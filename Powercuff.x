#import <notify.h>
#import <Foundation/Foundation.h>

#ifndef ROOT_PATH_NS
#define ROOT_PATH_NS(path) \
    ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? \
    [@"/var/jb" stringByAppendingPathComponent:path] : path)
#endif

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static id currentTarget;
static int token;

static void ApplyThermals(void) {
    uint64_t mode = 0;
    notify_get_state(token, &mode);
    
    // Index mapping: 0:None, 1:Nominal, 2:Light, 3:Moderate, 4:Heavy
    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    
    if (currentTarget) {
        if (mode == 0) {
            // GENIUS RESET: Explicitly tell iOS to stop simulating heat
            if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
                [currentTarget putDeviceInThermalSimulationMode:nil]; 
                [currentTarget putDeviceInThermalSimulationMode:@"off"];
            }
        } else if (mode < modes.count) {
            NSString *modeStr = modes[mode];
            if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
                [currentTarget putDeviceInThermalSimulationMode:modeStr];
            }
        }
    }
}

%group thermalmonitord
%hook CommonProduct
- (id)initProduct:(id)arg1 {
    self = %orig;
    if (self) {
        currentTarget = self;
        ApplyThermals();
    }
    return self;
}
%end

// Fallback for newer iOS 16 thermal structures
%hook GPProduct
- (id)initProduct:(id)arg1 {
    self = %orig;
    if (self) {
        currentTarget = self;
        ApplyThermals();
    }
    return self;
}
%end
%end

static void LoadSettings(void) {
    NSString *path = ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist");
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    
    uint64_t mode = [prefs[@"PowerMode"] ?: @0 unsignedLongLongValue];
    
    // Check Low Power Mode requirement
    if ([prefs[@"RequireLowPowerMode"] boolValue]) {
        if (![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
            mode = 0; // Force 'None' if LPM isn't active
        }
    }
    
    notify_set_state(token, mode);
    notify_post("com.rpetrich.powercuff.thermals");
}

%ctor {
    notify_register_check("com.rpetrich.powercuff.thermals", &token);
    NSString *procName = [[NSProcessInfo processInfo] processName];
    
    if ([procName isEqualToString:@"thermalmonitord"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)ApplyThermals, CFSTR("com.rpetrich.powercuff.thermals"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        %init(thermalmonitord);
    } else {
        // Observer for SpringBoard and Apps to watch for setting changes
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)LoadSettings, CFSTR("com.rpetrich.powercuff.settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        
        if ([procName isEqualToString:@"SpringBoard"]) {
            LoadSettings();
        }
    }
}
