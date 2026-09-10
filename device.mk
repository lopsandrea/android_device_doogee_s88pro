#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/doogee/s88pro

# Partizioni dinamiche: variabile di prodotto, non di board.
PRODUCT_USE_DYNAMIC_PARTITIONS := true


# fstab senza cifratura: nel ramdisk, con un suffisso tutto suo.
#
# Nel ramdisk serve perche' il first stage init lo cerca li': gira prima che il
# vendor sia montato, e senza si ferma subito --
#
#     init: Failed to create FirstStageMount failed to read default fstab for
#           first stage mount
#     init: Failed to mount required partitions early
#
# e il telefono ripiega in recovery dopo un minuto e mezzo. Misurato l'8
# settembre 2026, leggendo /sys/fs/pstore/console-ramoops dopo il tentativo.
#
# Qui c'era scritto il contrario -- "NON va copiato nel ramdisk: il boot non
# viene ricompilato" -- e allora era giusto: si usava boot_nocrypt.img, montato
# a mano in Fase 2, che il fstab nel ramdisk ce l'aveva gia'. Da quando il
# boot.img esce dal build quel presupposto e' caduto.
#
# ATTENZIONE, il boot.img costruito dal build NON contiene la patch Magisk che
# boot_nocrypt.img aveva (il suo ramdisk ha .backup/ e overlay.d/, e init pesa
# 199 KB invece di 2,9 MB): chi vuole il root deve ripatcharlo.
#
# Sulla cifratura la nota qui sopra diceva il contrario, e va corretta.
#
# Diceva di non reintrodurre "fileencryption" perche' il TEE (TrustKernel
# keymaster 4.0) rifiutava keystore2 con Error::Km(ErrorCode(-64)), cioe'
# KEYMASTER_NOT_CONFIGURED. Su questa configurazione non succede piu', e non
# e' una supposizione: con il sistema avviato, keystore_cli_v2 genera una
# chiave nel TEE, la usa e la verifica --
#
#     keystore_cli_v2 generate --name=prova --seclevel=tee   -> success
#     keystore_cli_v2 sign-verify --name=prova               -> Sign: 256 bytes
#                                                               Verify: OK
#
# e get-chars elenca OS_VERSION e OS_PATCHLEVEL fra i parametri "Hardware":
# il TEE i suoi dati di configurazione ce li ha. Da Keymaster 4.0 non e' piu'
# keystore a chiamare configure(), sono os_version e os_patch_level
# dell'header del boot.img che il bootloader passa al TEE, e il nostro
# boot.img li dichiara (13.0.0 e 2026-02).
#
# Anche il kernel e' pronto: CONFIG_FS_ENCRYPTION=y, ext4 con la feature
# "encryption", e la userdata ce l'ha gia' attiva.
#
# Percio' la riga /data e' di nuovo identica a quella di fabbrica, questa
# compresa. Passare da non cifrato a cifrato richiede di cancellare /data.
#
# E il fstab lo legge anche vold, che parte molto dopo il first stage.
#
# Finche' il build costruiva la vendor, questo file ci finiva dentro come
# /vendor/etc/fstab.mt6771 e copriva quello di fabbrica. Con
# BOARD_PREBUILT_VENDORIMAGE non ci finisce piu' -- il build non installa piu'
# niente in /vendor -- e a runtime torna a valere l'originale, che qui sbaglia
# in due punti: elenca /product come partizione logica, e /product nel super
# non c'e' piu'; e mette fileencryption su /data, che il TEE non regge.
#
# Il first stage non se ne accorge, perche' legge il nostro dal ramdisk e
# l'assenza di /product la tollera. vold no: itera su tutte le voci "logical"
# del fstab e su quella che manca chiama LOG(FATAL).
#
#     init:  DM_DEV_STATUS failed for product: No such device or address
#     vold:  could not find logical partition product: No such device or address
#     init:  Restarting system with command 'vold-failed'
#
# Letto in /sys/fs/pstore dopo il tentativo del 10 settembre 2026: il telefono
# restava fermo sul logo per due minuti e il watchdog lo spegneva.
#
# La via d'uscita e' il suffisso. fs_mgr costruisce il nome del file da
# ro.boot.fstab_suffix, e solo se quella manca ripiega su ro.hardware
# (system/core/fs_mgr/fs_mgr_fstab.cpp, GetFstabPath):
#
#     /odm/etc/fstab.<suffisso>  ->  /vendor/etc/fstab.<suffisso>  ->  /fstab.<suffisso>
#
# Con androidboot.fstab_suffix=s88pro nel cmdline, fstab.s88pro non esiste in
# /odm/etc ne' in /vendor/etc: niente lo copre, e vale il nostro.
#
# Ma va installato in due posti, perche' fra il first stage e vold la radice
# cambia. Montata la system, il first stage ci si trasferisce sopra
# (system/core/init/first_stage_mount.cpp:520, SwitchRoot("/system")) e il
# ramdisk sparisce: un fstab che stesse solo li' verrebbe letto dal first
# stage e non piu' da vold, che parte cinque secondi dopo. Percio' la copia
# nella radice della system, che dopo lo switch e' proprio "/".
#
# Radice della system vuol dire TARGET_COPY_OUT_ROOT, non
# TARGET_COPY_OUT_SYSTEM: questa e' una system-as-root, l'immagine contiene
# l'albero intero e la sottodirectory "system" dentro di se'. Sbagliando
# variabile il file finisce in /system/fstab.s88pro, dove fs_mgr non guarda.
#
# La copia col nome vecchio resta come rete di sicurezza. Se il bootloader non
# passasse androidboot.fstab_suffix, fs_mgr ripiegherebbe su "mt6771" e senza
# quella copia il first stage non troverebbe alcun fstab -- che non e' un
# bootloop qualunque, e' il telefono che ripiega in recovery.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6771:$(TARGET_COPY_OUT_RAMDISK)/fstab.s88pro \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6771:$(TARGET_COPY_OUT_RAMDISK)/fstab.mt6771 \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6771:$(TARGET_COPY_OUT_ROOT)/fstab.s88pro

