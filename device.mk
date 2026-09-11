#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/doogee/s88pro

# Dynamic partitions: a product variable, not a board one.
PRODUCT_USE_DYNAMIC_PARTITIONS := true


# The fstab goes in the ramdisk, under a suffix of its own.
#
# The ramdisk copy is needed because first stage init looks for it there: it
# runs before vendor is mounted, and without it stops immediately --
#
#     init: Failed to create FirstStageMount failed to read default fstab for
#           first stage mount
#     init: Failed to mount required partitions early
#
# and the phone falls back to recovery after a minute and a half. Measured on
# 8 September 2026, reading /sys/fs/pstore/console-ramoops after the attempt.
#
# This comment used to say the opposite -- "must NOT be copied into the
# ramdisk: boot is not rebuilt" -- and back then it was right: we used
# boot_nocrypt.img, flashed by hand in Phase 2, which already had the fstab in
# its ramdisk. Since boot.img comes out of the build, that premise no longer
# holds.
#
# BEWARE: the boot.img the build produces does NOT carry the Magisk patch that
# boot_nocrypt.img had (its ramdisk has .backup/ and overlay.d/, and init is
# 199 KB rather than 2.9 MB): anyone who wants root has to re-patch it.
#
# On encryption the note above said the opposite, and it needed fixing.
#
# It said not to reintroduce "fileencryption" because the TEE (TrustKernel
# keymaster 4.0) rejected keystore2 with Error::Km(ErrorCode(-64)), that is
# KEYMASTER_NOT_CONFIGURED. On this configuration that no longer happens, and
# it is not guesswork: with the system booted, keystore_cli_v2 generates a key
# in the TEE, uses it and verifies it --
#
#     keystore_cli_v2 generate --name=test --seclevel=tee   -> success
#     keystore_cli_v2 sign-verify --name=test               -> Sign: 256 bytes
#                                                              Verify: OK
#
# and get-chars lists OS_VERSION and OS_PATCHLEVEL among the "Hardware"
# parameters: the TEE does have its configuration data. Since Keymaster 4.0 it
# is no longer keystore that calls configure(); it is os_version and
# os_patch_level from the boot.img header, which the bootloader hands to the
# TEE, and our boot.img declares them (13.0.0 and 2026-02).
#
# The kernel is ready too: CONFIG_FS_ENCRYPTION=y, ext4 with the "encryption"
# feature, and userdata already has it enabled.
#
# So the /data line is once again identical to the stock one, this flag
# included. Going from unencrypted to encrypted requires wiping /data.
#
# The fstab is also read by vold, which starts long after first stage.
#
# As long as the build produced the vendor image, this file landed inside it as
# /vendor/etc/fstab.mt6771 and covered the stock one. With
# BOARD_PREBUILT_VENDORIMAGE it no longer does -- the build installs nothing
# into /vendor any more -- and at runtime the original takes over again, which
# is wrong in two places: it lists /product as a logical partition, and
# /product is no longer in super; and it sets fileencryption on /data, which
# the TEE cannot handle.
#
# First stage does not notice, because it reads ours from the ramdisk and
# tolerates the missing /product. vold does not: it iterates over every
# "logical" fstab entry and calls LOG(FATAL) on the one that is missing.
#
#     init:  DM_DEV_STATUS failed for product: No such device or address
#     vold:  could not find logical partition product: No such device or address
#     init:  Restarting system with command 'vold-failed'
#
# Read from /sys/fs/pstore after the attempt of 10 September 2026: the phone
# sat on the logo for two minutes and the watchdog powered it off.
#
# The way out is the suffix. fs_mgr builds the file name from
# ro.boot.fstab_suffix, and only falls back to ro.hardware when that is absent
# (system/core/fs_mgr/fs_mgr_fstab.cpp, GetFstabPath):
#
#     /odm/etc/fstab.<suffix>  ->  /vendor/etc/fstab.<suffix>  ->  /fstab.<suffix>
#
# With androidboot.fstab_suffix=s88pro in the cmdline, fstab.s88pro exists
# neither in /odm/etc nor in /vendor/etc: nothing covers it, and ours wins.
#
# But it has to be installed in two places, because the root changes between
# first stage and vold. Once system is mounted, first stage moves onto it
# (system/core/init/first_stage_mount.cpp:520, SwitchRoot("/system")) and the
# ramdisk disappears: an fstab living only there would be read by first stage
# and no longer by vold, which starts five seconds later. Hence the copy at the
# root of system, which after the switch is exactly "/".
#
# Root of system means TARGET_COPY_OUT_ROOT, not TARGET_COPY_OUT_SYSTEM: this
# is a system-as-root device, the image holds the whole tree with the "system"
# subdirectory inside itself. Pick the wrong variable and the file ends up in
# /system/fstab.s88pro, where fs_mgr does not look.
#
# The copy under the old name stays as a safety net. Were the bootloader not to
# pass androidboot.fstab_suffix, fs_mgr would fall back to "mt6771" and without
# that copy first stage would find no fstab at all -- which is not just any
# bootloop, it is the phone falling back to recovery.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6771:$(TARGET_COPY_OUT_RAMDISK)/fstab.s88pro \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6771:$(TARGET_COPY_OUT_RAMDISK)/fstab.mt6771 \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6771:$(TARGET_COPY_OUT_ROOT)/fstab.s88pro

