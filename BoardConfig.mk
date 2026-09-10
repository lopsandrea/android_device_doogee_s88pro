#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Tutti i valori qui sotto sono stati verificati sul device nelle Fasi 0-2,
# non dedotti. Dove un valore ha una storia che ne spiega la scelta, il
# commento la riporta: serve a non "correggerlo" per intuizione.

DEVICE_PATH := device/doogee/s88pro

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
# Niente "androidboot.selinux=permissive" qui dentro: il charter di LineageOS
# vuole SELinux Enforcing, e da quando il boot.img lo costruiamo noi quella
# riga fa davvero effetto (con il boot di fabbrica il bootloader la
# sovrascriveva e il telefono restava Enforcing lo stesso, che e' il motivo
# per cui il requisito sembrava soddisfatto quando non lo era).
#
# Il suffisso del fstab: serve a vold, non al kernel.
#
# fs_mgr cerca il fstab come "fstab.<suffisso>", dove il suffisso e'
# ro.boot.fstab_suffix se c'e' e ro.hardware (qui "mt6771") altrimenti, e lo
# cerca prima in /odm/etc, poi in /vendor/etc e infine nella radice. Con il
# vendor prebuilt, /vendor/etc/fstab.mt6771 e' quello di fabbrica e vince sul
# nostro: la spiegazione per esteso sta in device.mk, sopra PRODUCT_COPY_FILES.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 androidboot.fstab_suffix=s88pro
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
# Il device tree binario. Il boot.img di fabbrica ne ha uno separato di 110.368
# byte (header version 2), e mkbootimg lo pretende:
#   ValueError: DTB image must not be empty.
#
# Non e' un prebuilt: lo compila il nostro kernel, da
# arch/arm64/boot/dts/mediatek/mt6771.dtb (110.304 byte). Finche' il kernel era
# precompilato la questione non si poneva, perche' il boot.img veniva
# confezionato a parte sostituendo la sola sezione kernel.
# BOARD_PREBUILT_DTBIMAGE_DIR resta NON impostata di proposito.
#
# Puntandola alla directory dei dtb del kernel, build/make/core/Makefile:861
# ne fa le dipendenze con $(wildcard ...), che make valuta quando legge il
# Makefile: in quel momento il kernel non e' ancora stato compilato, la
# directory e' vuota e dtb.img esce di 0 byte.
#
# Lasciandola vuota entra in funzione il percorso di LineageOS
# (vendor/lineage/build/tasks/kernel.mk:566): compila i dtb dal kernel con
# make-dtb-target e le dipendenze giuste.
BOARD_INCLUDE_DTB_IN_BOOTIMG := true

# La recovery si costruisce.
#
# Prima non si faceva, per due motivi: sul device girava la TWRP 3.5.2 di
# lopestom, l'unica che espone fastbootd, e il build moriva comunque con
#   ValueError: DTB image must not be empty
# perche' mkbootimg vuole un dtb con --header_version 2 e quello che gli
# arrivava era di 0 byte.
#
# Il secondo motivo non c'e' piu': il dtb.img di 0 byte veniva da
# BOARD_PREBUILT_DTBIMAGE_DIR, tolta da un pezzo (vedi il commento sopra), e
# ora la recovery riceve lo stesso dtb del boot -- build/make/core/Makefile:
#   ifdef BOARD_INCLUDE_DTB_IN_BOOTIMG
#     INTERNAL_RECOVERYIMAGE_ARGS += --dtb $(INSTALLED_DTBIMAGE_TARGET)
#
# Il primo non e' piu' una scelta: il charter di LineageOS chiede di spedire
# LineageOS Recovery come recovery predefinita (17.0+ per la compatibilita',
# 18.1+ per il default), e con essa arrivano lo zip installabile e
# l'aggiornamento dall'Updater. TWRP resta utile per il lavoro di bring-up,
# ma va installata a mano da chi la vuole.
TARGET_NO_RECOVERY := false
BOARD_USES_RECOVERY_AS_BOOT := false

# Partizioni. Dimensioni lette dal device con blockdev --getsize64:
#   boot/recovery 33554432, super 4831838208.
# Il gruppo dinamico contiene solo system e vendor: product e' stata
# eliminata in Fase 2 per far spazio a un system da oltre 2 GB, e la GSI
# ha dimostrato di non averne bisogno.
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432

