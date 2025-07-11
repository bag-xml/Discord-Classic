THEOS_DEVICE_IP = 192.168.0.105

ARCHS = armv7 armv7s
TARGET := iphone:clang:7.1:5.0
PREFIX = /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/
SYSROOT = $(THEOS)/sdks/iPhoneOS7.1.sdk
MODULES = jailed
PACKAGE_FORMAT = ipa

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Discord

INCLUDE_FLAGS = $(shell find . -type d -not -path "*/.*" -exec gprintf '-iquote %s ' {} \;) 
Discord_FILES = $(shell find . -name "*.m")
Discord_FRAMEWORKS = AssetsLibrary QuickLook ImageIO MediaPlayer AVFoundation Security CFNetwork UIKit Foundation CoreGraphics QuartzCore
Discord_BUNDLE_RESOURCES = Theos/
Discord_CFLAGS = -ObjC -fobjc-arc -Wno-unused-const-variable -Wno-gnu-folding-constant -Wno-error=\#warnings -include Discord_Classic/Discord_Classic-Prefix.pch $(INCLUDE_FLAGS)
# -fobjc-weak -Wno-objc-property-no-attribute 

after-Discord-all::
	$(ECHO_BEGIN)codesign --force --deep --sign - $(THEOS_OBJ_DIR)/Discord.app$(ECHO_END)

after-package::
	$(ECHO_BEGIN)OPENSSL_CONF=$(HOME)/openssl-weak.conf ideviceinstaller install "$(THEOS_PACKAGE_DIR)/$(shell ls -rt $(THEOS_PACKAGE_DIR) | tail -n 1)"$(ECHO_END)

include $(THEOS_MAKE_PATH)/application.mk
