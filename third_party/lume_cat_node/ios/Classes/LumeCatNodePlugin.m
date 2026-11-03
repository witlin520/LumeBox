#import "LumeCatNodePlugin.h"
#import <NodeMobile/NodeMobile.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>

@interface LumeCatNodePlugin ()
@property(atomic) BOOL started;
@property(atomic) BOOL exited;
@end

@implementation LumeCatNodePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  static LumeCatNodePlugin *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [LumeCatNodePlugin new]; });
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"lumebox/cat_node" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:instance channel:channel];
}
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSDictionary *args = [call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{};
  if ([call.method isEqualToString:@"isSupported"]) { result(@YES); return; }
  if ([call.method isEqualToString:@"openExternal"]) {
    NSURL *url = [NSURL URLWithString:args[@"url"] ?: @""];
    if (!url) { result(@NO); return; }
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) { result(@(success)); }];
    return;
  }
  if ([call.method isEqualToString:@"start"]) {
    if (self.exited) { result([FlutterError errorWithCode:@"nodeExited" message:@"Node 已退出，请重新打开 App" details:nil]); return; }
    if (self.started) { result(@NO); return; }
    NSString *bootstrap = args[@"bootstrap"], *spec = args[@"spec"], *cache = args[@"cache"];
    if (!bootstrap || !spec || !cache) { result([FlutterError errorWithCode:@"arguments" message:@"Node 启动参数不完整" details:nil]); return; }
    self.started = YES;
    setenv("NODE_COMPILE_CACHE", cache.UTF8String, 1);
    setenv("NODE_COMPILE_CACHE_PORTABLE", "1", 1);
    NSUInteger memory = NSProcessInfo.processInfo.physicalMemory / 1024 / 1024;
    NSString *options = [NSString stringWithFormat:@"--max-old-space-size=%lu", (unsigned long)MAX(256, MIN(512, memory / 8))];
    setenv("NODE_OPTIONS", options.UTF8String, 1);
    setenv("CATVOD_DISABLE_AUTOSTART", "1", 1);
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
      char *argv[] = {strdup("node"), strdup(bootstrap.UTF8String), strdup(spec.UTF8String), NULL};
      node_start(3, argv);
      for (int i = 0; i < 3; i++) free(argv[i]);
      self.exited = YES;
    }];
    thread.name = @"LumeBox.CatNode";
    thread.stackSize = 8 * 1024 * 1024;
    thread.qualityOfService = NSQualityOfServiceUtility;
    [thread start];
    result(@YES); return;
  }
  if ([call.method isEqualToString:@"readSecret"] || [call.method isEqualToString:@"writeSecret"]) {
    NSString *key = [args[@"key"] isKindOfClass:NSString.class] ? args[@"key"] : nil;
    if (!key) { result([FlutterError errorWithCode:@"arguments" message:@"凭证名称不完整" details:nil]); return; }
    NSMutableDictionary *query = [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService:@"com.lumebox.cat", (__bridge id)kSecAttrAccount:key} mutableCopy];
    if ([call.method isEqualToString:@"readSecret"]) {
      query[(__bridge id)kSecReturnData] = @YES;
      CFTypeRef data = NULL;
      OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
      if (status == errSecSuccess) { result([[NSString alloc] initWithData:CFBridgingRelease(data) encoding:NSUTF8StringEncoding]); }
      else if (status == errSecItemNotFound) { result(nil); }
      else { result([FlutterError errorWithCode:@"keychain" message:@"无法读取订阅凭证" details:nil]); }
    } else {
      // Flutter's codec represents null dictionary values as NSNull.
      NSString *value = [args[@"value"] isKindOfClass:NSString.class] ? args[@"value"] : nil;
      if (!value) { SecItemDelete((__bridge CFDictionaryRef)query); result(nil); return; }
      NSDictionary *update = @{(__bridge id)kSecValueData:[value dataUsingEncoding:NSUTF8StringEncoding]};
      OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
      if (status == errSecItemNotFound) {
        [query addEntriesFromDictionary:update];
        query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
      }
      result(status == errSecSuccess ? nil : [FlutterError errorWithCode:@"keychain" message:@"无法保存订阅凭证" details:nil]);
    }
    return;
  }
  result(FlutterMethodNotImplemented);
}
@end