# La cache serve al generatore dell'OTA, non a noi.
#
# Su un device non-A/B l'aggiornamento si applica passando per /cache, e
# build/make/tools/releasetools/blockimgdiff.py dimensiona i trasferimenti in
# base a quanto e' grande. Se non gliela si dice, "mka bacon" muore cosi':
#
#   non_ab_ota.py WARNING: --- can't determine the cache partition size ---
#   blockimgdiff.py:1561  assert cache_size is not None -> AssertionError
#
# Il valore e' quello vero, letto dal telefono:
#   blockdev --getsize64 /dev/block/by-name/cache
# La vendor non si costruisce: si prende quella di fabbrica.
#
# Il vendor di questo telefono e' Android 10 e non abbiamo i sorgenti di
# niente di cio' che contiene. Ricostruirlo dai blob si puo' -- 1622 file
# estratti, ci abbiamo passato un pomeriggio -- ma resta il fatto che il build
# installa comunque i propri moduli in /vendor, e per ogni file su cui i due
# si sovrappongono bisogna decidere chi vince. Per la vibrazione o memtrack la
# risposta e' facile; per il composer grafico, per il gralloc, per la HAL
# delle impronte no, e sbagliare non da' un errore: da' un telefono fermo sul
# logo del bootloader, senza niente da leggere.
#
# Con BOARD_PREBUILT_VENDORIMAGE il build copia l'immagine invece di
# costruirla (build/make/core/Makefile:3601) e BUILDING_VENDOR_IMAGE resta
# vuota, quindi non installa piu' niente li' dentro. Il risultato e' identico
# bit per bit a quello che gira sul telefono da sempre.
#
# Il prezzo e' che il vendor non e' ispezionabile file per file dal device
# tree, e per una sottomissione a LineageOS e' un punto da discutere. Il
# vantaggio e' che lo zip installabile funziona, che era il requisito.
#
# L'immagine non e' pero' quella di fabbrica tale e quale: dentro ci va il
# nostro fstab, perche' i file init del vendor montano /data per nome e non
# c'e' altro modo di farglielo leggere. La regola che la produce, con le
# ragioni per esteso, sta in Android.mk.
S88PRO_VENDOR_CON_FSTAB := $(PRODUCT_OUT)/vendor-con-il-nostro-fstab.img
BOARD_PREBUILT_VENDORIMAGE := $(S88PRO_VENDOR_CON_FSTAB)

BOARD_CACHEIMAGE_PARTITION_SIZE := 452984832
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4

# I blob del vendor si copiano, non si dichiarano uno per uno.
#
# Il build rifiuta i file ELF in PRODUCT_COPY_FILES:
#   FAILED: ...check-non-elf-file-timestamps.../lib64/libXXX.so.timestamp
# e la via ufficiale sarebbe un modulo BUILD_PREBUILT per libreria. Con le 947
# del vendor MediaTek non regge: 361 hanno un basename che si ripete -- la
# stessa libreria in lib e in lib64, oppure in hw/ e nella radice -- e due
# moduli con lo stesso LOCAL_MODULE si sovrascrivono a vicenda, silenziosamente.
#
# AOSP ha l'interruttore apposta (build/make/core/board_config.mk:179).
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BOARD_SUPER_PARTITION_SIZE := 4831838208
BOARD_SUPER_PARTITION_GROUPS := doogee_dynamic_partitions
BOARD_DOOGEE_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor
BOARD_DOOGEE_DYNAMIC_PARTITIONS_SIZE := 4827643904
# Nota: PRODUCT_USE_DYNAMIC_PARTITIONS e' una variabile di PRODOTTO e vive in
# device.mk. Metterla qui fa fallire la configurazione con
#   cannot assign to readonly variable: PRODUCT_USE_DYNAMIC_PARTITIONS

