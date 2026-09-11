#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Every value below was verified on the device during Phases 0-2, not inferred.
# Where a value has a history that explains the choice, the comment records it:
# it is there to stop anyone "fixing" it on a hunch.

DEVICE_PATH := device/doogee/s88pro

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a53

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv7-a-neon
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a53

TARGET_BOARD_PLATFORM := mt6771
TARGET_BOOTLOADER_BOARD_NAME := E977
TARGET_NO_BOOTLOADER := true
TARGET_SCREEN_DENSITY := 480

# Prebuilt kernel: Doogee never published the S88 Pro sources. The binary is
# extracted from the stock boot.img and is identical to the one in the stock
# recovery (9531111 bytes, verified in Phase 1).
BOARD_KERNEL_BASE := 0x40078000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x14f88000
BOARD_KERNEL_TAGS_OFFSET := 0x13f88000
BOARD_BOOTIMG_HEADER_VERSION := 2
# No "androidboot.selinux=permissive" in here: the LineageOS charter requires
# SELinux Enforcing, and now that we build boot.img ourselves that line would
# actually take effect (with the stock boot image the bootloader overrode it
# and the phone stayed Enforcing anyway, which is why the requirement looked
# satisfied when it was not).
#
# The fstab suffix: it is for vold, not for the kernel.
#
# fs_mgr looks for the fstab as "fstab.<suffix>", where the suffix is
# ro.boot.fstab_suffix when present and ro.hardware ("mt6771" here) otherwise,
# and it looks first in /odm/etc, then in /vendor/etc and finally at the root.
# With the prebuilt vendor image, /vendor/etc/fstab.mt6771 is the stock one and
# beats ours: the full explanation is in device.mk, above PRODUCT_COPY_FILES.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 androidboot.fstab_suffix=s88pro
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
# The device tree blob. The stock boot.img has a separate one of 110,368 bytes
# (header version 2), and mkbootimg insists on it:
#   ValueError: DTB image must not be empty.
#
# It is not a prebuilt: our own kernel compiles it, from
# arch/arm64/boot/dts/mediatek/mt6771.dtb (110,304 bytes). While the kernel was
# prebuilt the question did not arise, because boot.img was packed separately
# by replacing only the kernel section.
# BOARD_PREBUILT_DTBIMAGE_DIR is deliberately left UNSET.
#
# Point it at the kernel's dtb directory and build/make/core/Makefile:861 makes
# its dependencies with $(wildcard ...), which make evaluates while reading the
# Makefile: at that moment the kernel has not been compiled yet, the directory
# is empty and dtb.img comes out at 0 bytes.
#
# Leaving it unset brings the LineageOS path into play
# (vendor/lineage/build/tasks/kernel.mk:566): it compiles the dtbs from the
# kernel with make-dtb-target and the right dependencies.
BOARD_INCLUDE_DTB_IN_BOOTIMG := true

# Recovery is built.
#
# It used not to be, for two reasons: the device ran lopestom's TWRP 3.5.2, the
# only one exposing fastbootd, and the build died anyway with
#   ValueError: DTB image must not be empty
# because mkbootimg wants a dtb with --header_version 2 and what it got was 0
# bytes.
#
# The second reason is gone: the 0-byte dtb.img came from
# BOARD_PREBUILT_DTBIMAGE_DIR, dropped a while ago (see the comment above), and
# recovery now gets the same dtb as boot -- build/make/core/Makefile:
#   ifdef BOARD_INCLUDE_DTB_IN_BOOTIMG
#     INTERNAL_RECOVERYIMAGE_ARGS += --dtb $(INSTALLED_DTBIMAGE_TARGET)
#
# The first is no longer a choice: the LineageOS charter requires shipping
# LineageOS Recovery as the default recovery (17.0+ for compatibility, 18.1+
# for the default), and with it come the installable zip and updating through
# the Updater. TWRP is still useful for bring-up work, but whoever wants it has
# to install it by hand.
TARGET_NO_RECOVERY := false
BOARD_USES_RECOVERY_AS_BOOT := false

# Partitions. Sizes read from the device with blockdev --getsize64:
#   boot/recovery 33554432, super 4831838208.
# The dynamic group holds only system and vendor: product was removed in
# Phase 2 to make room for a system image over 2 GB, and the GSI proved it is
# not needed.
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432

# The cache size is for the OTA generator, not for us.
#
# On a non-A/B device the update is applied through /cache, and
# build/make/tools/releasetools/blockimgdiff.py sizes the transfers from how
# big it is. Without being told, "mka bacon" dies like this:
#
#   non_ab_ota.py WARNING: --- can't determine the cache partition size ---
#   blockimgdiff.py:1561  assert cache_size is not None -> AssertionError
#
# The value is the real one, read from the phone:
#   blockdev --getsize64 /dev/block/by-name/cache

