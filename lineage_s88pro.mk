#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, device/doogee/s88pro/device.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Fa uscire la ROM installabile senza costruire il recovery: il BoardConfig ha
# TARGET_NO_RECOVERY := true (si usa la TWRP di lopestom, e costruirlo fallisce
# comunque su mkbootimg), ma il build lega le due cose e senza questa riga
# INTERNAL_OTA_PACKAGE_TARGET resta vuota -- il target "bacon" finisce per
# eseguire "ln -f" su uno zip che nessuno ha costruito.
#
# Sta QUI e non in device.mk: da li' non veniva raccolta.
PRODUCT_BUILD_GENERIC_OTA_PACKAGE := true

PRODUCT_DEVICE := s88pro
PRODUCT_NAME := lineage_s88pro
PRODUCT_BRAND := DOOGEE
PRODUCT_MODEL := S88Pro
PRODUCT_MANUFACTURER := doogee

PRODUCT_GMS_CLIENTID_BASE := android-doogee

# Fingerprint stock verificato in Fase 1. Alcune app e il RIL lo leggono.
PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="S88Pro_EEA-user 10 QP1A.190711.020 1592876742 release-keys"

BUILD_FINGERPRINT := DOOGEE/S88Pro_EEA/S88Pro:10/QP1A.190711.020/1592876742:user/release-keys
