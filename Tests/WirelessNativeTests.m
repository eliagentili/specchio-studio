#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "../Native/WirelessBridge.h"
typedef struct { int video; int audio; int width; int height; double energy; int ends; } Counts;
static void sample(void *ctx,CMSampleBufferRef buffer,bool video) {
    Counts *c=ctx;
    if(video) {
        CVImageBufferRef image=CMSampleBufferGetImageBuffer(buffer);
        NSCAssert(image!=NULL,@"Decoder returned no image");
        c->video++; c->width=(int)CVPixelBufferGetWidth(image); c->height=(int)CVPixelBufferGetHeight(image);
    } else {
        c->audio+=(int)CMSampleBufferGetNumSamples(buffer);
        CMBlockBufferRef block=CMSampleBufferGetDataBuffer(buffer);
        size_t length=CMBlockBufferGetDataLength(block);
        int16_t *data=malloc(length); CMBlockBufferCopyDataBytes(block,0,length,data);
        for(size_t i=0;i<length/2;i++) c->energy+=abs(data[i]);
        free(data);
    }
}
static void event(void *ctx,int code,const char *message) { if(code==3) ((Counts *)ctx)->ends++; }
typedef struct { int16_t data[8192]; UInt32 cursor; } Tone;
static OSStatus pcmInput(AudioConverterRef converter,UInt32 *count,AudioBufferList *buffers,AudioStreamPacketDescription **desc,void *ctx) {
    Tone *tone=ctx;
    UInt32 available=4096-tone->cursor;
    *count=MIN(*count,available);
    buffers->mNumberBuffers=1;
    buffers->mBuffers[0]=(AudioBuffer){2,*count*4,tone->data+tone->cursor*2};
    tone->cursor+=*count;
    return *count ? noErr : -1;
}
int main(int argc,char **argv) { @autoreleasepool {
    NSCAssert(argc==3,@"Expected H264 and HEVC fixtures");
    Counts counts={0};
    void *receiver=SSWirelessCreate(&counts,sample,event);
    for(int i=1;i<=3;i++) {
        BOOL hevc=i==2;
        NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[hevc ? 2 : 1]]];
        NSCAssert(data.length>0,@"Fixture missing");
        int before=counts.video;
        SSWirelessFeedVideo(receiver,data.bytes,(int)data.length,hevc);
        NSCAssert(counts.video==before+1,@"Native video decode failed after a codec change");
        printf("PASS: wireless %s decoder produced %dx%d pixels\n",hevc ? "HEVC" : "H264",counts.width,counts.height);
    }
    SSWirelessFeedEnd(receiver); SSWirelessFeedEnd(receiver);
    NSCAssert(counts.ends==1,@"Stream end must be delivered once, including peer EOF");
    NSData *again=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    SSWirelessFeedVideo(receiver,again.bytes,(int)again.length,false);
    NSCAssert(counts.video==4,@"Video decoder failed to reconnect after EOF");
    SSWirelessFeedEnd(receiver);
    NSCAssert(counts.ends==2,@"Second stream end was lost");
    SSWirelessStop(receiver);
    const uint8_t malformed[]={0,0,0,1,0x67};
    SSWirelessFeedVideo(receiver,malformed,sizeof(malformed),false);
    NSCAssert(counts.video==4,@"Malformed input produced a frame");
    SSWirelessFeedAudio(receiver,NULL,4,1);
    SSWirelessFeedAudio(receiver,malformed,0,1);
    SSWirelessFeedAudio(receiver,malformed,sizeof(malformed),255);
    NSCAssert(counts.audio==0,@"Malformed audio produced samples");
    AudioStreamBasicDescription pcm={44100,kAudioFormatLinearPCM,kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked,4,1,4,2,16,0};
    AudioStreamBasicDescription eld={0}; eld.mSampleRate=44100; eld.mChannelsPerFrame=2;
    eld.mFormatID=kAudioFormatMPEG4AAC_ELD; eld.mFramesPerPacket=480;
    AudioConverterRef encoder=NULL;
    OSStatus err=AudioConverterNew(&pcm,&eld,&encoder);
    NSCAssert(!err && encoder,@"AAC-ELD encoder unavailable");
    Tone tone={0}; for(int i=0;i<4096;i++) tone.data[i*2]=tone.data[i*2+1]=(int16_t)(14000*sin(2*M_PI*440*i/44100.0));
    int packets=0;
    for(int i=0;i<6;i++) {
        uint8_t encoded[4096]; UInt32 n=1;
        AudioBufferList list={1,{{2,sizeof(encoded),encoded}}}; AudioStreamPacketDescription desc={0};
        err=AudioConverterFillComplexBuffer(encoder,pcmInput,&tone,&n,&list,&desc);
        if(n && list.mBuffers[0].mDataByteSize>0) {
            SSWirelessFeedAudio(receiver,encoded,(int)list.mBuffers[0].mDataByteSize,8); packets++;
        }
    }
    AudioConverterDispose(encoder);
    NSCAssert(packets>0 && counts.audio>0 && counts.energy>0,@"AAC-ELD wireless audio was silent or undecodable");
    printf("PASS: wireless AAC-ELD audio decoder produced %d non-silent PCM frames\n",counts.audio);
    SSWirelessDestroy(receiver);
    printf("PASS: wireless peer EOF, decoder reconnect, stop/reset and malformed input\n");
    return 0;
} }
