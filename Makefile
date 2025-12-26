TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = Powercuff
# We include QuartzCore for the 30FPS limiter and UIKit for process identification
Powercuff_FILES = Powercuff.x
Powercuff_FRAMEWORKS = Foundation QuartzCore UIKit
Powercuff_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
