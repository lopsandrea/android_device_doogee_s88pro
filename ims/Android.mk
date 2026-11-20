#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := $(call my-dir)

# MediaTek's ImsService, for VoLTE.
#
# The APK is not in tree: it is derived from TrebleDroid's ims-mtk-q.apk and
# has to be prepared once with ./prepare-imsservice.sh (see the comment in
# there). The module exists only if the file is there, so whoever has not
# prepared it still builds, simply without VoLTE.
ifneq ($(wildcard $(LOCAL_PATH)/ImsService.apk),)

include $(CLEAR_VARS)

LOCAL_MODULE := ImsService
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := ImsService.apk

# Mandatory: the APK declares sharedUserId="android.uid.phone" and to share the
# UID with com.android.phone it has to carry our platform signature.
LOCAL_CERTIFICATE := platform

# An ordinary system app, not priv-app: everything it needs comes from the
# phone UID it shares, which is how GSIs run it (installed in /data). The only
# native library it loads is MediaTek's video call wrapper, from /system/lib64:
# see proprietary-files.txt.

# The dex is the one recompiled by smali: leave it as it is.
LOCAL_DEX_PREOPT := false
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)

# The manifest lists five MediaTek <uses-library> entries, all of them
# required="false", and the build system insists on finding them among the
# modules:
#
#   error: mismatch in the <uses-library> tags between the build system and the manifest
#
# Nothing declares them on this device and the APK does without them, as on a
# GSI. The check is there for dexpreopt, which is disabled for this module, so
# it is turned off.
LOCAL_ENFORCE_USES_LIBRARIES := false

include $(BUILD_PREBUILT)

endif