# The vendor image is not built: we take the stock one.
#
# This phone's vendor is Android 10 and we have the sources for none of what it
# contains. Rebuilding it from the blobs is possible -- 1622 files extracted,
# we spent an afternoon on it -- but the fact remains that the build installs
# its own modules into /vendor anyway, and for every file where the two overlap
# someone has to decide which wins. For vibrator or memtrack the answer is
# easy; for the graphics composer, for gralloc, for the fingerprint HAL it is
# not, and getting it wrong does not produce an error: it produces a phone
# stuck on the bootloader logo, with nothing to read.
#
# With BOARD_PREBUILT_VENDORIMAGE the build copies the image instead of
# building it (build/make/core/Makefile:3601) and BUILDING_VENDOR_IMAGE stays
# empty, so it no longer installs anything in there. The result is bit-for-bit
# identical to what has always run on the phone.
#
# The price is that vendor cannot be inspected file by file from the device
# tree, and for a LineageOS submission that is a point to discuss. The
# advantage is that the installable zip works, which was the requirement.
#
# The image is not the stock one verbatim, though: our fstab goes inside it,
# because the vendor init files mount /data by name and there is no other way
# to make them read it. The rule that produces it, with the reasons in full,
# is in Android.mk.
S88PRO_VENDOR_WITH_FSTAB := $(PRODUCT_OUT)/vendor-with-our-fstab.img
BOARD_PREBUILT_VENDORIMAGE := $(S88PRO_VENDOR_WITH_FSTAB)

BOARD_CACHEIMAGE_PARTITION_SIZE := 452984832
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4

# Vendor blobs are copied, not declared one by one.
#
# The build rejects ELF files in PRODUCT_COPY_FILES:
#   FAILED: ...check-non-elf-file-timestamps.../lib64/libXXX.so.timestamp
# and the official way would be a BUILD_PREBUILT module per library. With the
# 947 in the MediaTek vendor that does not scale: 361 have a repeated basename
# -- the same library in lib and in lib64, or in hw/ and at the root -- and two
# modules with the same LOCAL_MODULE silently override each other.
#
# AOSP has a switch for exactly this (build/make/core/board_config.mk:179).
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BOARD_SUPER_PARTITION_SIZE := 4831838208
BOARD_SUPER_PARTITION_GROUPS := doogee_dynamic_partitions
BOARD_DOOGEE_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor
BOARD_DOOGEE_DYNAMIC_PARTITIONS_SIZE := 4827643904
# Note: PRODUCT_USE_DYNAMIC_PARTITIONS is a PRODUCT variable and lives in
# device.mk. Putting it here fails configuration with
#   cannot assign to readonly variable: PRODUCT_USE_DYNAMIC_PARTITIONS

# The vendor VINTF manifest. It is the stock ROM's, extracted from the phone's
# /vendor/etc/vintf/manifest.xml: it describes which HALs the vendor offers,
# and the blobs in vendor/doogee/s88pro are exactly those.
#
# Without it the build stops at the very end, when checking compatibility:
#   Fetch 'out/.../vendor/etc/vintf/manifest.xml': NAME_NOT_FOUND
#   ERROR: Cannot fetch vendor manifest.
# (in vendor/etc/vintf the build creates the manifest/ directory for fragments,
# but the main manifest has to come from the device tree)
# The device manifest is joined by the gpu@1.0 fragment that the stock vendor
# kept separate in /vendor/etc/vintf/manifest/. It cannot be copied as a file,
# the build refuses:
#   error: VINTF metadata found in PRODUCT_COPY_FILES: ... use DEVICE_MANIFEST_FILE
#
# The cas one must NOT be added: the stock vendor declared cas@1.1, but here
# AOSP builds the HAL at version 1.2, which brings its own fragment. Declaring
# both makes assemble_vintf stop with
#   HAL "android.hardware.cas" has a conflict: Conflicting major version:
#     1.1 (from manifest.xml) vs. 1.2 (from .../cas@1.2-service.xml)
DEVICE_MANIFEST_FILE := \
    $(DEVICE_PATH)/manifest.xml \
    vendor/doogee/s88pro/proprietary/vendor/etc/vintf/manifest/android.hardware.gpu@1.0-service.xml