# Le due fotocamere in piu' -- senza questa, la HAL non le cerca nemmeno.
#
# libcam.halsensor.so legge ro.odm_main2_camera e in base a quella decide fin
# dove spingere la ricerca: senza, si ferma all'indice 1 e in dmesg si legge
# "impSearchSensor search to 1"; con, arriva a 3 e prova tutti e quattro gli
# slot. Non e' una deduzione -- e' la sola proprieta' che quella libreria
# consulta con "cam" o "sensor" nel nome, e il comportamento cambia con lei.
#
# Sul kernel di fabbrica, con questa proprieta' impostata, la ricerca trova
# tutte e quattro: imx230, s5k3p3sx, gc8034 e gc0310.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.odm_main2_camera=1


# Il vendor e' Android 10: il framework deve parlare la sua VNDK.
#
# PRODUCT_TARGET_VNDK_VERSION dichiara quale VNDK usa il vendor, ma NON
# include le librerie: per quelle serve PRODUCT_EXTRA_VNDK_VERSIONS.
# Senza, /system/lib64/vndk-29 non esiste, i binari del vendor Android 10
# non trovano le loro dipendenze e il boot muore con
#   reboot: Restarting system with command 'boringssl-self-check-failed'
# Le GSI includono tutte le VNDK: e' la ragione per cui la GSI si avvia
# su questo device e il nostro system, senza questa riga, no.
PRODUCT_TARGET_VNDK_VERSION := 29
PRODUCT_EXTRA_VNDK_VERSIONS := 29
PRODUCT_SHIPPING_API_LEVEL := 29

# Overlay delle risorse del framework: dichiara il lettore di impronte.
# Vedi il commento dentro overlay/frameworks/base/core/res/res/values/config.xml
DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay

# Avvio del TEE: vedi il commento dentro il file.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/trustkernel-fixup.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/trustkernel-fixup.rc

