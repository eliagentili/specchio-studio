/* Offline regressions for Specchio Studio's locally hardened PIN pairing.
 * The test client below implements SRP-6a equations using fixed private a and
 * the public RFC 5054 2048-bit group. It is compiled only into this test binary;
 * no listener, device, credentials, persistent key file or external service is used.
 */
#include <stdbool.h>
#include <assert.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/bn.h>
#include <openssl/evp.h>
#include "pairing.h"
/* Access the real static handler without starting the daemon or opening sockets. */
#include "../ThirdParty/UxPlay/lib/raop.c"

static const char *group_n =
    "AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050A37329CBB4"
    "A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50E8083969EDB767B0CF60"
    "95179A163AB3661A05FBD5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF"
    "747359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A436C6481F1D2B907"
    "8717461A5B9D32E688F87748544523B524B0D57D5EA77A2775D2ECFA032CFBDBF52FB37861"
    "60279004E57AE6AF874E7303CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DB"
    "FBB694B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F9E4AFF73";
static const char *test_user = "00:11:22:33:44:55";
static const char *test_pin = "4826";

typedef struct {
    unsigned char bytes[2048];
    size_t length;
} input_t;

static void append(input_t *input, const void *data, size_t length) {
    assert(input->length + length <= sizeof(input->bytes));
    memcpy(input->bytes + input->length, data, length);
    input->length += length;
}
static void append_bn(input_t *input, const BIGNUM *number, int width) {
    int length = width ? width : BN_num_bytes(number);
    assert(length > 0 && input->length + length <= sizeof(input->bytes));
    assert(BN_bn2binpad(number, input->bytes + input->length, length) == length);
    input->length += length;
}
static void digest(input_t *input, const EVP_MD *algorithm, unsigned char *out) {
    unsigned int length;
    assert(EVP_Digest(input->bytes, input->length, out, &length, algorithm, NULL) == 1);
    assert(length == (unsigned int)EVP_MD_get_size(algorithm));
}
static BIGNUM *hash_pair(const BIGNUM *first, const BIGNUM *second) {
    input_t input = {0};
    unsigned char output[20];
    append_bn(&input, first, SRP_PK_SIZE);
    append_bn(&input, second, SRP_PK_SIZE);
    digest(&input, EVP_sha1(), output);
    return BN_bin2bn(output, sizeof(output), NULL);
}

typedef struct {
    unsigned char public_key[SRP_PK_SIZE];
    int public_length;
    unsigned char proof[SRP_PROOF_SIZE];
    unsigned char server_proof[SRP_PROOF_SIZE];
    unsigned char key[SRP_SESSION_KEY_SIZE];
} test_client_t;

