#import "WirelessBridge.h"
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AudioToolbox/AudioToolbox.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <sys/select.h>
#include "raop.h"

@interface SSReceiver : NSObject {
@public
    void *_context;
    SSWirelessSample _sample;
    SSWirelessEvent _event;
    raop_t *_raop;
    dnssd_t *_dnssd;
    pthread_t _dnsThread;
    BOOL _hasThread;
    atomic_bool _dnsStop;
    VTDecompressionSessionRef _decoder;
    CMVideoFormatDescriptionRef _format;
    NSMutableDictionary<NSNumber *,NSData *> *_parameters;
    AudioConverterRef _audioDecoder;
    unsigned char _audioCodec;
    unsigned short _audioFrames;
    BOOL _streamActive;
    uint16_t _port;
    NSMutableSet<NSString *> *_paired;
    NSString *_pairPath;
    FILE *_diagnostics;
}
- (void)video:(const unsigned char *)bytes length:(int)length hevc:(BOOL)hevc time:(uint64_t)time;
- (void)audio:(audio_decode_struct *)packet;
- (void)clearDecoder;
@end

static SSReceiver *receiver(void *p) { return (__bridge SSReceiver *)p; }
static CMTime presentationTime(uint64_t ntp) {
    CMTime host = CMClockGetTime(CMClockGetHostTimeClock());
    if (!ntp) return host;
    double delta = ((int64_t)ntp - (int64_t)get_local_time()) / 1e9;
    if (!isfinite(delta) || fabs(delta) > 2) return host;
    return CMTimeAdd(host, CMTimeMakeWithSeconds(delta, 1000000000));
}
static void sendEvent(SSReceiver *r, int event, NSString *text) {
    if (r->_event) r->_event(r->_context, event, text.UTF8String);
}
static void decoded(void *ref, void *frame, OSStatus status, VTDecodeInfoFlags flags, CVImageBufferRef image, CMTime pts, CMTime duration) {
    SSReceiver *r = receiver(ref);
    if (status || !image) return;
    CMVideoFormatDescriptionRef fmt = NULL;
    CMSampleBufferRef sample = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(NULL,image,&fmt)) return;
    CMSampleTimingInfo timing = {duration,pts,kCMTimeInvalid};
    if (!CMSampleBufferCreateReadyWithImageBuffer(NULL,image,fmt,&timing,&sample)) {
        r->_sample(r->_context,sample,true);
        CFRelease(sample);
    }
    CFRelease(fmt);
}

typedef struct { const unsigned char *data; UInt32 length; BOOL consumed; AudioStreamPacketDescription description; } AudioPacket;
static OSStatus supplyAudio(AudioConverterRef converter, UInt32 *count, AudioBufferList *buffers, AudioStreamPacketDescription **desc, void *ctx) {
    AudioPacket *p = ctx;
    if (p->consumed) { *count = 0; return -1; }
    p->consumed = YES;
    buffers->mNumberBuffers = 1;
    buffers->mBuffers[0] = (AudioBuffer){2,p->length,(void *)p->data};
    p->description = (AudioStreamPacketDescription){0,0,p->length};
    if (desc) *desc = &p->description;
    *count = 1;
    return noErr;
}

