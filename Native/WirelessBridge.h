#ifndef SPECCHIO_WIRELESS_BRIDGE_H
#define SPECCHIO_WIRELESS_BRIDGE_H
#include <CoreMedia/CoreMedia.h>
#include <stdbool.h>
typedef void (*SSWirelessSample)(void *context, CMSampleBufferRef sample, bool video);
typedef void (*SSWirelessEvent)(void *context, int event, const char *message);
void *SSWirelessCreate(void *context, SSWirelessSample sample, SSWirelessEvent event);
int SSWirelessStart(void *receiver, const char *name, const char *deviceID, const char *keyPath);
void SSWirelessStop(void *receiver);
void SSWirelessDestroy(void *receiver);
unsigned short SSWirelessPort(void *receiver);
// Feed a local Annex-B fixture into the same decoder used for network video.
void SSWirelessFeedVideo(void *receiver, const unsigned char *data, int length, bool hevc);
void SSWirelessFeedAudio(void *receiver, const unsigned char *data, int length, unsigned char codec);
void SSWirelessFeedEnd(void *receiver);
#endif