/* Client a is deliberately fixed for reproducible tests, never production. */
static test_client_t make_client(const unsigned char *salt, int salt_length,
                                 const unsigned char *server, int server_length) {
    test_client_t client = {0};
    BN_CTX *context = BN_CTX_new();
    assert(context);
    BN_CTX_start(context);
    BIGNUM *n = BN_CTX_get(context), *g = BN_CTX_get(context);
    BIGNUM *a = BN_CTX_get(context), *A = BN_CTX_get(context);
    BIGNUM *s = BN_CTX_get(context), *B = BN_CTX_get(context);
    BIGNUM *x = BN_CTX_get(context), *gx = BN_CTX_get(context);
    BIGNUM *base = BN_CTX_get(context), *exponent = BN_CTX_get(context);
    BIGNUM *shared = BN_CTX_get(context);
    assert(shared && BN_hex2bn(&n, group_n));
    assert(BN_set_word(g, 2));
    assert(BN_hex2bn(&a, "5A17C94DB630FC4B9012D6758F0AE32D81839E711CDF23B44A916C32DB942F60"));
    assert(BN_bin2bn(salt, salt_length, s) && BN_bin2bn(server, server_length, B));
    assert(BN_mod_exp(A, g, a, n, context));
    client.public_length = BN_bn2bin(A, client.public_key);
    BIGNUM *u = hash_pair(A, B), *k = hash_pair(n, g);
    assert(u && k);
    unsigned char inner[20], output[64];
    input_t input = {0};
    append(&input, test_user, strlen(test_user)); append(&input, ":", 1);
    append(&input, test_pin, strlen(test_pin)); digest(&input, EVP_sha1(), inner);
    input.length = 0; append_bn(&input, s, 0); append(&input, inner, sizeof(inner));
    digest(&input, EVP_sha1(), output); assert(BN_bin2bn(output, 20, x));
    /* S = (B - k*g^x) ^ (a + u*x) mod N */
    assert(BN_mod_exp(gx, g, x, n, context));
    assert(BN_mod_mul(base, k, gx, n, context));
    assert(BN_mod_sub(base, B, base, n, context));
    assert(BN_mul(exponent, u, x, context) && BN_add(exponent, exponent, a));
    assert(BN_mod_exp(shared, base, exponent, n, context));
    for (unsigned char suffix = 0; suffix < 2; suffix++) {
        const unsigned char counter[4] = {0, 0, 0, suffix};
        input.length = 0; append_bn(&input, shared, 0); append(&input, counter, 4);
        digest(&input, EVP_sha1(), client.key + 20 * suffix);
    }
    unsigned char hn[20], hg[20], hi[20];
    input.length = 0; append_bn(&input, n, 0); digest(&input, EVP_sha1(), hn);
    input.length = 0; append_bn(&input, g, 0); digest(&input, EVP_sha1(), hg);
    input.length = 0; append(&input, test_user, strlen(test_user)); digest(&input, EVP_sha1(), hi);
    for (int i = 0; i < 20; i++) hn[i] ^= hg[i];
    input.length = 0; append(&input, hn, 20); append(&input, hi, 20);
    append_bn(&input, s, 0); append_bn(&input, A, 0); append_bn(&input, B, 0);
    append(&input, client.key, sizeof(client.key)); digest(&input, EVP_sha1(), client.proof);
    input.length = 0; append_bn(&input, A, 0); append(&input, client.proof, sizeof(client.proof));
    append(&input, client.key, sizeof(client.key)); digest(&input, EVP_sha1(), client.server_proof);
    BN_free(u); BN_free(k); BN_CTX_end(context); BN_CTX_free(context);
    return client;
}

static test_client_t begin(pairing_session_t *session, pairing_t *pairing) {
    const char *salt = NULL, *server = NULL;
    int salt_length = 0, server_length = 0;
    assert(srp_new_user(session, pairing, test_user, test_pin,
                        &salt, &salt_length, &server, &server_length) == 0);
    assert(salt && salt_length > 0 && salt_length <= SRP_SALT_SIZE);
    assert(server && server_length > 0 && server_length <= SRP_PK_SIZE);
    test_client_t client = make_client((const unsigned char *)salt, salt_length,
                                      (const unsigned char *)server, server_length);
    free((void *)server);
    return client;
}
static void no_client_identity(pairing_session_t *session) {
    char *username = NULL, *key = (char *)1;
    get_pairing_session_client_data(session, &username, &key);
    assert(username && key == NULL);
}
static void verify(pairing_session_t *session, pairing_t *pairing, test_client_t *client) {
    /* Exactly 20 allocated bytes catches the former 64-byte SHA-1 copy under ASan. */
    unsigned char *proof = malloc(SRP_PROOF_SIZE);
    assert(proof); memcpy(proof, client->proof, SRP_PROOF_SIZE);
    assert(srp_validate_proof(session, pairing, client->public_key,
                              client->public_length, proof, SRP_PROOF_SIZE) == 0);
    assert(memcmp(proof, client->server_proof, SRP_PROOF_SIZE) == 0);
    assert(srp_validate_proof(session, pairing, client->public_key,
                              client->public_length, proof, SRP_PROOF_SIZE) < 0);
    free(proof);
}
static void setup_cipher(const test_client_t *client, unsigned char *key, unsigned char *iv) {
    unsigned char output[64];
    input_t input = {0};
    const char *label = "Pair-Setup-AES-Key";
    append(&input, label, strlen(label)); append(&input, client->key, sizeof(client->key));
    digest(&input, EVP_sha512(), output); memcpy(key, output, 16);
    input.length = 0; label = "Pair-Setup-AES-IV";
    append(&input, label, strlen(label)); append(&input, client->key, sizeof(client->key));
    digest(&input, EVP_sha512(), output); memcpy(iv, output, 16); iv[15]++;
}
static void confirm(pairing_session_t *session, pairing_t *pairing, const test_client_t *client, bool valid) {
    unsigned char key[16], iv[16], original[32], encrypted[32], tag[16], result[32], expected[32];
    setup_cipher(client, key, iv);
    for (int i = 0; i < 32; i++) original[i] = (unsigned char)(i + 1);
    assert(gcm_encrypt(original, sizeof(original), encrypted, key, iv, tag) == 32);
    if (!valid) tag[0] ^= 1;
    int status = srp_confirm_pair_setup(session, pairing, encrypted, tag);
    if (valid) {
        assert(status == 32); iv[15]++;
        assert(gcm_decrypt(encrypted, sizeof(encrypted), result, key, iv, tag) == 32);
        pairing_get_public_key(pairing, expected); assert(memcmp(result, expected, 32) == 0);
        char *username = NULL, *encoded = NULL;
        get_pairing_session_client_data(session, &username, &encoded);
        assert(username && strcmp(username, test_user) == 0 && encoded);
        unsigned char decoded[48] = {0};
        assert(EVP_DecodeBlock(decoded, (const unsigned char *)encoded, (int)strlen(encoded)) >= 32);
        assert(memcmp(decoded, original, 32) == 0); free(encoded);
    } else {
        assert(status < 0); no_client_identity(session);
    }
    assert(srp_confirm_pair_setup(session, pairing, encrypted, tag) < 0);
}

