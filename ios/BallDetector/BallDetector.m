#import <VisionCamera/FrameProcessorPlugin.h>
#import <VisionCamera/FrameProcessorPluginRegistry.h>

#if __has_include("hoopmetric/hoopmetric-Swift.h")
#import "hoopmetric/hoopmetric-Swift.h"
#else
#import "hoopmetric-Swift.h"
#endif

VISION_EXPORT_SWIFT_FRAME_PROCESSOR(BallDetectorPlugin, detectBall)