# Il manifest VINTF del vendor. E' quello della ROM di fabbrica, estratto da
# /vendor/etc/vintf/manifest.xml del telefono: descrive quali HAL il vendor
# offre, e i blob in vendor/doogee/s88pro sono proprio quelli.
#
# Senza, il build si ferma in fondo, quando verifica la compatibilita':
#   Fetch 'out/.../vendor/etc/vintf/manifest.xml': NAME_NOT_FOUND
#   ERROR: Cannot fetch vendor manifest.
# (in vendor/etc/vintf il build crea la directory manifest/ per i frammenti,
# ma il manifest principale deve fornirlo il device tree)
# Al manifest del device si unisce il frammento gpu@1.0 che il vendor di
# fabbrica teneva separato in /vendor/etc/vintf/manifest/. Copiarlo come file
# non si puo', il build lo rifiuta:
#   error: VINTF metadata found in PRODUCT_COPY_FILES: ... use DEVICE_MANIFEST_FILE
#
# Quello di cas invece NON va aggiunto: il vendor di fabbrica dichiarava
# cas@1.1, ma la HAL qui la compila AOSP nella versione 1.2, che si porta il
# proprio frammento. Dichiarandoli entrambi assemble_vintf si ferma con
#   HAL "android.hardware.cas" has a conflict: Conflicting major version:
#     1.1 (from manifest.xml) vs. 1.2 (from .../cas@1.2-service.xml)
DEVICE_MANIFEST_FILE := \
    $(DEVICE_PATH)/manifest.xml \
    vendor/doogee/s88pro/proprietary/vendor/etc/vintf/manifest/android.hardware.gpu@1.0-service.xml
# La matrice di compatibilita': gli HAL del framework che questo device
# pretende. E' quella della ROM di fabbrica, presa da
# /vendor/etc/vintf/compatibility_matrix.xml del telefono, SENZA le sezioni
# vendor-ndk e system-sdk.
#
# Toglierle non e' una svista. La matrice di fabbrica chiedeva la versione 29
# (Android 10), quella generata dal build chiede 33. Nessuna delle due va bene,
# perche' qui sopra c'e' BOARD_VNDK_VERSION := current, e con "current" il
# framework non elenca nessuna versione numerica nel suo manifest: qualunque
# requisito resta senza riscontro e checkvintf si ferma con
#   Vndk version 33 is not supported. Supported versions in framework
#   manifest are: []
# Che i blob di Android 10 girino sotto il framework di Android 13 e' un fatto
# misurato: e' la ROM che sta sul telefono.
#
# Nel file NON ci sono commenti XML: assemble_vintf li rifiuta con
#   Input file has unknown format. ... Not a valid XML
# (verificato: lo stesso file senza commento passa).
DEVICE_MATRIX_FILE := $(DEVICE_PATH)/compatibility_matrix.xml

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

# Le regole fra tipi di SISTEMA vanno qui, non in BOARD_SEPOLICY_DIRS
# (BOARD_PLAT_PRIVATE_SEPOLICY_DIR e obsoleta).
#
# Chiudono due denial misurati sul telefono con SELinux Enforcing:
#   system_app -> sysfs_leds       S88ProParts non arrivava ai LED di notifica
#   nfc        -> system_data_file /data/nfc non e mappato in AOSP
#
# I 52 denial dell avvio (vold -> sysfs_mmcblk, aee_aedv -> proc_ppm) NON sono
# chiudibili da qui: quei tipi li definisce la policy del vendor, che arriva
# gia compilata nel blob (TARGET_USES_PREBUILT_VENDOR_SEPOLICY). Nessuno dei
# due blocca qualcosa.
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/system_ext/private

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

# ---------------------------------------------------------------------------
# IL KERNEL SI COMPILA DAI SORGENTI
#
# Il charter di LineageOS lo chiede: "Non-GKI devices MUST NOT ship a prebuilt
# kernel". I sorgenti stanno in kernel/doogee/s88pro, e il manifest locale
# (s88pro.xml) li porta giu' insieme al resto.
#
# prebuilt/kernel resta nel repo per chi vuole solo installare senza
# ricompilare: LineageOS lo userebbe solo con TARGET_FORCE_PREBUILT_KERNEL.
# Il fstab che usa il recovery. C'era, in rootdir/etc/, ma non era dichiarato,
# e senza questa riga il build non produce NESSUNA ROM installabile:
# build/make/core/Makefile spegne build_ota_package quando recovery_fstab e'
# vuoto, INTERNAL_OTA_PACKAGE_TARGET resta vuota, e il target "bacon" finisce
# per eseguire "ln -f" su un file che nessuno ha costruito:
#   ln: cannot create hard link from '.../lineage-20.0-...-s88pro.zip'
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.mt6771