@implementation SSReceiver
- (instancetype)init {
    if ((self = [super init])) {
        _parameters = [NSMutableDictionary new];
        _paired = [NSMutableSet new];
        atomic_init(&_dnsStop, true);
        _audioFrames = 480;
    }
    return self;
}
- (void)clearDecoder {
    if (_decoder) {
        VTDecompressionSessionWaitForAsynchronousFrames(_decoder);
        VTDecompressionSessionInvalidate(_decoder); CFRelease(_decoder); _decoder = NULL;
    }
    if (_format) { CFRelease(_format); _format = NULL; }
    [_parameters removeAllObjects];
}
- (void)video:(const unsigned char *)bytes length:(int)length hevc:(BOOL)hevc time:(uint64_t)time {
    @autoreleasepool { @synchronized(self) {
        if (!bytes || length <= 4 || length > 32*1024*1024) return;
        NSMutableArray<NSData *> *nals = [NSMutableArray new];
        int start = -1;
        for (int i=0; i+3<length;) {
            int prefix = bytes[i]==0 && bytes[i+1]==0 && bytes[i+2]==1 ? 3 :
                (bytes[i]==0 && bytes[i+1]==0 && bytes[i+2]==0 && bytes[i+3]==1 ? 4 : 0);
            if (prefix) {
                if (start>=0 && i>start) [nals addObject:[NSData dataWithBytes:bytes+start length:i-start]];
                start=i+prefix; i=start;
            } else i++;
        }
        if (start<0 || start>=length) return;
        [nals addObject:[NSData dataWithBytes:bytes+start length:length-start]];
        BOOL changed = NO, hasPicture = NO;
        NSMutableData *avcc = [NSMutableData new];
        for (NSData *nal in nals) {
            const uint8_t *b = nal.bytes;
            int type = hevc ? ((b[0]>>1)&63) : (b[0]&31);
            BOOL parameter = hevc ? (type>=32 && type<=34) : (type==7 || type==8);
            if (parameter) {
                if (![_parameters[@(type)] isEqual:nal]) { _parameters[@(type)] = nal; changed = YES; }
            } else {
                if (hevc ? type<=31 : (type>=1 && type<=5)) hasPicture = YES;
                uint32_t size = CFSwapInt32HostToBig((uint32_t)nal.length);
                [avcc appendBytes:&size length:4]; [avcc appendData:nal];
            }
        }
        // Parameter sets from a previous connection may be byte-identical. A
        // codec change or an invalidated session still needs a fresh decoder.
        CMVideoCodecType requestedCodec = hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264;
        if (changed || !_format || !_decoder || CMFormatDescriptionGetMediaSubType(_format) != requestedCodec) {
            NSArray<NSNumber *> *types = hevc ? @[@32,@33,@34] : @[@7,@8];
            const uint8_t *sets[3]; size_t sizes[3]; BOOL complete = YES;
            for (int i=0;i<types.count;i++) {
                NSData *d = _parameters[types[i]]; if (!d) { complete=NO; break; }
                sets[i] = d.bytes; sizes[i] = d.length;
            }
            if (!complete) return;
            CMVideoFormatDescriptionRef next = NULL;
            OSStatus err = hevc ? CMVideoFormatDescriptionCreateFromHEVCParameterSets(NULL,3,sets,sizes,4,NULL,&next)
                : CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL,2,sets,sizes,4,&next);
            if (err || !next) return;
            if (_decoder) { VTDecompressionSessionWaitForAsynchronousFrames(_decoder); VTDecompressionSessionInvalidate(_decoder); CFRelease(_decoder); _decoder=NULL; }
            if (_format) CFRelease(_format); _format=next;
            NSDictionary *attrs = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:@{}};
            VTDecompressionOutputCallbackRecord callback = {decoded,(__bridge void *)self};
            err = VTDecompressionSessionCreate(NULL,_format,NULL,(__bridge CFDictionaryRef)attrs,&callback,&_decoder);
            if (err) { sendEvent(self,6,[NSString stringWithFormat:@"Video decoding is unavailable (%d)",(int)err]); return; }
        }
        if (!hasPicture || !_decoder || !avcc.length) return;
        CMBlockBufferRef block = NULL; CMSampleBufferRef sample = NULL;
        if (CMBlockBufferCreateWithMemoryBlock(NULL,NULL,avcc.length,NULL,NULL,0,avcc.length,0,&block)) return;
        CMBlockBufferReplaceDataBytes(avcc.bytes,block,0,avcc.length);
        CMSampleTimingInfo timing = {kCMTimeInvalid,presentationTime(time),kCMTimeInvalid};
        size_t sampleSize = avcc.length;
        if (!CMSampleBufferCreateReady(NULL,block,_format,1,1,&timing,1,&sampleSize,&sample)) {
            if (!_streamActive) { _streamActive=YES; sendEvent(self,2,@"iPhone/iPad connected wirelessly"); }
            OSStatus err = VTDecompressionSessionDecodeFrame(_decoder,sample,0,NULL,NULL);
            if (err == kVTInvalidSessionErr) { VTDecompressionSessionInvalidate(_decoder); CFRelease(_decoder); _decoder=NULL; }
            CFRelease(sample);
        }
        CFRelease(block);
    } }
}
- (void)audio:(audio_decode_struct *)packet {
    @autoreleasepool { @synchronized(self) {
        if (!packet || !packet->data || packet->data_len<=0 || packet->data_len>32*1024*1024) return;
        unsigned char codec = packet->ct;
        if (codec!=1 && codec!=2 && codec!=4 && codec!=8) return;
        AudioStreamBasicDescription pcm = {44100,kAudioFormatLinearPCM,kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked,4,1,4,2,16,0};
        uint8_t output[16384]; UInt32 frames = 4096;
        if (codec==1) { frames=MIN(packet->data_len/4,4096); memcpy(output,packet->data,frames*4); }
        else {
            if (!_audioDecoder || codec!=_audioCodec) {
                if (_audioDecoder) { AudioConverterDispose(_audioDecoder); _audioDecoder=NULL; }
                AudioStreamBasicDescription compressed = {0};
                compressed.mSampleRate=44100; compressed.mChannelsPerFrame=2;
                compressed.mFormatID=codec==8 ? kAudioFormatMPEG4AAC_ELD : codec==4 ? kAudioFormatMPEG4AAC : kAudioFormatAppleLossless;
                compressed.mFramesPerPacket=codec==8 ? 480 : codec==4 ? 1024 : 352;
                if (AudioConverterNew(&compressed,&pcm,&_audioDecoder)) return;
                _audioCodec=codec;
                const uint8_t eld[]={0xf8,0xe8,0x50,0x00}, lc[]={0x12,0x10};
                const uint8_t alac[]={0,0,1,0x60,0,0x10,0x28,0x0a,0x0e,2,0,0xff,0,0,0,0,0,0,0,0,0,0,0xac,0x44};
                const void *cookie=codec==8 ? eld : codec==4 ? lc : alac;
                UInt32 size=codec==8 ? sizeof(eld) : codec==4 ? sizeof(lc) : sizeof(alac);
                AudioConverterSetProperty(_audioDecoder,kAudioConverterDecompressionMagicCookie,size,cookie);
            }
            AudioPacket input={packet->data,(UInt32)packet->data_len,NO,{0}};
            AudioBufferList list={1,{{2,sizeof(output),output}}};
            OSStatus err=AudioConverterFillComplexBuffer(_audioDecoder,supplyAudio,&input,&frames,&list,NULL);
            if ((err && err!=-1) || !frames) return;
            frames=MIN(frames,4096);
        }
        CMAudioFormatDescriptionRef format=NULL; CMBlockBufferRef block=NULL; CMSampleBufferRef sample=NULL;
        if (CMAudioFormatDescriptionCreate(NULL,&pcm,0,NULL,0,NULL,NULL,&format)) return;
        size_t bytes=frames*4;
        if (!CMBlockBufferCreateWithMemoryBlock(NULL,NULL,bytes,NULL,NULL,0,bytes,0,&block)) {
            CMBlockBufferReplaceDataBytes(output,block,0,bytes);
            CMSampleTimingInfo timing={CMTimeMake(1,44100),presentationTime(packet->ntp_time_local),kCMTimeInvalid};
            size_t frameSize=4;
            if (!CMSampleBufferCreateReady(NULL,block,format,frames,1,&timing,1,&frameSize,&sample)) {
                _sample(_context,sample,false); CFRelease(sample);
            }
            CFRelease(block);
        }
        CFRelease(format);
    } }
}
@end