static void test_null_arguments(pairing_t *pairing) {
    pairing_session_t *session = pairing_session_init(pairing);
    const char *salt = NULL, *server = NULL; int sl = 0, bl = 0;
    assert(srp_new_user(NULL, pairing, test_user, test_pin, &salt, &sl, &server, &bl) < 0);
    assert(srp_new_user(session, NULL, test_user, test_pin, &salt, &sl, &server, &bl) < 0);
    assert(srp_new_user(session, pairing, NULL, test_pin, &salt, &sl, &server, &bl) < 0);
    assert(srp_new_user(session, pairing, test_user, NULL, &salt, &sl, &server, &bl) < 0);
    assert(srp_new_user(session, pairing, test_user, test_pin, NULL, &sl, &server, &bl) < 0);
    assert(srp_new_user(session, pairing, test_user, test_pin, &salt, NULL, &server, &bl) < 0);
    assert(srp_new_user(session, pairing, test_user, test_pin, &salt, &sl, NULL, &bl) < 0);
    assert(srp_new_user(session, pairing, test_user, test_pin, &salt, &sl, &server, NULL) < 0);
    test_client_t client = begin(session, pairing); verify(session, pairing, &client);
    unsigned char epk[32] = {0}, tag[16] = {0};
    assert(srp_confirm_pair_setup(NULL, pairing, epk, tag) < 0);
    assert(srp_confirm_pair_setup(session, NULL, epk, tag) < 0);
    assert(srp_confirm_pair_setup(session, pairing, NULL, tag) < 0);
    assert(srp_confirm_pair_setup(session, pairing, epk, NULL) < 0);
    confirm(session, pairing, &client, true);
    pairing_session_destroy(session);
}

