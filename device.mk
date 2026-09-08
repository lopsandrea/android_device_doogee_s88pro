#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/doogee/s88pro

# Partizioni dinamiche: variabile di prodotto, non di board.
# Serve a far uscire la ROM installabile SENZA costruire il recovery.
#
# Il BoardConfig dichiara TARGET_NO_RECOVERY := true, e con una ragione: si usa
# la TWRP di lopestom, l'unica che espone fastbootd, e costruire il recovery qui
# fallisce comunque su mkbootimg ("DTB image must not be empty").
#
# Ma build/make/core/Makefile lega le due cose: senza recovery non calcola
# recovery_fstab, quindi spegne build_ota_package, quindi
# INTERNAL_OTA_PACKAGE_TARGET resta vuota e il target "bacon" non produce
# nulla -- falliva su "ln -f" di uno zip che nessuno aveva costruito.
#
# Questa riga salta quel blocco di condizioni e fa generare il pacchetto lo
# stesso. Il giorno in cui si costruira' il recovery di LineageOS -- che il
# charter chiede -- si puo' togliere.
# (la riga vera sta in lineage_s88pro.mk: da qui non veniva raccolta)

PRODUCT_USE_DYNAMIC_PARTITIONS := true

# fstab senza cifratura, nel solo vendor.
#
# NON va copiato nel ramdisk: il boot non viene ricompilato. Si continua a
# usare boot_nocrypt.img prodotto in Fase 2, che ha gia' il fstab corretto nel
# ramdisk e conserva la patch Magisk.
#
# E soprattutto: NON reintrodurre "fileencryption" in questo fstab. Il TEE
# MediaTek (TrustKernel keymaster v4) rifiuta keystore2 con
# Error::Km(ErrorCode(-64)), vold non riesce a creare la chiave e il sistema
# non completa l'avvio. Vedi docs/bringup/fase2-risultato-gsi-funzionante.md
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6771:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.mt6771

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