# The two extra cameras -- without this the HAL does not even look for them.
#
# libcam.halsensor.so reads ro.odm_main2_camera and decides from it how far to
# push the search: without it, it stops at index 1 and dmesg shows
# "impSearchSensor search to 1"; with it, it reaches 3 and probes all four
# slots. This is not a deduction -- it is the only property that library
# consults with "cam" or "sensor" in the name, and the behaviour changes with
# it.
#
# On the stock kernel, with this property set, the search finds all four:
# imx230, s5k3p3sx, gc8034 and gc0310.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.odm_main2_camera=1


# The vendor image is Android 10: the framework has to speak its VNDK.
#
# PRODUCT_TARGET_VNDK_VERSION declares which VNDK the vendor uses, but does NOT
# pull in the libraries: those need PRODUCT_EXTRA_VNDK_VERSIONS. Without it,
# /system/lib64/vndk-29 does not exist, the Android 10 vendor binaries cannot
# find their dependencies and boot dies with
#   reboot: Restarting system with command 'boringssl-self-check-failed'
# GSIs ship every VNDK: that is why a GSI boots on this device and our system,
# without this line, does not.
PRODUCT_TARGET_VNDK_VERSION := 29
PRODUCT_EXTRA_VNDK_VERSIONS := 29
PRODUCT_SHIPPING_API_LEVEL := 29

# Framework resource overlay: declares the fingerprint reader.
# See the comment inside overlay/frameworks/base/core/res/res/values/config.xml
DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay

# TEE startup: see the comment inside the file.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/trustkernel-fixup.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/trustkernel-fixup.rc

# Key layout, taken from the stock ROM.
#
# Without this file we fall back to Generic.kl. The two programmable keys on
# the case come from here: the side one as F5 (scancode 63) and the other as
# CAMERA (212); the action to bind is chosen in S88ProParts.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/usr/keylayout/mtk-kpd.kl:$(TARGET_COPY_OUT_SYSTEM)/usr/keylayout/mtk-kpd.kl

# Fingerprint sensor gestures.
#
# The Sunwave reader registers a second input device, sf-keys, which reports
# swipes and taps: verified with getevent, the tap arrives as F10 (scancode 68)
# and the two crosswise swipes as 105 and 106. Without this file they fall back
# to Generic.kl and the swipes move focus inside apps.
#
# The gestures are enabled by <navigation>true</navigation> in
# /vendor/etc/sw_config.xml, which lives in the stock image: see
# hardware-riferimento.md for how to edit it at constant length.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/usr/keylayout/sf-keys.kl:$(TARGET_COPY_OUT_SYSTEM)/usr/keylayout/sf-keys.kl

# Device-specific settings: case LEDs, keys, reverse charging.
PRODUCT_PACKAGES += \
    S88ProParts

# FM radio.
#
# The LineageOS app and the stock one are the same: the vendor's native library
# (libfmjni, among the blobs) registers its methods for exactly
# com/android/fmradio/FmNative. The driver is already loaded at boot by the
# vendor, which insmods fmradio_drv.ko once the connectivity chip is ready.
PRODUCT_PACKAGES += \
    FMRadio

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/s88pro-fm.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/s88pro-fm.rc

# The privileged permission allowlist for S88ProParts: without it the system
# does not boot at all. See the comment inside the file.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/parts/privapp-permissions-s88pro.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/privapp-permissions-s88pro.xml

# EAS boost for foreground apps: without it the UI stutters. Median frame time
# goes from 19 to 11 ms and janky frames from 28.4% to 0.4%. See the comment
# inside the .rc file, which also explains why a service is needed instead of
# two "write" lines.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/s88pro-schedtune.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/s88pro-schedtune.rc \
    $(LOCAL_PATH)/rootdir/etc/s88pro-schedtune.sh:$(TARGET_COPY_OUT_SYSTEM)/etc/s88pro-schedtune.sh

# The serial console shell, which AOSP starts on every userdebug build, must
# not run here. See the comment inside the file: the kernel console stays, only
# the UART prompt goes away.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/s88pro-console.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/s88pro-console.rc