# Mappa dei tasti, ripresa dalla ROM di fabbrica.
#
# Senza questo file si ricade su Generic.kl. I due tasti programmabili sulla
# scocca arrivano da qui: quello laterale come F5 (scancode 63) e l'altro come
# CAMERA (212); l'azione da associare si sceglie in S88ProParts.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/usr/keylayout/mtk-kpd.kl:$(TARGET_COPY_OUT_SYSTEM)/usr/keylayout/mtk-kpd.kl

# Gesti sul sensore di impronte.
#
# Il lettore Sunwave registra un secondo input device, sf-keys, che riporta
# scorrimenti e tocchi: verificato con getevent, il tocco arriva come F10
# (scancode 68) e i due scorrimenti trasversali come 105 e 106. Senza questo
# file ricadono su Generic.kl e gli scorrimenti spostano il fuoco nelle app.
#
# I gesti sono accesi da <navigation>true</navigation> in
# /vendor/etc/sw_config.xml, che sta nell'immagine di fabbrica: vedi
# hardware-riferimento.md per come si modifica a lunghezza costante.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/usr/keylayout/sf-keys.kl:$(TARGET_COPY_OUT_SYSTEM)/usr/keylayout/sf-keys.kl

# Impostazioni specifiche del device: LED della scocca, tasti, ricarica inversa.
PRODUCT_PACKAGES += \
    S88ProParts

# Radio FM.
#
# L'app di LineageOS e quella di fabbrica sono la stessa: la libreria nativa
# del vendor (libfmjni, fra i blob) registra i metodi proprio per
# com/android/fmradio/FmNative. Il driver e' gia' caricato all'avvio dal
# vendor, che insmod fmradio_drv.ko quando il chip di connettivita' e' pronto.
PRODUCT_PACKAGES += \
    FMRadio

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/s88pro-fm.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/s88pro-fm.rc

# L'allowlist delle permission privilegiate di S88ProParts: senza, il sistema
# non si avvia affatto. Vedi il commento dentro il file.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/parts/privapp-permissions-s88pro.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/privapp-permissions-s88pro.xml

# Boost EAS per le app in primo piano: senza, l'interfaccia va a scatti.
# Il frame mediano passa da 19 a 11 ms e i frame fuori tempo dal 28,4% allo
# 0,4%. Vedi il commento dentro il file .rc, che spiega anche perche' serve un
# servizio invece di due righe "write".
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/s88pro-schedtune.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/s88pro-schedtune.rc \
    $(LOCAL_PATH)/rootdir/etc/s88pro-schedtune.sh:$(TARGET_COPY_OUT_SYSTEM)/etc/s88pro-schedtune.sh

# La shell sulla console seriale, che AOSP avvia su ogni build userdebug, qui
# non deve partire. Vedi il commento dentro il file: la console del kernel
# resta, si spegne solo il prompt su UART.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/s88pro-console.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/s88pro-console.rc

# L'USB della recovery: senza, si vede sullo schermo ma non risponde ad adb.
# Il perche' sta nel commento dentro il file.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6771.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt6771.rc

# /cache e' un collegamento a /data/cache, quindi il file_contexts di AOSP non
# prende e il contenuto resta senza etichetta: in enforcing system_server non
# scrive piu' in /cache/recovery. Vedi il commento dentro il file.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/s88pro-cache.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/s88pro-cache.rc


# Proprieta' di sistema del device
PRODUCT_SYSTEM_PROPERTIES += \
    ro.hardware=mt6771

# Compressione AFBC della GPU: va spenta.
#
# La Mali G72 comprime in AFBC i framebuffer che compone, e il gralloc lo fa in
# modo trasparente per chi quei buffer li legge con la GPU. L'encoder video
# MediaTek pero' non passa dalla GPU: prende l'ion fd dal gralloc e lo da' in
# pasto a MDP come se fosse raster lineare. Su un buffer compresso ne esce
# rumore a bande, ed e' esattamente l'immagine che si vedeva in registrazione
# schermo, Miracast e scrcpy.
#
# Il gralloc saprebbe evitarlo da se' -- ha il ramo "AFBC selected but not
# supported by producer/consumer. Disabling" -- ma con i buffer del display
# virtuale non scatta. Questa proprieta' spegne AFBC per tutte le allocazioni:
# e' la via piu' larga ma anche l'unica che non richieda di toccare il gralloc,
# che e' un blob. Il prezzo e' un po' di banda di memoria in piu' per la
# composizione; il guadagno e' la codifica dello schermo in hardware.
#
# La ricostruzione completa e' in docs/bringup/hardware-riferimento.md.
PRODUCT_SYSTEM_PROPERTIES += \
    debug.gpu.afbc.disable=1