static void test_order_and_lengths(pairing_t *pairing) {
    pairing_session_t *session = pairing_session_init(pairing);
    unsigned char proof[SRP_PROOF_SIZE] = {0}, point[SRP_PK_SIZE] = {2}, epk[32] = {0}, tag[16] = {0};
    assert(session && pairing_session_init(NULL) == NULL);
    assert(srp_validate_proof(session, pairing, point, sizeof(point), proof, sizeof(proof)) < 0);
    assert(srp_confirm_pair_setup(session, pairing, epk, tag) < 0);
    no_client_identity(session);
    test_client_t client = begin(session, pairing);
    assert(srp_confirm_pair_setup(session, pairing, epk, tag) < 0);
    unsigned char *one_byte = malloc(1); assert(one_byte); *one_byte = 2;
    const int invalid_points[] = {-1, 0, SRP_PK_SIZE + 1, INT_MAX};
    for (size_t i = 0; i < sizeof(invalid_points) / sizeof(*invalid_points); i++)
        assert(srp_validate_proof(session, pairing, one_byte, invalid_points[i], proof, sizeof(proof)) < 0);
    const int invalid_proofs[] = {-1, 0, 1, SRP_PROOF_SIZE - 1, SRP_PROOF_SIZE + 1, 64, INT_MAX};
    for (size_t i = 0; i < sizeof(invalid_proofs) / sizeof(*invalid_proofs); i++)
        assert(srp_validate_proof(session, pairing, client.public_key, client.public_length,
                                  one_byte, invalid_proofs[i]) < 0);
    assert(srp_validate_proof(NULL, pairing, one_byte, 1, proof, sizeof(proof)) < 0);
    assert(srp_validate_proof(session, NULL, one_byte, 1, proof, sizeof(proof)) < 0);
    assert(srp_validate_proof(session, pairing, NULL, 1, proof, sizeof(proof)) < 0);
    assert(srp_validate_proof(session, pairing, one_byte, 1, NULL, sizeof(proof)) < 0);
    free(one_byte);
    verify(session, pairing, &client); confirm(session, pairing, &client, true);
    /* Restarting the same session must forget a formerly confirmed client. */
    client = begin(session, pairing); no_client_identity(session);
    verify(session, pairing, &client); confirm(session, pairing, &client, false);
    client = begin(session, pairing); verify(session, pairing, &client); confirm(session, pairing, &client, true);
    pairing_session_destroy(session);
    puts("PASS: PIN pairing ordered SRP proof and authenticated key exchange; exact proof buffer and malformed lengths under ASan");
}

static void test_failure_and_restart(pairing_t *pairing) {
    pairing_session_t *session = pairing_session_init(pairing);
    test_client_t client = begin(session, pairing);
    unsigned char invalid[SRP_PROOF_SIZE] = {0}, epk[32] = {0}, tag[16] = {0};
    assert(srp_validate_proof(session, pairing, client.public_key, client.public_length, invalid, sizeof(invalid)) < 0);
    assert(srp_validate_proof(session, pairing, client.public_key, client.public_length, client.proof, sizeof(client.proof)) < 0);
    assert(srp_confirm_pair_setup(session, pairing, epk, tag) < 0);
    client = begin(session, pairing);
    const char *salt = (char *)1, *server = (char *)1; int sl = 1, bl = 1;
    char too_long[SRP_USERNAME_SIZE + 2]; memset(too_long, 'a', sizeof(too_long) - 1); too_long[sizeof(too_long) - 1] = '\0';
    assert(srp_new_user(session, pairing, too_long, test_pin, &salt, &sl, &server, &bl) < 0);
    assert(salt == NULL && server == NULL && sl == 0 && bl == 0);
    assert(srp_validate_proof(session, pairing, client.public_key, client.public_length, client.proof, sizeof(client.proof)) < 0);
    no_client_identity(session);
    /* A zero SRP public value must fail safely and invalidate this attempt. */
    client = begin(session, pairing);
    unsigned char zero = 0;
    assert(srp_validate_proof(session, pairing, &zero, 1, invalid, sizeof(invalid)) < 0);
    assert(srp_confirm_pair_setup(session, pairing, epk, tag) < 0);
    client = begin(session, pairing); verify(session, pairing, &client); confirm(session, pairing, &client, true);
    pairing_session_destroy(session);
    puts("PASS: PIN pairing invalid proof, invalid public value, invalid restart, recovery and authentication failure clear state");
}

/* Serialize and parse an in-memory RTSP request, then call the shipped handler.
 * No connection creation, daemon startup or networking function is invoked. */