# USB in recovery: without it recovery shows on screen but does not answer adb.
# The reason is in the comment inside the file.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6771.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt6771.rc

# /cache is a symlink to /data/cache, so the AOSP file_contexts does not apply
# and the contents stay unlabelled: in enforcing mode system_server can no
# longer write to /cache/recovery. See the comment inside the file.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/s88pro-cache.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/s88pro-cache.rc



# Device system properties
PRODUCT_SYSTEM_PROPERTIES += \
    ro.hardware=mt6771

# GPU AFBC compression: must be turned off.
#
# The Mali G72 compresses the framebuffers it composes with AFBC, and gralloc
# does so transparently for anyone reading those buffers with the GPU. The
# MediaTek video encoder, however, does not go through the GPU: it takes the
# ion fd from gralloc and feeds it to MDP as if it were linear raster. On a
# compressed buffer the result is banded noise, and that is exactly the picture
# we saw in screen recording, Miracast and scrcpy.
#
# gralloc would know how to avoid it by itself -- it has the "AFBC selected but
# not supported by producer/consumer. Disabling" path -- but it does not fire
# for virtual display buffers. This property disables AFBC for every
# allocation: the broadest option, but also the only one that does not require
# touching gralloc, which is a blob. The cost is a little extra memory
# bandwidth for composition; the gain is hardware screen encoding.
#
# The full reconstruction is in docs/bringup/hardware-riferimento.md.
PRODUCT_SYSTEM_PROPERTIES += \
    debug.gpu.afbc.disable=1


# VoLTE: MediaTek's ImsService.
#
# WORK IN PROGRESS. The stack binds to the framework and the MMTEL feature
# reaches READY, but the capabilities stay empty and registration on the
# network does not happen yet. VoWiFi is deliberately left out: it depends on a
# method MediaTek added to WifiManager which AOSP does not have.
# Status, reconstruction and how to pick it up: docs/bringup/volte-stato-esperimento.md
#
# The APK is not in tree: it is prepared once with ims/prepare-imsservice.sh
# starting from the stock ROM's copy. If it is missing, the build carries on
# without VoLTE and these two lines do no harm: they declare libraries and
# permissions for a package that is not there, which PackageManager ignores.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/ims/mediatek-ims-libs.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/mediatek-ims-libs.xml \
    $(LOCAL_PATH)/ims/privapp-permissions-mtk-ims.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/privapp-permissions-mtk-ims.xml

# The module exists only if the APK has been prepared: naming it regardless
# would fail the build with "module ImsService not found".
ifneq ($(wildcard $(LOCAL_PATH)/ims/ImsService.apk),)
PRODUCT_PACKAGES += \
    ImsService
endif

# libhidltransport and libhwbinder: required by libmtk_vt_wrapper.so, which
# ImsService loads for the video call provider. They are deprecated (folded
# into libhidlbase in Android 11) but Android 12 still builds them, so we take
# them from here rather than from the blobs: copying them from stock would
# define them twice and the build would stop with "overriding commands for
# target".
PRODUCT_PACKAGES += \
    libhidltransport \
    libhwbinder

# The modem keeps VoLTE off until told otherwise.
PRODUCT_SYSTEM_PROPERTIES += \
    persist.vendor.mtk.volte.enable=1

# Bluetooth: which profiles exist.
#
# Since Android 13 the profile list is no longer compiled into the stack: these
# properties decide it, and whoever does not declare them gets none. The
# symptom is not a dead Bluetooth -- the adapter turns on, it has its address,
# scanning finds devices -- but none of those devices connect. In the log:
#
#   BluetoothManagerService: Cannot bind profile: 1, not in supported profiles list
#   CachedBluetoothDevice: No profiles. Maybe we will connect later for device ...
#
# and in dumpsys every connection policy at -1. With the properties in place
# A2dpService, AvrcpTargetService and HeadsetService appear, and the policies
# move to 100.
#
# LE Audio is deliberately left out: the combo chip is an MT6631, which does
# not have it. Profile 22 will keep failing to bind, and rightly so.
PRODUCT_SYSTEM_PROPERTIES += \
    bluetooth.profile.a2dp.source.enabled=true \
    bluetooth.profile.asha.central.enabled=true \
    bluetooth.profile.avrcp.target.enabled=true \
    bluetooth.profile.bas.client.enabled=true \
    bluetooth.profile.gatt.enabled=true \
    bluetooth.profile.hfp.ag.enabled=true \
    bluetooth.profile.hid.device.enabled=true \
    bluetooth.profile.hid.host.enabled=true \
    bluetooth.profile.map.server.enabled=true \
    bluetooth.profile.opp.enabled=true \
    bluetooth.profile.pan.nap.enabled=true \
    bluetooth.profile.pan.panu.enabled=true \
    bluetooth.profile.pbap.server.enabled=true \
    bluetooth.profile.sap.server.enabled=true

