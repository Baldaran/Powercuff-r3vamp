#import <notify.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifndef ROOT_PATH_NS
#define ROOT_PATH_NS(path) \
    ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? \
    [@"/var/jb" stringByAppendingPathComponent:path] : path)
#endif

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)simulationMode;
@end

@interface Context : NSObject
- (void)setThermalSimulationMode:(int)mode;
@end

extern char ***_NSGetArgv(void);

static id currentTarget; 
static int token;

static NSString *stringForThermalMode(uint64_t thermalMode) {
    switch (thermalMode) {
        case 1: return @"nominal";
        case 2: return @"light";
        case 3: return @"moderate";
        case 4: return @"heavy";
        default: return @"off";
    }
}

static void ApplyThermals(void) {
    uint64_t thermalMode = 0;
    notify_get_state(token, &thermalMode);
    
    NSLog(@"[Powercuff-Debug] Applying Thermal Mode: %llu (%@)", thermalMode, stringForThermalMode(thermalMode));

    if (currentTarget) {
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            NSLog(@"[Powercuff-Debug] Using CommonProduct method");
            [currentTarget putDeviceInThermalSimulationMode:stringForThermalMode(thermalMode)];
        } else if ([currentTarget respondsToSelector:@selector(setThermalSimulationMode:)]) {
            NSLog(@"[Powercuff-Debug] Using Context method");
            [currentTarget setThermalSimulationMode:(int)thermalMode];
        }
    } else {
        NSLog(@"[Powercuff-Debug] Error: currentTarget is NULL");
    }
}

%group thermalmonitord
%hook CommonProduct
- (id)initProduct:(id)data {
    self = %orig;
    if (self) {
        currentTarget = self;
        NSLog(@"[Powercuff-Debug] CommonProduct initialized");
        ApplyThermals();
    }
    return self;
}
%end

%hook Context
- (id)init {
    self = %orig;
    if (self) {
        currentTarget = self;
        NSLog(@"[Powercuff-Debug] Context initialized");
        ApplyThermals();
    }
    return self;
}
%end
%end

static void LoadSettings(void) {
    NSString *basePath = @"/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist";
    NSString *finalPath = ROOT_PATH_NS(basePath);
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:finalPath];
    NSLog(@"[Powercuff-Debug] Loading settings from: %@", finalPath);
    
    uint64_t thermalMode = 0;
    if (prefs[@"PowerMode"]) {
        thermalMode = [prefs[@"PowerMode"] unsignedLongLongValue];
    }
    
    if ([prefs[@"RequireLowPowerMode"] boolValue]) {
        if (![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
            NSLog(@"[Powercuff-Debug] Low Power Mode required but NOT enabled. Setting mode to 0.");
            thermalMode = 0;
        }
    }

    NSLog(@"[Powercuff-Debug] Final Thermal Mode: %llu", thermalMode);
    notify_set_state(token, thermalMode);
    notify_post("com.rpetrich.powercuff.thermals");
}

%group SpringBoard
%hook SpringBoard
- (void)_batterySaverModeChanged:(int)arg1 {
    %orig;
    NSLog(@"[Powercuff-Debug] Battery Saver Mode Changed");
    LoadSettings();
}
%end
%end

%ctor {
    notify_register_check("com.rpetrich.powercuff.thermals", &token);
    
    char *argv0 = **_NSGetArgv();
    if (argv0) {
        NSString *processName = [[NSString stringWithUTF8String:argv0] lastPathComponent];
        NSLog(@"[Powercuff-Debug] Loaded into process: %@", processName);

        if ([processName isEqualToString:@"thermalmonitord"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)ApplyThermals, CFSTR("com.rpetrich.powercuff.thermals"), NULL, CFNotificationSuspensionBehaviorCoalesce);
            %init(thermalmonitord);
        } else if ([processName isEqualToString:@"SpringBoard"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)LoadSettings, CFSTR("com.rpetrich.powercuff.settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
            LoadSettings();
            %init(SpringBoard);
        }
    }
}