static plist_t handler_request(raop_conn_t *connection, plist_t content, int expected_code) {
    char *body = NULL; uint32_t body_length = 0;
    plist_to_bin(content, &body, &body_length);
    assert(body && body_length > 0);
    char header[256];
    int header_length = snprintf(header, sizeof(header),
        "POST /pair-setup-pin RTSP/1.0\r\nContent-Type: application/x-apple-binary-plist\r\nContent-Length: %u\r\nCSeq: 1\r\n\r\n", body_length);
    assert(header_length > 0 && header_length < sizeof(header));
    http_request_t *request = http_request_init();
    assert(request);
    assert(http_request_add_data(request, header, header_length) == 0);
    assert(http_request_add_data(request, body, (int)body_length) == 0);
    free(body);
    assert(!http_request_has_error(request) && http_request_is_complete(request));
    http_response_t *response = http_response_create();
    http_response_init(response, "RTSP/1.0", 200, "OK");
    char *response_body = NULL; int response_length = 0;
    raop_handler_pairsetup_pin(connection, request, response, &response_body, &response_length);
    http_response_finish(response, response_body, response_length);
    int wire_length = 0;
    const char *wire = http_response_get_data(response, &wire_length);
    char status[32]; int status_length = snprintf(status, sizeof(status), "RTSP/1.0 %d ", expected_code);
    assert(wire && wire_length >= status_length && memcmp(wire, status, status_length) == 0);
    plist_t result = NULL;
    if (expected_code == 200) {
        assert(response_body && response_length > 0);
        plist_from_bin(response_body, (uint32_t)response_length, &result);
        assert(PLIST_IS_DICT(result));
    } else {
        assert(response_body == NULL && response_length == 0);
    }
    free(response_body);
    http_response_destroy(response); http_request_destroy(request);
    return result;
}
static plist_t blob_request(const char *first, int first_length, const char *second, int second_length) {
    const char zeros[SRP_PK_SIZE + 1] = {0};
    plist_t content = plist_new_dict();
    plist_dict_set_item(content, first, plist_new_data(zeros, first_length));
    plist_dict_set_item(content, second, plist_new_data(zeros, second_length));
    return content;
}
typedef struct { int registrations; } test_registration_t;
static void registered_client(void *context, const char *user, const char *public_key, const char *name) {
    test_registration_t *registration = context;
    assert(user && strcmp(user, test_user) == 0 && public_key && name);
    unsigned char decoded[48] = {0};
    assert(EVP_DecodeBlock(decoded, (const unsigned char *)public_key, (int)strlen(public_key)) >= 32);
    assert(decoded[0] == 7);
    for (int i = 1; i < 32; i++) assert(decoded[i] == 0);
    registration->registrations++;
}
static void test_handler_boundaries(pairing_t *pairing) {
    raop_t receiver = {0};
    receiver.pairing = pairing; receiver.pin = 4826;
    test_registration_t registration = {0};
    receiver.callbacks.cls = &registration; receiver.callbacks.register_client = registered_client;
    receiver.logger = logger_init(); assert(receiver.logger);
    logger_set_level(receiver.logger, LOGGER_EMERG);
    raop_conn_t connection = {0}; connection.raop = &receiver;
    connection.session = pairing_session_init(pairing); assert(connection.session);
    plist_t content = plist_new_array();
    assert(handler_request(&connection, content, 470) == NULL); plist_free(content);
    content = plist_new_dict();
    plist_dict_set_item(content, "method", plist_new_uint(1));
    plist_dict_set_item(content, "user", plist_new_string(test_user));
    assert(handler_request(&connection, content, 470) == NULL); plist_free(content);
    content = plist_new_dict();
    plist_dict_set_item(content, "method", plist_new_string("invalid"));
    plist_dict_set_item(content, "user", plist_new_string(test_user));
    assert(handler_request(&connection, content, 470) == NULL); plist_free(content);
    /* Boundary failures must be rejected even before an SRP session exists. */
    const int proof_lengths[] = {0, 1, 19, 21, 64};
    for (size_t i = 0; i < sizeof(proof_lengths) / sizeof(*proof_lengths); i++) {
        content = blob_request("pk", 256, "proof", proof_lengths[i]);
        assert(handler_request(&connection, content, 470) == NULL); plist_free(content);
    }
    const int point_lengths[] = {0, 257};
    for (size_t i = 0; i < sizeof(point_lengths) / sizeof(*point_lengths); i++) {
        content = blob_request("pk", point_lengths[i], "proof", 20);
        assert(handler_request(&connection, content, 470) == NULL); plist_free(content);
    }
    const int epk_lengths[] = {0, 1, 31, 33};
    for (size_t i = 0; i < sizeof(epk_lengths) / sizeof(*epk_lengths); i++) {
        content = blob_request("epk", epk_lengths[i], "authTag", 16);
        assert(handler_request(&connection, content, 470) == NULL); plist_free(content);
    }
    const int tag_lengths[] = {0, 1, 15, 17};
    for (size_t i = 0; i < sizeof(tag_lengths) / sizeof(*tag_lengths); i++) {
        content = blob_request("epk", 32, "authTag", tag_lengths[i]);
        assert(handler_request(&connection, content, 470) == NULL); plist_free(content);
    }
    assert(registration.registrations == 0);
    /* Complete the same three handler requests a legitimate client sends. */
    content = plist_new_dict();
    plist_dict_set_item(content, "method", plist_new_string("pin"));
    plist_dict_set_item(content, "user", plist_new_string(test_user));
    plist_t result = handler_request(&connection, content, 200); plist_free(content);
    uint64_t sl = 0, bl = 0; char *salt = NULL, *server = NULL;
    plist_get_data_val(plist_dict_get_item(result, "salt"), &salt, &sl);
    plist_get_data_val(plist_dict_get_item(result, "pk"), &server, &bl);
    assert(sl > 0 && sl <= SRP_SALT_SIZE && bl > 0 && bl <= SRP_PK_SIZE);
    test_client_t client = make_client((unsigned char *)salt, (int)sl, (unsigned char *)server, (int)bl);
    free(salt); free(server); plist_free(result);
    content = plist_new_dict();
    plist_dict_set_item(content, "pk", plist_new_data((char *)client.public_key, client.public_length));
    plist_dict_set_item(content, "proof", plist_new_data((char *)client.proof, sizeof(client.proof)));
    result = handler_request(&connection, content, 200); plist_free(content);
    uint64_t proof_length = 0; char *proof = NULL;
    plist_get_data_val(plist_dict_get_item(result, "proof"), &proof, &proof_length);
    assert(proof && proof_length == SRP_PROOF_SIZE && memcmp(proof, client.server_proof, SRP_PROOF_SIZE) == 0);
    free(proof); plist_free(result);
    unsigned char key[16], iv[16], original[32] = {7}, encrypted[32], tag[16];
    setup_cipher(&client, key, iv);
    assert(gcm_encrypt(original, sizeof(original), encrypted, key, iv, tag) == 32);
    content = plist_new_dict();
    plist_dict_set_item(content, "epk", plist_new_data((char *)encrypted, sizeof(encrypted)));
    plist_dict_set_item(content, "authTag", plist_new_data((char *)tag, sizeof(tag)));
    result = handler_request(&connection, content, 200); plist_free(content);
    uint64_t epk_length = 0, tag_length = 0; char *server_epk = NULL, *server_tag = NULL;
    plist_get_data_val(plist_dict_get_item(result, "epk"), &server_epk, &epk_length);
    plist_get_data_val(plist_dict_get_item(result, "authTag"), &server_tag, &tag_length);
    assert(epk_length == 32 && tag_length == 16);
    unsigned char actual[32], expected[32]; iv[15]++;
    assert(gcm_decrypt((unsigned char *)server_epk, 32, actual, key, iv, (unsigned char *)server_tag) == 32);
    pairing_get_public_key(pairing, expected); assert(memcmp(actual, expected, 32) == 0);
    free(server_epk); free(server_tag); plist_free(result);
    assert(pairing_session_check_handshake_status(connection.session) == 0);
    assert(registration.registrations == 1);
    pairing_session_destroy(connection.session); logger_destroy(receiver.logger);
    puts("PASS: real PIN pairing handler rejects malformed plist types and blob boundaries with RTSP 470 and completes all three valid requests offline");
}

int main(void) {
    int result = -1;
    pairing_t *pairing = pairing_init_generate(test_user, "", &result);
    assert(pairing && result == 0);
    test_null_arguments(pairing); test_order_and_lengths(pairing); test_failure_and_restart(pairing);
    test_handler_boundaries(pairing);
    /* Exercise repeated initialization/cleanup with independently generated server data. */
    for (int i = 0; i < 64; i++) {
        pairing_session_t *session = pairing_session_init(pairing);
        test_client_t client = begin(session, pairing);
        verify(session, pairing, &client); confirm(session, pairing, &client, true);
        pairing_session_destroy(session);
    }
    pairing_destroy(pairing);
    puts("PASS: PIN pairing 64 repeated successful setup/proof/confirm sessions without stale state or sanitizer errors");
    return 0;
}