# Proprietary blobs extracted from the stock images (Task 4).
# The line kicks in once vendor/doogee/s88pro exists: before that the build
# would fail looking for a makefile that is not there.
$(call inherit-product-if-exists, vendor/doogee/s88pro/s88pro-vendor.mk)


# Not drm@1.2-service.clearkey either: it is the test DRM for CTS, and its
# fragment declares android.hardware.drm 1.2/clearkey while the device manifest
# declares the stock 1.0/default. Two versions of the same HAL, and
# assemble_vintf stops. drm@1.0-service, the real one, stays.
#
# No cas: the stock vendor had android.hardware.cas@1.1-service, but here AOSP
# builds the HAL at version 1.2, which is already installed and brings its own
# VINTF fragment. Asking for 1.1 as well installs two modules for the same HAL,
# and assemble_vintf stops:
#   HAL "android.hardware.cas" has a conflict: Conflicting major version:
#     1.2 (from .../cas@1.2-service.xml) vs. 1.1 (from .../cas@1.1-service.xml)



# No libtinycompress, and it is worth knowing why.
#
# The stock vendor ships it in lib and lib64; here the 32-bit variant does not
# compile:
#   generated_kernel_includes/gen/usr/include/asm/sigcontext.h:74:2:
#     error: unknown type name '__uint128_t'
# The UAPI headers are generated with ARCH=arm64 and end up in the 32-bit
# compile too, where that type does not exist. This is not a flaw in our
# kernel: it is that the same headers serve two architectures.
#
# It is needed for compressed audio (offload playback). If one day it is truly
# missing, the way forward is to generate the UAPI headers for ARCH=arm as
# well, not to force this one.

# A note on libraries with the .vendor suffix: in soong a "vendor_available"
# module produces two variants, and PRODUCT_PACKAGES without the suffix
# installs the system one. Declared without it, they landed in /system/lib64
# and vendor was left without -- something you only see by comparing the two
# images, the build says nothing.

# The properties that lived in the stock /vendor/default.prop.
#
# The file is not copied: it declares ro.vndk.version=29, that is the Android
# 10 VNDK, while the build generates 33. Init reads one and then the other, the
# linker ends up with two versions, and the first to suffer is the BoringSSL
# self test -- which does not fail with a message but reboots the phone:
#   reboot: Restarting system with command 'boringssl-self-check-failed'
# Two rounds of bootloop before finding it, because nothing suggests a line in
# a property file is involved.
#
# Only the ones the build does not generate itself and that are genuinely
# needed stay here: ro.zygote, ro.bionic.* and ro.vndk.version are its job,
# rightly so. ro.apex.updatable: without it, the phone does not boot.
#
# BoardConfig sets TARGET_FLATTEN_APEX := false, so the APEXes are 26 .apex
# files that apexd has to mount. But apexd mounts them only when told to with
# this property, which lives in build/make/target/product/updatable_apex.mk
# together with the flag:
#
#   PRODUCT_VENDOR_PROPERTIES := ro.apex.updatable=true
#   TARGET_FLATTEN_APEX := false
#
# The device tree had picked up only the second line. The first is a VENDOR
# property, and until now it came from the stock vendor -- which has it --
# without anyone noticing. From the moment we install our own vendor image it
# disappears, and the chain is this:
#
#   apexd: ActivateFlattenedApex        (looks for directories, finds files: 0 activated)
#   linkerconfig: Unable to access VNDK APEX at path: /apex/com.android.vndk.v33
#   linkerconfig: terminated by exit(255)
#   reboot: Restarting system with command 'boringssl-self-check-failed'
#
# The last message is misleading -- encryption has nothing to do with it:
# without configured namespaces the self test cannot find libcrypto, and that
# service, when it fails, reboots the phone instead of complaining. The same
# trap is already described in the TARGET_FLATTEN_APEX comment in
# BoardConfig.mk: the second half of the same story.
PRODUCT_VENDOR_PROPERTIES += \
    ro.apex.updatable=true \
    ro.vendor.rc=/vendor/etc/init/hw/ \
    ro.oem_unlock_supported=1 \
    camera.disable_zsl_mode=1 \
    ro.logd.size.stats=64K \
    ro.logd.kernel=false \
    log.tag.stats_log=I \
    dalvik.vm.isa.arm64.variant=cortex-a53 \
    dalvik.vm.isa.arm64.features=default \
    dalvik.vm.isa.arm.variant=cortex-a53 \
    dalvik.vm.isa.arm.features=default

# No HALs or libraries to request for vendor: it is a prebuilt image, see
# BOARD_PREBUILT_VENDORIMAGE in BoardConfig. Everything it needs is already
# inside.
