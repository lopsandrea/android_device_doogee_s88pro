#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := $(call my-dir)

# ImsService di MediaTek, per VoLTE.
#
# L'APK non sta in albero: e' derivato da quello della ROM di fabbrica e va
# preparato una volta con ./prepare-imsservice.sh (vedi il commento la' dentro).
# Il modulo esiste solo se il file c'e', cosi' chi non l'ha preparato compila
# lo stesso, semplicemente senza VoLTE.
ifneq ($(wildcard $(LOCAL_PATH)/ImsService.apk),)

include $(CLEAR_VARS)

LOCAL_MODULE := ImsService
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := ImsService.apk

# Obbligatoria: l'APK dichiara sharedUserId="android.uid.phone" e per condividere
# lo UID con com.android.phone deve portare la nostra firma di piattaforma, non
# quella di Doogee.
LOCAL_CERTIFICATE := platform

# Deve stare in priv-app: da /data il namespace del classloader non lascia
# caricare le librerie native di /system/lib64, che a questo APK servono.
# I permessi privilegiati sono in privapp-permissions-mtk-ims.xml.
LOCAL_PRIVILEGED_MODULE := true

# Il dex e' quello ricompilato da smali: lasciarlo com'e'.
LOCAL_DEX_PREOPT := false
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)

# Il manifest dichiara cinque <uses-library>, e il build system pretende di
# ritrovarle fra i moduli:
#
#   error: mismatch in the <uses-library> tags between the build system and the manifest
#
# Qui pero' non sono moduli: sono jar della ROM di fabbrica, dichiarati come
# librerie condivise in mediatek-ims-libs.xml e risolti a runtime dal
# PackageManager. Il controllo serve al dexpreopt, che per questo modulo e'
# disattivato, quindi si spegne.
LOCAL_ENFORCE_USES_LIBRARIES := false

include $(BUILD_PREBUILT)

endif
