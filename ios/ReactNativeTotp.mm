#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ReactNativeTotp, NSObject)

RCT_EXTERN_METHOD(initFynoConfig:(NSString *)wsid
                  distinctId:(NSString *)distinctId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(registerTenant:(NSString *)tenantId
                  tenantLabel:(NSString *)tenantLabel
                  totpToken:(NSString *)totpToken
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(setConfig:(NSString *)tenantId
                  config:(NSDictionary *)config
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getTotp:(NSString *)tenantId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(deleteTenant:(NSString *)tenantId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(fetchActiveTenants:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end