# The compatibility matrix: the framework HALs this device requires. It is the
# stock ROM's, taken from the phone's
# /vendor/etc/vintf/compatibility_matrix.xml, WITHOUT the vendor-ndk and
# system-sdk sections.
#
# Dropping them is not an oversight. The stock matrix asked for version 29
# (Android 10), the build-generated one asks for 33. Neither works, because
# above there is BOARD_VNDK_VERSION := current, and with "current" the
# framework lists no numeric version in its manifest: any requirement goes
# unmatched and checkvintf stops with
#   Vndk version 33 is not supported. Supported versions in framework
#   manifest are: []
# That Android 10 blobs run under the Android 13 framework is a measured fact:
# it is the ROM sitting on the phone.
#
# The file carries NO XML comments: assemble_vintf rejects them with
#   Input file has unknown format. ... Not a valid XML
# (verified: the same file without the comment passes).
DEVICE_MATRIX_FILE := $(DEVICE_PATH)/compatibility_matrix.xml

TARGET_COPY_OUT_VENDOR := vendor

# Makes the /metadata directory be created in system.
#
# Without it our system has no such mount point (the GSI does: that is the
# difference that made it boot) and two things follow in a chain:
#   init: Unable to move mount at '/metadata': No such file or directory
# and removing /metadata from the fstab to work around that leaves apexd
# without its data area, the APEXes do not mount and boot dies with
#   reboot: Restarting system with command 'boringssl-self-check-failed'
# because the crypto library lives in the com.android.conscrypt APEX.
BOARD_USES_METADATA_PARTITION := true
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Verified Boot disabled.
# The bootloader rejects images signed with keys it does not know, and in
# Phase 1 that produced repeated bootloops. On an unlocked bootloader an
# unsigned image is instead accepted with the "orange state" warning.
BOARD_AVB_ENABLE := false

# APEXes as packages, not flattened.
#
# The AOSP default is TARGET_FLATTEN_APEX := true: the APEXes end up in
# /system/apex as directories, and init is supposed to bind-mount them onto
# /apex. On this device that does not happen, and boot dies like this:
#   apexd: Scanning /system/apex for pre-installed ApexFiles
#   apexd: Activated 0 packages.
#   linkerconfig: executing /apex/com.android.runtime/bin/linkerconfig
#                 failed: No such file or directory
# apexd looks for .apex *files* and finds only directories. Without
# /apex/com.android.runtime there is no linker (/system/bin/linker is a symlink
# in there), so the first service init launches in early-init fails to start
# and the device reboots with
#   reboot: Restarting system with command 'boringssl-self-check-failed'
# a misleading message: it is not encryption, it is the missing interpreter.
#
# The GSI that boots on this phone has the APEXes as files: it inherits
# updatable_apex.mk through generic_system.mk. We take only this line, without
# PRODUCT_COMPRESSED_APEX: .capex files have to be decompressed into /data on
# first boot, a complication we do not need.
TARGET_FLATTEN_APEX := false

# FM radio: the native library comes from the device, not from LineageOS.
#
# packages/apps/FMRadio ships a generic libfmjni, which however cannot talk to
# the MediaTek driver. Its Android.mk allows for our case:
#   ifneq ($(BOARD_HAVE_MTK_FM),true) ... builds its own ... endif
# Declaring this stops the generic one being built and leaves ours in place,
# taken from the stock ROM (see proprietary-files.txt). Without this line the
# build stops with
#   MODULE.TARGET.SHARED_LIBRARIES.libfmjni already defined
BOARD_HAVE_MTK_FM := true

# Vendor VNDK: the device shipped with Android 10.
BOARD_VNDK_VERSION := current

# Do NOT set BOARD_SEPOLICY_VERS := 29.0.
#
# It looks like the right choice (the vendor is Android 10) but it does not
# compile: the LineageOS common sepolicy uses macros introduced after
# Android 10, and checkpolicy stops with
#   device/lineage/sepolicy/common/public/property.te: syntax error at
#   token system_vendor_config_prop
#
# The mismatch with the vendor's prebuilt policy is instead solved by removing
# that policy from the vendor image itself, so init has nothing to compare
# against and uses the system policy directly.
PRODUCT_SEPOLICY_SPLIT := true

BOARD_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor

# Rules between SYSTEM types go here, not in BOARD_SEPOLICY_DIRS
# (BOARD_PLAT_PRIVATE_SEPOLICY_DIR is obsolete).
#
# They close two denials measured on the phone with SELinux Enforcing:
#   system_app -> sysfs_leds       S88ProParts could not reach the notification LEDs
#   nfc        -> system_data_file /data/nfc is not mapped in AOSP
#
# The 52 boot-time denials (vold -> sysfs_mmcblk, aee_aedv -> proc_ppm) are NOT
# closable from here: those types are defined by the vendor policy, which
# arrives already compiled in the blob (TARGET_USES_PREBUILT_VENDOR_SEPOLICY).
# Neither of them blocks anything.
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/system_ext/private

