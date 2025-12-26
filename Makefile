# Define the target and SDK
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard

# Set the architectures for modern devices
ARCHS = arm64 arm64e

# This is the key for Rootless compatibility
THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = Powercuff
Powercuff_FILES = Powercuff.x
Powercuff_FRAMEWORKS = Foundation
Powercuff_CFLAGS = -fobjc-arc -std=c99

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
