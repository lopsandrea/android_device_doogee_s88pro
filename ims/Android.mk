#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := $(call my-dir)

# MediaTek's ImsService, for VoLTE.
#
# The APK is not in tree: it is derived from the stock ROM's and has to be
# prepared once with ./prepare-imsservice.sh (see the comment in there). The
# module exists only if the file is there, so whoever has not prepared it still
# builds, simply without VoLTE.
ifneq ($(wildcard $(LOCAL_PATH)/ImsService.apk),)

include $(CLEAR_VARS)

LOCAL_MODULE := ImsService
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := ImsService.apk

# Mandatory: the APK declares sharedUserId="android.uid.phone" and to share the
# UID with com.android.phone it has to carry our platform signature, not
# Doogee's.
LOCAL_CERTIFICATE := platform

# It has to live in priv-app: from /data the classloader namespace does not
# allow loading the native libraries in /system/lib64, which this APK needs.
# The privileged permissions are in privapp-permissions-mtk-ims.xml.
LOCAL_PRIVILEGED_MODULE := true

# The dex is the one recompiled by smali: leave it as it is.
LOCAL_DEX_PREOPT := false
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)

# The manifest declares five <uses-library> entries, and the build system
# insists on finding them among the modules:
#
#   error: mismatch in the <uses-library> tags between the build system and the manifest
#
# Here, though, they are not modules: they are stock ROM jars, declared as
# shared libraries in mediatek-ims-libs.xml and resolved at runtime by
# PackageManager. The check is there for dexpreopt, which is disabled for this
# module, so it is turned off.
LOCAL_ENFORCE_USES_LIBRARIES := false

include $(BUILD_PREBUILT)

endif