# The vendor sepolicy is the stock one; we do not build it.
#
# The vendor image we flash is stock MediaTek: its vendor_sepolicy.cil (826 KB)
# carries the rules for the MediaTek HALs, which ours (123 KB) does not have.
# Replacing it, as was done to work around a secilc failure, strikes the vendor
# services dumb: no context, no registration with hwservicemanager, and
# system_server hangs forever waiting for them. The ANR said so word for word:
#   PowerHalLoader::loadHidlV1_0() -> getRawServiceInternal(...)
#   at com.android.server.power.PowerManagerService.nativeInit(Native method)
#
# With this flag init recompiles the policy at runtime, joining our platform
# policy to the MediaTek rules, which is the intended mechanism for an
# Android 10 vendor under an Android 12 framework (the 29.0.cil mapping is
# there).
#
# The second flag removes a line that made that recompilation fail:
#   device/lineage/sepolicy/common/private/genfs_contexts
#     genfscon fuseblk / u:object_r:vfat:s0
# while the MediaTek vendor declares the same filesystem as
#     genfscon fuseblk / u:object_r:fuseblk:s0
# Two contexts for the same path: secilc stops with
#   Problems processing genfscon rules / Failed to compile cildb: -1
# and init, left without a policy, reboots into the bootloader.
#
# Both have to be declared: the first would default to true, but only when
# BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE is empty, and here it is ext4.
TARGET_USES_PREBUILT_VENDOR_SEPOLICY := true
TARGET_HAS_FUSEBLK_SEPOLICY_ON_VENDOR := true

# ---------------------------------------------------------------------------
# THE KERNEL IS BUILT FROM SOURCE
#
# The LineageOS charter requires it: "Non-GKI devices MUST NOT ship a prebuilt
# kernel". The sources live in kernel/doogee/s88pro, and the local manifest
# (s88pro.xml) pulls them down along with the rest.
#
# prebuilt/kernel stays in the repo for anyone who only wants to install
# without rebuilding: LineageOS would use it only with
# TARGET_FORCE_PREBUILT_KERNEL.

# The fstab recovery uses. It was there, in rootdir/etc/, but was not declared,
# and without this line the build produces NO installable ROM at all:
# build/make/core/Makefile turns off build_ota_package when recovery_fstab is
# empty, INTERNAL_OTA_PACKAGE_TARGET stays empty, and the "bacon" target ends
# up running "ln -f" on a file nobody built:
#   ln: cannot create hard link from '.../lineage-20.0-...-s88pro.zip'
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.mt6771

# Which file to take from arch/arm64/boot/. Without it the build copies the
# DIRECTORY:
#   cp "out/.../obj/KERNEL_OBJ/arch/arm64/boot/" "out/.../kernel"
#   cp: Skipped dir '...': No such file or directory
# It was only needed with the prebuilt kernel, where the file was already
# chosen.
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb

TARGET_KERNEL_SOURCE := kernel/doogee/s88pro
TARGET_KERNEL_CONFIG := lineage_s88pro_defconfig

# The clang version has to be pinned, not left at the "clang-stable" default:
# prebuilts/clang/host/linux-x86/clang-stable holds only clang-format, and the
# build dies with "clang: command not found".
#
# LineageOS 20 ships clang-r450784d (14.0.6), and that is fine: the two
# warnings that on clang-17 forced us to turn them off --
# deprecated-non-prototype and single-bit-bitfield-constant-conversion -- were
# INTRODUCED in clang-15 and 16. clang-14 does not emit them, so the matching
# -Wno- flags are unnecessary; and passing them would make it fail, because it
# reports them as an unknown option and the -fstack-protector-strong test does
# not pass.
TARGET_KERNEL_CLANG_VERSION := r450784d

