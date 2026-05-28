#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>

// Compile-time selector checks.

#define PROPERTY(propName) NSStringFromSelector(@selector(propName))

// A better assert. NSAssert is too runtime dependant, and assert() doesn't log.
// http://www.mikeash.com/pyblog/friday-qa-2013-05-03-proper-use-of-asserts.html
// Accepts both:
// - PSPDFAssert(x > 0);
// - PSPDFAssert(y > 3, @"Bad value for y");
#define PSPDFAssert(expression, ...) \
do { if(!(expression)) { \
    NSLog(@"%@", [NSString stringWithFormat: @"Assertion failure: %s in %s on line %s:%d. %@", #expression, __PRETTY_FUNCTION__, __FILE__, __LINE__, [NSString stringWithFormat:@"" __VA_ARGS__]]); \
abort(); }} while(0)

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Helper for Swizzling

BOOL PSPDFReplaceMethodWithBlock(Class c, SEL origSEL, SEL newSEL, id block) {
    PSPDFAssert(c && origSEL && newSEL && block);
    Method origMethod = class_getInstanceMethod(c, origSEL);
    const char *encoding = method_getTypeEncoding(origMethod);
    
    // Add the new method.
    IMP impl = imp_implementationWithBlock(block);
    if (!class_addMethod(c, newSEL, impl, encoding)) {
        NSLog(@"Failed to add method: %@ on %@", NSStringFromSelector(newSEL), c);
        return NO;
    }else {
        // Ensure the new selector has the same parameters as the existing selector.
        Method newMethod = class_getInstanceMethod(c, newSEL);
        PSPDFAssert(strcmp(method_getTypeEncoding(origMethod), method_getTypeEncoding(newMethod)) == 0, @"Encoding must be the same.");
        
        // If original doesn't implement the method we want to swizzle, create it.
        if (class_addMethod(c, origSEL, method_getImplementation(newMethod), encoding)) {
            class_replaceMethod(c, newSEL, method_getImplementation(origMethod), encoding);
        }else {
            method_exchangeImplementations(origMethod, newMethod);
        }
    }
    return YES;
}

// This installs a small guard that checks for the most common threading-errors in UIKit.
// This won't really slow down performance but still only is compiled in DEBUG versions of PSPDFKit.
// @note No private API is used here.
__attribute__((constructor)) static void PSPDFUIKitMainThreadGuard(void) {
    setenv("CA_DEBUG_TRANSACTIONS", "1", 1); // Enable Core Animation debug transactions.
    @autoreleasepool {
        for (NSString *selStr in @[PROPERTY(setNeedsLayout), PROPERTY(setNeedsDisplay), PROPERTY(setNeedsDisplayInRect:)]) {
            SEL selector = NSSelectorFromString(selStr);
            SEL newSelector = NSSelectorFromString([NSString stringWithFormat:@"pspdf_%@", selStr]);
            if ([selStr hasSuffix:@":"]) {
                PSPDFReplaceMethodWithBlock(UIView.class, selector, newSelector, ^(__unsafe_unretained UIView *_self, CGRect r) {
                    if(!NSThread.isMainThread){
                        dispatch_async(dispatch_get_main_queue(), ^{
                            ((void ( *)(id, SEL, CGRect))objc_msgSend)(_self, newSelector, r);
                        });
                    }else{
                        ((void ( *)(id, SEL, CGRect))objc_msgSend)(_self, newSelector, r);
                    }
                });
            }else {
                PSPDFReplaceMethodWithBlock(UIView.class, selector, newSelector, ^(__unsafe_unretained UIView *_self) {
                    if(!NSThread.isMainThread){
                        dispatch_async(dispatch_get_main_queue(), ^{
                            ((void ( *)(id, SEL))objc_msgSend)(_self, newSelector);
                        });
                    }else
                        ((void ( *)(id, SEL))objc_msgSend)(_self, newSelector);
                });
            }
        }
    }
}