# VoLTE: ImsService di MediaTek.
#
# LAVORO INCOMPLETO. Lo stack si lega al framework e la feature MMTEL arriva a
# READY, ma le capability restano vuote e la registrazione sulla rete non
# avviene ancora. Il VoWiFi e' escluso per scelta: dipende da un metodo che
# MediaTek ha aggiunto a WifiManager e che AOSP non ha.
# Stato, ricostruzione e come riprendere: docs/bringup/volte-stato-esperimento.md
#
# L'APK non e' in albero: si prepara una volta con ims/prepare-imsservice.sh a
# partire da quello della ROM di fabbrica. Se manca, la build prosegue senza
# VoLTE e queste due righe non fanno danno: dichiarano librerie e permessi per
# un pacchetto che non c'e', cosa che il PackageManager ignora.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/ims/mediatek-ims-libs.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/mediatek-ims-libs.xml \
    $(LOCAL_PATH)/ims/privapp-permissions-mtk-ims.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/privapp-permissions-mtk-ims.xml

# Il modulo esiste solo se l'APK e' stato preparato: nominarlo comunque farebbe
# fallire la build con "module ImsService not found".
ifneq ($(wildcard $(LOCAL_PATH)/ims/ImsService.apk),)
PRODUCT_PACKAGES += \
    ImsService
endif

# libhidltransport e libhwbinder: le pretende libmtk_vt_wrapper.so, che
# ImsService carica per il provider di videochiamata. Sono deprecate (confluite
# in libhidlbase con Android 11) ma Android 12 le costruisce ancora, quindi si
# prendono da qui invece che dai blob: copiarle dallo stock le definirebbe due
# volte e la build si ferma con "overriding commands for target".
PRODUCT_PACKAGES += \
    libhidltransport \
    libhwbinder

# Il modem tiene VoLTE spento finche' non glielo si dice.
PRODUCT_SYSTEM_PROPERTIES += \
    persist.vendor.mtk.volte.enable=1

# Bluetooth: quali profili esistono.
#
# Da Android 13 l'elenco dei profili non e' piu' compilato dentro lo stack: lo
# decidono queste proprieta', e chi non le dichiara non ne ha nessuno. Il
# sintomo non e' un Bluetooth spento -- l'adapter si accende, ha il suo
# indirizzo, la scansione trova i dispositivi -- ma nessuno di quei dispositivi
# si collega. Nel log:
#
#   BluetoothManagerService: Cannot bind profile: 1, not in supported profiles list
#   CachedBluetoothDevice: No profiles. Maybe we will connect later for device ...
#
# e nel dumpsys ogni politica di connessione a -1. Con le proprieta' al loro
# posto compaiono A2dpService, AvrcpTargetService, HeadsetService, e le
# politiche passano a 100.
#
# LE Audio resta fuori di proposito: il combo e' un MT6631, che non ce l'ha.
# Il profilo 22 continuera' a non agganciarsi, ed e' giusto cosi'.
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

# Blob proprietari estratti dalle immagini stock (Task 4).
# La riga viene abilitata quando vendor/doogee/s88pro esiste: prima di allora
# la build fallirebbe cercando un makefile inesistente.
$(call inherit-product-if-exists, vendor/doogee/s88pro/s88pro-vendor.mk)