static void pairingStage(SSReceiver *r,const char *stage) {
    if(r->_diagnostics) { flockfile(r->_diagnostics); fprintf(r->_diagnostics,"%.3f %s\n",NSDate.date.timeIntervalSince1970,stage); fflush(r->_diagnostics); funlockfile(r->_diagnostics); }
}
static void protocolLog(void *ctx,int level,const char *message) {
    // UxPlay requires a non-null logger even when only warnings are enabled.
    // Keep protocol diagnostics local; no client payloads are logged at this level.
    SSReceiver *r=receiver(ctx);
    const char *stage=NULL;
    if(strstr(message,"client sent PAIR-PIN-START")) stage="PIN_REQUEST";
    else if(strstr(message,"client requested pair-setup-pin")) stage="PAIR_SETUP_PACKET";
    else if(strstr(message,"failed to create user")) stage="SRP_INIT_FAILED";
    else if(strstr(message,"client proof not validated")) stage="SRP_PROOF_REJECTED";
    else if(strstr(message,"pair-pin-setup (step 3)")) stage="PAIR_CONFIRM_REJECTED";
    else if(strstr(message,"pair-pin-setup success")) stage="PAIR_SETUP_VERIFIED";
    else if(strstr(message,"Incorrect pair-verify signature")) stage="PAIR_VERIFY_REJECTED";
    else if(strstr(message,"pair-verify: signature is verified")) stage="PAIR_VERIFY_OK";
    else if(strstr(message,"raop_ntp error sending request")) stage="NTP_SEND_ERROR";
    if(stage) pairingStage(r,stage);
}
static void videoPacket(void *ctx, raop_ntp_t *ntp, video_decode_struct *data) { [receiver(ctx) video:data->data length:data->data_len hevc:data->is_h265 time:data->ntp_time_local]; }
static void audioPacket(void *ctx, raop_ntp_t *ntp, audio_decode_struct *data) { [receiver(ctx) audio:data]; }
static void nothing(void *ctx) {}
static void resetConnection(void *ctx,int reason) {}
static void volume(void *ctx,float value) {}
static double initialVolume(void *ctx) { return 0.0; }
static void metadata(void *ctx,const void *bytes,int length) {}
static void progress(void *ctx,uint32_t *a,uint32_t *b,uint32_t *c) {}
static int codec(void *ctx, video_codec_t value) { return value==VIDEO_CODEC_H264 || value==VIDEO_CODEC_H265 ? 0 : -1; }
static void audioFormat(void *ctx,unsigned char *ct,unsigned short *spf,bool *screen,bool *media,uint64_t *fmt) { receiver(ctx)->_audioFrames=*spf; }
static void reportSize(void *ctx,float *a,float *b,float *c,float *d) {}
static void pin(void *ctx,char *value) { sendEvent(receiver(ctx),1,[NSString stringWithUTF8String:value]); }
static void registerClient(void *ctx,const char *id,const char *pk,const char *name) {
    SSReceiver *r=receiver(ctx);
    @synchronized(r) {
        NSString *key=[NSString stringWithUTF8String:pk];
        if(![r->_paired containsObject:key]) {
            [r->_paired addObject:key];
            if(r->_pairPath) { [r->_paired.allObjects writeToFile:r->_pairPath atomically:YES]; chmod(r->_pairPath.fileSystemRepresentation,0600); }
        }
        pairingStage(r,"VERIFIED_CLIENT_REGISTERED");
    }
}
static bool checkClient(void *ctx,const char *pk) {
    SSReceiver *r=receiver(ctx);
    @synchronized(r) { BOOL known=[r->_paired containsObject:[NSString stringWithUTF8String:pk]]; pairingStage(r,known ? "TRUSTED_CLIENT" : "UNKNOWN_CLIENT"); return known; }
}
static void admitClient(void *ctx,char *id,char *model,char *name,bool *admit) { *admit=true; }
static const char *password(void *ctx,int *len) { *len=0; return ""; }
static void dacp(void *ctx,const char *a,const char *b) {}
static void playUnsupported(void *ctx,const char *location,float position) { sendEvent(receiver(ctx),6,@"Use Screen Mirroring in Control Center to stream video."); }
static void seekUnsupported(void *ctx,float position) {}
static void playbackInfo(void *ctx,playback_info_t *info) { memset(info,0,sizeof(*info)); }
static float playlistRemove(void *ctx) { return 0; }
static void customProfile(void *ctx,const char **profile) { *profile=""; }
static void videoReset(void *ctx,reset_type_t reason) {
    SSReceiver *r=receiver(ctx);
    @synchronized(r) {
        BOOL active=r->_streamActive; r->_streamActive=NO; [r clearDecoder];
        if (r->_audioDecoder) { AudioConverterDispose(r->_audioDecoder); r->_audioDecoder=NULL; }
        if (active) sendEvent(r,3,@"Mirroring ended. The receiver is ready for a new connection.");
    }
}
static void mirrorRunning(void *ctx,bool running) {
    if(running) return;
    SSReceiver *r=receiver(ctx);
    pairingStage(r,"VIDEO_STREAM_ENDED");
    videoReset(ctx,RESET_TYPE_RTP_SHUTDOWN);
    // Ask the control server to release the old audio/timing connections.
    // This only marks connections for its own thread; it does not join this thread.
    if(r->_raop && !atomic_load(&r->_dnsStop)) raop_remove_known_connections(r->_raop);
}
static void *serveDNS(void *ctx) {
    SSReceiver *r=receiver(ctx);
    while (!atomic_load(&r->_dnsStop)) {
        fd_set set; FD_ZERO(&set); int max=-1;
        int fds[2]={dnssd_get_service_fd(r->_dnssd,0),dnssd_get_service_fd(r->_dnssd,1)};
        for (int i=0;i<2;i++) if (fds[i]>=0) { FD_SET(fds[i],&set); if (fds[i]>max) max=fds[i]; }
        struct timeval timeout={0,100000};
        if (select(max+1,&set,NULL,NULL,&timeout)>0) for(int i=0;i<2;i++) if(fds[i]>=0 && FD_ISSET(fds[i],&set)) {
            int err=dnssd_process_service(r->_dnssd,i);
            if(err) { sendEvent(r,6,@"Network announcement is unavailable. Check Local Network permission."); atomic_store(&r->_dnsStop,true); }
        }
    }
    return NULL;
}
void *SSWirelessCreate(void *context,SSWirelessSample sample,SSWirelessEvent event) {
    SSReceiver *r=[SSReceiver new]; r->_context=context; r->_sample=sample; r->_event=event;
    return (__bridge_retained void *)r;
}
int SSWirelessStart(void *ptr,const char *name,const char *deviceID,const char *keyPath) {
    SSReceiver *r=receiver(ptr); if(r->_raop) return 0;
    r->_pairPath=[[NSString stringWithUTF8String:keyPath] stringByAppendingString:@".clients.plist"];
    NSArray *saved=[NSArray arrayWithContentsOfFile:r->_pairPath];
    for(id key in saved) if([key isKindOfClass:NSString.class]) [r->_paired addObject:key];
    NSString *diag=[[[NSString stringWithUTF8String:keyPath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"connection-stages.txt"];
    r->_diagnostics=fopen(diag.fileSystemRepresentation,"w"); chmod(diag.fileSystemRepresentation,0600);
    unsigned char hw[6]; unsigned int parts[6];
    if(sscanf(deviceID,"%x:%x:%x:%x:%x:%x",&parts[0],&parts[1],&parts[2],&parts[3],&parts[4],&parts[5])!=6) return -1;
    for(int i=0;i<6;i++) hw[i]=(unsigned char)parts[i];
    int error=0;
    r->_dnssd=dnssd_init(name,(int)strlen(name),(const char *)hw,6,1,&error);
    if(!r->_dnssd || error) { SSWirelessStop(ptr); return -2; }
    dnssd_set_peer_to_peer(r->_dnssd,1);
    dnssd_set_airplay_features(r->_dnssd,0,0); dnssd_set_airplay_features(r->_dnssd,4,0);
    dnssd_set_airplay_features(r->_dnssd,42,1);
    raop_callbacks_t cb={0}; cb.cls=ptr;
    cb.video_process=videoPacket; cb.audio_process=audioPacket;
    cb.video_pause=nothing; cb.video_resume=nothing; cb.conn_init=nothing; cb.conn_destroy=nothing;
    cb.conn_feedback=nothing; cb.conn_reset=resetConnection;
    cb.audio_flush=nothing; cb.video_flush=nothing;
    cb.audio_set_client_volume=initialVolume; cb.audio_set_volume=volume;
    cb.audio_set_metadata=metadata; cb.audio_set_coverart=metadata; cb.audio_stop_coverart_rendering=nothing;
    cb.audio_set_progress=progress; cb.audio_get_format=audioFormat; cb.video_report_size=reportSize;
    cb.display_pin=pin; cb.register_client=registerClient; cb.check_register=checkClient;
    cb.report_client_request=admitClient; cb.passwd=password; cb.export_dacp=dacp;
    cb.video_set_codec=codec; cb.video_reset=videoReset; cb.mirror_video_running=mirrorRunning;
    cb.on_video_play=playUnsupported; cb.on_video_scrub=seekUnsupported; cb.on_video_rate=seekUnsupported;
    cb.on_video_stop=nothing; cb.on_video_acquire_playback_info=playbackInfo;
    cb.on_video_playlist_remove=playlistRemove; cb.get_custom_profile=customProfile;
    r->_raop=raop_init(&cb);
    if(!r->_raop) { SSWirelessStop(ptr); return -3; }
    raop_set_log_callback(r->_raop,protocolLog,ptr);
    raop_set_log_level(r->_raop,LOGGER_INFO);
    if(raop_init2(r->_raop,1,deviceID,keyPath)) { free(r->_raop); r->_raop=NULL; SSWirelessStop(ptr); return -4; }
    raop_set_plist(r->_raop,"width",1920); raop_set_plist(r->_raop,"height",1080);
    raop_set_plist(r->_raop,"maxFPS",60); raop_set_plist(r->_raop,"refreshRate",60); raop_set_plist(r->_raop,"pin",10000+(int)arc4random_uniform(9000)+1000);
    raop_set_dnssd(r->_raop,r->_dnssd);
    unsigned short port=0;
    if(raop_start_httpd(r->_raop,&port)<0) { SSWirelessStop(ptr); return -5; }
    raop_set_port(r->_raop,port); r->_port=port;
    if(dnssd_register_raop(r->_dnssd,port) || dnssd_register_airplay(r->_dnssd,port)) { SSWirelessStop(ptr); return -6; }
    atomic_store(&r->_dnsStop,false);
    if(pthread_create(&r->_dnsThread,NULL,serveDNS,ptr)) { SSWirelessStop(ptr); return -7; }
    r->_hasThread=YES;
    return 0;
}
void SSWirelessStop(void *ptr) {
    SSReceiver *r=receiver(ptr);
    atomic_store(&r->_dnsStop,true);
    if(r->_hasThread) { pthread_join(r->_dnsThread,NULL); r->_hasThread=NO; }
    if(r->_dnssd) { dnssd_unregister_raop(r->_dnssd); dnssd_unregister_airplay(r->_dnssd); }
    if(r->_raop) { raop_destroy(r->_raop); r->_raop=NULL; }
    if(r->_dnssd) { dnssd_destroy(r->_dnssd); r->_dnssd=NULL; }
    if(r->_diagnostics) { fclose(r->_diagnostics); r->_diagnostics=NULL; }
    @synchronized(r) { [r clearDecoder]; if(r->_audioDecoder) { AudioConverterDispose(r->_audioDecoder); r->_audioDecoder=NULL; } r->_streamActive=NO; r->_port=0; }
}
void SSWirelessDestroy(void *ptr) { if(!ptr) return; SSWirelessStop(ptr); CFBridgingRelease(ptr); }
unsigned short SSWirelessPort(void *ptr) { return receiver(ptr)->_port; }
void SSWirelessFeedVideo(void *ptr,const unsigned char *data,int length,bool hevc) { [receiver(ptr) video:data length:length hevc:hevc time:0]; }
void SSWirelessFeedAudio(void *ptr,const unsigned char *data,int length,unsigned char codec) {
    audio_decode_struct packet={0}; packet.data=(unsigned char *)data; packet.data_len=length; packet.ct=codec;
    [receiver(ptr) audio:&packet];
}
void SSWirelessFeedEnd(void *ptr) { mirrorRunning(ptr,false); }
