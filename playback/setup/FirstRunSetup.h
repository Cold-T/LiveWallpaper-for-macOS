#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
BOOL LWSetupRuntimeReady(void);
void LWSetupPrepareComponents(void (^progress)(NSString *, double), void (^completion)(NSString *));
void LWSetupImportEngine(NSString *source, NSArray<NSDictionary *> *screens,
                        void (^progress)(NSString *, double), void (^completion)(NSString *, NSString *));
#ifdef __cplusplus
}
#endif
