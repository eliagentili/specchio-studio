#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
crypto_version=3.6.5
crypto_source=".build/crypto-source/openssl-${crypto_version}"
crypto_build=".build/crypto-${crypto_version}"
# Configure and compile in fresh directories so no previous version can survive.
rm -rf "$crypto_source" "$crypto_build"
mkdir -p .build/crypto-source "$crypto_build"
tar -xzf "ThirdParty/OpenSSL/openssl-${crypto_version}-source.tar.gz" -C .build/crypto-source
cd "$crypto_build"
"../crypto-source/openssl-${crypto_version}/Configure" darwin64-arm64-cc no-shared no-tests no-module no-legacy -mmacosx-version-min=14.0
make -j6 build_libs
cp libcrypto.a ../../ThirdParty/OpenSSL/lib/libcrypto.a
# Public headers come from both the source and generated build directories.
# Replace the entire installed tree rather than retaining headers from an older release.
rm -rf ../../ThirdParty/OpenSSL/include
mkdir -p ../../ThirdParty/OpenSSL/include/openssl
cp -R "../crypto-source/openssl-${crypto_version}/include/openssl/." ../../ThirdParty/OpenSSL/include/openssl/
cp -R include/openssl/. ../../ThirdParty/OpenSSL/include/openssl/