# The warnings clang-14 has and the stock clang-9 does not. The kernel builds
# with -Werror, and code from 2019 becomes an error purely because the compiler
# is newer. We turn off the INDIVIDUAL warnings, not -Werror as a whole: that
# way a real defect still stops the build.
KERNEL_WARN_OFF := -Wno-unused-but-set-variable
KERNEL_WARN_OFF += -Wno-void-pointer-to-enum-cast
KERNEL_WARN_OFF += -Wno-strict-prototypes
KERNEL_WARN_OFF += -Wno-enum-conversion
KERNEL_WARN_OFF += -Wno-sometimes-uninitialized
KERNEL_WARN_OFF += -Wno-misleading-indentation
KERNEL_WARN_OFF += -Wno-bool-operation
KERNEL_WARN_OFF += -Wno-gnu-variable-sized-type-not-at-end
# -fuse-ld=lld (below, in KCFLAGS) is needed to LINK the vdso, but it also ends
# up in ordinary compiles, where clang reports it as an unused argument -- and
# with -Werror that would be an error.
KERNEL_WARN_OFF += -Wno-unused-command-line-argument

# LLVM_IAS=0: clang's integrated assembler cannot digest the assembly of a 4.14
# kernel (arch/arm64/mm/fault.c, "junk at end of line"); we use the GNU binutils
# one, which accepts that code.
#
# KCFLAGS=-gdwarf-4: with the binutils 4.9 assembler -- from 2014 -- DWARF 5
# directives become "file number less than one". Asking for DWARF 4 makes the
# format readable again and CONFIG_DEBUG_INFO stays on as it is in stock.
# HOSTCFLAGS=-fuse-ld=lld: the Android build sanitises PATH and does not put
# "ld" in it (it is not in prebuilts/build-tools/path/linux-x86). The 4.14
# kernel links its host tools -- the first is scripts/basic/fixdep -- by
# calling HOSTCC without passing HOSTLDFLAGS, and clang looks for "ld":
#   clang-14: error: unable to execute command: Executable "ld" doesn't exist!
# With -fuse-ld=lld it uses the linker sitting next to the compiler.
TARGET_KERNEL_ADDITIONAL_FLAGS := LLVM_IAS=0 HOSTCFLAGS="-fuse-ld=lld" KCFLAGS="-gdwarf-4 -fuse-ld=lld $(KERNEL_WARN_OFF)"

# NO "include vendor/lineage/config/BoardConfigLineage.mk" here: it is already
# done by build/core/config.mk:361, and including it a second time breaks the
# export to soong -- SOONG_CONFIG_NAMESPACES ends up with lineageVarsPlugin
# twice and the list of exported variables stops halfway.

# The device-specific OTA hooks, in releasetools.py next to this file.
#
# They exist because two things cannot be said in a makefile variable:
#
#   FullOTA_Assertions   refuses to install on a phone running a different
#                        stock firmware. The charter asks a non-A/B device
#                        relying on an OEM vendor partition to assert the
#                        vendor image version at flash time, and this device
#                        relies on one -- BOARD_PREBUILT_VENDORIMAGE above.
#
#   FullOTA_InstallEnd   writes recovery.img. non_ab_ota.py puts it in every
#                        package but only writes it for two-step packages, and
#                        the usual road -- install-recovery.sh in /vendor/bin --
#                        is closed here, because with the prebuilt vendor image
#                        the build installs nothing into /vendor.
TARGET_RELEASETOOLS_EXTENSIONS := $(DEVICE_PATH)

# No AOT compilation for the MediaTek prebuilt .jars.
#
# They come from the stock Android 10 ROM and reference AOSP classes that
# Android 13 no longer has. dex2oat verifies before compiling, and with
# --abort-on-hard-verifier-error it stops the build:
#
#   Verification error in void com.mediatek.internal.telephony.gsm.
#     MtkGsmCellBroadcastHandler.<init>(Context, Phone)
#   'this' argument ... not instance of 'Unresolved Reference:
#     com.android.internal.telephony.gsm.GsmCellBroadcastHandler'
#
# GsmCellBroadcastHandler left the framework after Android 10: cell broadcast
# moved into the com.android.cellbroadcast APEX. The class cannot resolve, and
# no amount of configuring will make it.
#
# This is not a regression, it is the previous behaviour made explicit. Until
# extract-utils generated these makefiles the .jars travelled through
# PRODUCT_COPY_FILES, and a copied file is never preopted -- nobody was
# verifying them either. ART verifies at load time instead, and fails soft on
# the single class that cannot resolve while the rest of the jar works, which
# is why telephony has always worked on this phone.
#
# The cost is startup time on these jars, not correctness.
DEXPREOPT_DISABLED_MODULES := \
    mediatek-common \
    mediatek-framework \
    mediatek-framework-net \
    mediatek-ims-base \
    mediatek-ims-common \
    mediatek-ims-extension-plugin \
    mediatek-ims-legacy \
    mediatek-services \
    mediatek-telecom-common \
    mediatek-telephony-base \
    mediatek-telephony-common \
    mediatek-wfo-legacy \
    mtk-ims-compat
