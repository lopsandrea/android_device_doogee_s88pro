#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Tutti i valori qui sotto sono stati verificati sul device nelle Fasi 0-2,
# non dedotti. Dove un valore ha una storia che ne spiega la scelta, il
# commento la riporta: serve a non "correggerlo" per intuizione.

DEVICE_PATH := device/doogee/S88Pro

# Architettura
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

# Kernel prebuilt: Doogee non ha mai pubblicato i sorgenti del S88 Pro.
# Il binario e' estratto dal boot.img stock ed e' identico a quello della
# recovery stock (9531111 byte, verificato in Fase 1).
BOARD_KERNEL_BASE := 0x40078000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x14f88000
BOARD_KERNEL_TAGS_OFFSET := 0x13f88000
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 androidboot.selinux=permissive
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
BOARD_INCLUDE_DTB_IN_BOOTIMG :=

# Non si costruisce la recovery.
#
# Sul device usiamo la TWRP 3.5.2 di lopestom, l'unica che espone fastbootd
# e senza la quale le partizioni logiche non si toccano. Costruirne una qui
# non servirebbe, e comunque fallisce: mkbootimg con --header_version 2 e
# nessun dtb muore con "ValueError: DTB image must not be empty", lo stesso
# muro incontrato in Fase 1.
TARGET_NO_RECOVERY := true
BOARD_USES_RECOVERY_AS_BOOT := false

# Partizioni. Dimensioni lette dal device con blockdev --getsize64:
#   boot/recovery 33554432, super 4831838208.
# Il gruppo dinamico contiene solo system e vendor: product e' stata
# eliminata in Fase 2 per far spazio a un system da oltre 2 GB, e la GSI
# ha dimostrato di non averne bisogno.
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432
BOARD_SUPER_PARTITION_SIZE := 4831838208
BOARD_SUPER_PARTITION_GROUPS := doogee_dynamic_partitions
BOARD_DOOGEE_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor
BOARD_DOOGEE_DYNAMIC_PARTITIONS_SIZE := 4827643904
# Nota: PRODUCT_USE_DYNAMIC_PARTITIONS e' una variabile di PRODOTTO e vive in
# device.mk. Metterla qui fa fallire la configurazione con
#   cannot assign to readonly variable: PRODUCT_USE_DYNAMIC_PARTITIONS

TARGET_COPY_OUT_VENDOR := vendor

# Fa creare la directory /metadata nella system.
#
# Senza, il nostro system non ha quel punto di mount (la GSI si': e' la
# differenza che la faceva avviare) e succedono due cose a catena:
#   init: Unable to move mount at '/metadata': No such file or directory
# e togliendo /metadata dal fstab per aggirarla, apexd resta senza la sua
# area dati, gli APEX non si montano e il boot muore con
#   reboot: Restarting system with command 'boringssl-self-check-failed'
# perche' la libreria crypto vive nell'APEX com.android.conscrypt.
BOARD_USES_METADATA_PARTITION := true
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Verified Boot disabilitato.
# Il bootloader rifiuta le immagini firmate con chiavi che non conosce, e
# in Fase 1 questo ha prodotto bootloop ripetuti. Su bootloader sbloccato
# un'immagine non firmata viene invece accettata con l'avviso "orange state".
BOARD_AVB_ENABLE := false