# Quale file prendere da arch/arm64/boot/. Senza, il build copia la DIRECTORY:
#   cp "out/.../obj/KERNEL_OBJ/arch/arm64/boot/" "out/.../kernel"
#   cp: Skipped dir '...': No such file or directory
# Serviva solo con il kernel prebuilt, dove il file era gia' scelto.
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb

TARGET_KERNEL_SOURCE := kernel/doogee/s88pro
TARGET_KERNEL_CONFIG := lineage_s88pro_defconfig

# La versione di clang va fissata, non lasciata al default "clang-stable":
# in prebuilts/clang/host/linux-x86/clang-stable c'e' solo clang-format, e la
# build muore con "clang: command not found".
#
# LineageOS 20 porta clang-r450784d (14.0.6), e va bene: i due warning che su
# clang-17 costringevano a spegnerli -- deprecated-non-prototype e
# single-bit-bitfield-constant-conversion -- sono stati INTRODOTTI in clang-15
# e 16. clang-14 non li emette, quindi i rispettivi -Wno- non servono; e
# passarglieli lo farebbe fallire, perche' li segnala come opzione sconosciuta
# e il test di -fstack-protector-strong non passa.
TARGET_KERNEL_CLANG_VERSION := r450784d

# I warning che clang-14 ha e il clang-9 di fabbrica no. Il kernel compila con
# -Werror, e codice del 2019 diventa errore solo perche' il compilatore e' piu'
# recente. Si spengono i SINGOLI warning, non -Werror per intero: cosi' un
# difetto vero continua a fermare il build.
KERNEL_WARN_OFF := -Wno-unused-but-set-variable
KERNEL_WARN_OFF += -Wno-void-pointer-to-enum-cast
KERNEL_WARN_OFF += -Wno-strict-prototypes
KERNEL_WARN_OFF += -Wno-enum-conversion
KERNEL_WARN_OFF += -Wno-sometimes-uninitialized
KERNEL_WARN_OFF += -Wno-misleading-indentation
KERNEL_WARN_OFF += -Wno-bool-operation
KERNEL_WARN_OFF += -Wno-gnu-variable-sized-type-not-at-end
# -fuse-ld=lld (qui sotto, in KCFLAGS) serve al LINK del vdso, ma finisce
# anche nelle compilazioni normali, dove clang lo segnala come argomento
# inutilizzato -- e con -Werror sarebbe un errore.
KERNEL_WARN_OFF += -Wno-unused-command-line-argument

# LLVM_IAS=0: l'assembler integrato di clang non digerisce l'assembly di un
# kernel 4.14 (arch/arm64/mm/fault.c, "junk at end of line"); si usa quello di
# GNU binutils, che quel codice lo accetta.
#
# KCFLAGS=-gdwarf-4: con l'assembler di binutils 4.9 -- del 2014 -- le direttive
# DWARF 5 diventano "file number less than one". Chiedendo DWARF 4 il formato
# torna leggibile e CONFIG_DEBUG_INFO resta acceso come in fabbrica.
# HOSTCFLAGS=-fuse-ld=lld: il build di Android sanifica il PATH e non ci mette
# "ld" (in prebuilts/build-tools/path/linux-x86 non c'e'). Il kernel 4.14 linka
# i suoi strumenti host -- il primo e' scripts/basic/fixdep -- chiamando HOSTCC
# senza passare HOSTLDFLAGS, e clang cerca "ld":
#   clang-14: error: unable to execute command: Executable "ld" doesn't exist!
# Con -fuse-ld=lld usa il linker che sta accanto al compilatore.
TARGET_KERNEL_ADDITIONAL_FLAGS := LLVM_IAS=0 HOSTCFLAGS="-fuse-ld=lld" KCFLAGS="-gdwarf-4 -fuse-ld=lld $(KERNEL_WARN_OFF)"

# NIENTE "include vendor/lineage/config/BoardConfigLineage.mk" qui: lo fa gia'
# build/core/config.mk:361, e includerlo una seconda volta rompe l'esportazione
# a soong -- SOONG_CONFIG_NAMESPACES si ritrova lineageVarsPlugin due volte e
# l'elenco delle variabili esportate si ferma a meta'.