# Nemmeno drm@1.2-service.clearkey: e' la DRM di prova per il CTS, e il suo
# frammento dichiara android.hardware.drm 1.2/clearkey mentre il manifest del
# device dichiara la 1.0/default di fabbrica. Due versioni della stessa HAL, e
# assemble_vintf si ferma. La drm@1.0-service, quella vera, resta.
#
# cas no: il vendor di fabbrica aveva android.hardware.cas@1.1-service, ma
# qui la HAL la costruisce AOSP nella versione 1.2, che e' gia' installata e
# porta il proprio frammento VINTF. Chiedendo anche la 1.1 si installano due
# moduli per la stessa HAL, e assemble_vintf si ferma:
#   HAL "android.hardware.cas" has a conflict: Conflicting major version:
#     1.2 (from .../cas@1.2-service.xml) vs. 1.1 (from .../cas@1.1-service.xml)



# libtinycompress no, e vale la pena sapere perche'.
#
# Il vendor di fabbrica la porta in lib e lib64; qui la variante a 32 bit non
# compila:
#   generated_kernel_includes/gen/usr/include/asm/sigcontext.h:74:2:
#     error: unknown type name '__uint128_t'
# Gli header UAPI vengono generati con ARCH=arm64 e finiscono anche nella
# compilazione a 32 bit, dove quel tipo non esiste. Non e' un difetto del
# nostro kernel: e' che gli stessi header servono due architetture.
#
# Serve all'audio compresso (offload playback). Se un giorno mancasse davvero,
# la via e' generare gli header UAPI anche per ARCH=arm, non forzare questa.

# Nota sulle librerie con il suffisso .vendor: in soong un modulo
# "vendor_available" produce due varianti, e PRODUCT_PACKAGES senza suffisso
# installa quella di sistema. Dichiarate senza, finivano in /system/lib64 e la
# vendor restava senza -- si vede solo confrontando le due immagini, il build
# non dice niente.

# Le proprieta' che stavano in /vendor/default.prop di fabbrica.
#
# Il file non si copia: dichiara ro.vndk.version=29, cioe' la VNDK di
# Android 10, mentre il build genera 33. Init legge prima l'uno e poi
# l'altro, il linker si ritrova due versioni, e il primo a farne le spese e'
# il self test di BoringSSL -- che non fallisce con un messaggio ma riavvia
# il telefono:
#   reboot: Restarting system with command 'boringssl-self-check-failed'
# Due giri di bootloop prima di trovarlo, perche' nessuno dice che c'entra
# una riga in un file di proprieta'.
#
# Qui restano solo quelle che il build non genera da se' e che servono
# davvero: ro.zygote, ro.bionic.* e ro.vndk.version le fa lui, giustamente.
# ro.apex.updatable: senza, il telefono non si avvia.
#
# BoardConfig imposta TARGET_FLATTEN_APEX := false, quindi gli APEX sono 26
# file .apex che apexd deve montare. Ma apexd li monta solo se glielo si dice
# con questa proprieta', che sta in build/make/target/product/updatable_apex.mk
# insieme al flag:
#
#   PRODUCT_VENDOR_PROPERTIES := ro.apex.updatable=true
#   TARGET_FLATTEN_APEX := false
#
# Il device tree aveva preso solo la seconda riga. La prima e' una proprieta'
# del VENDOR, e finora arrivava dal vendor di fabbrica -- che ce l'ha -- senza
# che nessuno se ne accorgesse. Dal momento in cui installiamo la nostra
# vendor, sparisce, e la catena e' questa:
#
#   apexd: ActivateFlattenedApex        (cerca directory, trova file: 0 attivati)
#   linkerconfig: Unable to access VNDK APEX at path: /apex/com.android.vndk.v33
#   linkerconfig: terminated by exit(255)
#   reboot: Restarting system with command 'boringssl-self-check-failed'
#
# L'ultimo messaggio e' fuorviante -- non c'entra la crittografia: senza
# namespace configurati il self test non trova libcrypto, e quel servizio,
# quando fallisce, riavvia il telefono invece di lamentarsi. Lo stesso
# inganno e' gia' descritto nel commento di TARGET_FLATTEN_APEX in
# BoardConfig.mk: la seconda meta' della stessa storia.
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

# Niente HAL o librerie da chiedere per il vendor: e' un'immagine prebuilt,
# vedi BOARD_PREBUILT_VENDORIMAGE nel BoardConfig. Tutto quello che le serve
# ce l'ha gia' dentro.
