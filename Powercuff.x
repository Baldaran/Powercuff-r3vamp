#import <notify.h>
#import <Foundation/Foundation.h>

#ifndef ROOT_PATH_NS
#define ROOT_PATH_NS(path) \
    ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? \
    [@"/var/jb" stringByAppendingPathComponent:path] : path)
#endif

// Hooking every possible thermal management class found in iOS 16
@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

@interface GPProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

@interface CLPProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

@interface Context : NSObject
- (void)setThermalSimulationMode:(int)mode;
@end

static id currentTarget;
static int token;

static NSString *stringForMode(uint64_t mode) {
    switch (mode) {
        case 1: return @"nominal";
        case 2: return @"light";
        case 3: return @"moderate";
        case 4: return @"heavy";
        default: return @"off";
    }
}

static void ApplyThermals(void) {
    uint64_t mode = 0;
    notify_get_state(token, &mode);
    
    if (currentTarget) {
        NSString *modeString = stringForMode(mode);
        // Try all known methods for iOS 16
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            [currentTarget putDeviceInThermalSimulationMode:modeString];
        } 
        if ([currentTarget respondsToSelector:@selector(setThermalSimulationMode:)]) {
            [currentTarget setThermalSimulationMode:(int)mode];
        }
    }
}

%group thermalmonitord
%hook CommonProduct
- (id)initProduct:(id)arg1 {
    self = %orig;
    if (self) { currentTarget = self; ApplyThermals(); }
    return self;
}
%end

%hook GPProduct
- (id)initProduct:(id)arg1 {
    self = %orig;
    if (self) { currentTarget = self; ApplyThermals(); }
    return self;
}
%end

%hook CLPProduct
- (id)initProduct:(id)arg1 {
    self = %orig;
    if (self) { currentTarget = self; ApplyThermals(); }
    return self;
}
%end

%hook Context
- (id)init {
    self = %orig;
    if (self) { currentTarget = self; ApplyThermals(); }
    return self;
}
%end
%end

static void LoadSettings(void) {
    NSString *path = ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist");
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    
    uint64_t mode = [prefs[@"PowerMode"] ?: @0 unsignedLongLongValue];
    
    // Disable if LPM is required but not active
    if ([prefs[@"RequireLowPowerMode"] boolValue]) {
        if (![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
            mode = 0;
        }
    }
    
    notify_set_state(token, mode);
    notify_post("com.rpetrich.powercuff.thermals");
}

%group SpringBoard
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;
    LoadSettings();
}
- (void)_batterySaverModeChanged:(int)arg1 {
    %orig;
    LoadSettings();
}
%end
%end

%ctor {
    notify_register_check("com.rpetrich.powercuff.thermals", &token);
    NSString *proc = [[NSProcessInfo processInfo] processName];
    
    if ([proc isEqualToString:@"thermalmonitord"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)ApplyThermals, CFSTR("com.rpetrich.powercuff.thermals"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        %init(thermalmonitord);
    } else if ([proc isEqualToString:@"SpringBoard"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)LoadSettings, CFSTR("com.rpetrich.powercuff.settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        %init(SpringBoard);
        LoadSettings();
    }
}
