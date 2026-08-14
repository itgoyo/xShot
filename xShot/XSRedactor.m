#import "XSRedactor.h"
#import <Vision/Vision.h>

@implementation XSRedactor

+ (NSImage *)redactEmailsInImage:(NSImage *)image foundCount:(NSInteger *)count {
    if (count) *count = 0;
    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cg = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!cg) return image;

    __block NSInteger found = 0;
    __block NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
        for (VNRecognizedTextObservation *obs in request.results) {
            VNRecognizedText *top = [obs topCandidates:1].firstObject;
            if (!top.string.length) continue;
            if ([re numberOfMatchesInString:top.string options:0 range:NSMakeRange(0, top.string.length)] > 0) {
                found += 1;
                [rects addObject:[NSValue valueWithRect:obs.boundingBox]];
            }
        }
        dispatch_semaphore_signal(sema);
    }];
    req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    [handler performRequests:@[req] error:nil];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)5 * NSEC_PER_SEC));
    if (count) *count = found;
    if (found == 0) return image;

    NSSize size = image.size;
    NSImage *out = [[NSImage alloc] initWithSize:size];
    [out lockFocus];
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
    [[NSColor colorWithWhite:0.12 alpha:1] setFill];
    for (NSValue *v in rects) {
        NSRect bb = v.rectValue;
        NSRect r = NSMakeRect(bb.origin.x * size.width,
                              bb.origin.y * size.height,
                              bb.size.width * size.width,
                              bb.size.height * size.height);
        r = NSInsetRect(r, -3, -2);
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:3 yRadius:3] fill];
    }
    [out unlockFocus];
    return out;
}

@end