# APEX come pacchetti, non "flattened".
#
# Il default di AOSP e' TARGET_FLATTEN_APEX := true: gli APEX finiscono in
# /system/apex come directory, e init dovrebbe montarle in bind su /apex.
# Su questo device non succede, e il boot muore cosi:
#   apexd: Scanning /system/apex for pre-installed ApexFiles
#   apexd: Activated 0 packages.
#   linkerconfig: executing /apex/com.android.runtime/bin/linkerconfig
#                 failed: No such file or directory
# apexd cerca *file* .apex e trova solo directory. Senza
# /apex/com.android.runtime non esiste il linker (/system/bin/linker e' un
# symlink li dentro), quindi il primo servizio che init lancia in early-init
# non parte e il device riavvia con
#   reboot: Restarting system with command 'boringssl-self-check-failed'
# messaggio fuorviante: non e' la crittografia, e' l'interprete mancante.
#
# La GSI che si avvia su questo telefono ha gli APEX come file: eredita
# updatable_apex.mk tramite generic_system.mk. Noi prendiamo solo questa
# riga, senza PRODUCT_COMPRESSED_APEX: gli .capex vanno decompressi in
# /data al primo avvio, complicazione che non ci serve.
TARGET_FLATTEN_APEX := false

# Radio FM: la libreria nativa la fornisce il device, non LineageOS.
#
# packages/apps/FMRadio porta con se' una libfmjni generica, che pero' non sa
# parlare con il driver MediaTek. Il suo Android.mk prevede il nostro caso:
#   ifneq ($(BOARD_HAVE_MTK_FM),true) ... compila la propria ... endif
# Dichiarandolo, quella generica non viene costruita e resta la nostra, presa
# dalla ROM di fabbrica (vedi proprietary-files.txt). Senza questa riga la
# build si ferma con
#   MODULE.TARGET.SHARED_LIBRARIES.libfmjni already defined
BOARD_HAVE_MTK_FM := true

# VNDK del vendor: il device e' nato con Android 10.
BOARD_VNDK_VERSION := current

# NON impostare BOARD_SEPOLICY_VERS := 29.0.
#
# Sembra la scelta giusta (il vendor e' Android 10) ma non compila: la
# sepolicy comune di LineageOS usa macro introdotte dopo Android 10, e
# checkpolicy si ferma con
#   device/lineage/sepolicy/common/public/property.te: syntax error at
#   token system_vendor_config_prop
#
# Il disallineamento con la policy precompilata del vendor si risolve
# invece rimuovendo quest ultima dal vendor stesso, cosi init non ha nulla
# da confrontare e usa direttamente la policy di system.
PRODUCT_SEPOLICY_SPLIT := true

BOARD_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor

# La sepolicy del vendor e' quella di fabbrica, non la costruiamo.
#
# Il vendor che flashiamo e' lo stock MediaTek: la sua vendor_sepolicy.cil
# (826 KB) contiene le regole per le HAL MediaTek, che la nostra (123 KB) non
# ha. Sostituirla, come si era fatto per aggirare un fallimento di secilc,
# rende muti i servizi del vendor: nessun contesto, nessuna registrazione su
# hwservicemanager, e system_server resta appeso per sempre ad aspettarli.
# L'ANR lo diceva parola per parola:
#   PowerHalLoader::loadHidlV1_0() -> getRawServiceInternal(...)
#   at com.android.server.power.PowerManagerService.nativeInit(Native method)
#
# Con questo flag init ricompila a runtime la policy unendo la nostra
# piattaforma alle regole MediaTek, che e' il meccanismo previsto per un
# vendor Android 10 sotto un framework Android 12 (il mapping 29.0.cil c'e').
#
# Il secondo flag toglie una riga che faceva fallire quella ricompilazione:
#   device/lineage/sepolicy/common/private/genfs_contexts
#     genfscon fuseblk / u:object_r:vfat:s0
# mentre il vendor MediaTek dichiara lo stesso filesystem come
#     genfscon fuseblk / u:object_r:fuseblk:s0
# Due contesti per lo stesso path: secilc si ferma con
#   Problems processing genfscon rules / Failed to compile cildb: -1
# e init, rimasto senza policy, riavvia nel bootloader.
#
# Vanno dichiarati entrambi: il primo avrebbe un default a true, ma solo se
# BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE e' vuota, e qui vale ext4.
TARGET_USES_PREBUILT_VENDOR_SEPOLICY := true
TARGET_HAS_FUSEBLK_SEPOLICY_ON_VENDOR := true
