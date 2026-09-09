#!/usr/bin/env bash
# Genera i makefile di vendor/doogee/s88pro a partire da proprietary-files.txt.
#
# LA DESTINAZIONE VIENE DAL PERCORSO. Prima questo script mandava tutto in
# $(TARGET_COPY_OUT_SYSTEM), perche' l'elenco conteneva solo i .jar del
# framework MediaTek. Da quando ci sono anche i 1622 file della partizione
# vendor, il prefisso decide dove va il file: "vendor/..." in
# TARGET_COPY_OUT_VENDOR, "system/..." in TARGET_COPY_OUT_SYSTEM, e cosi' via.
# Sbagliarlo non da' errore: i file finiscono nella partizione sbagliata e il
# telefono non parte, che e' peggio.
#
# PERCHE' ORA ANCHE I .so PASSANO DA PRODUCT_COPY_FILES. Prima ogni libreria
# diventava un modulo BUILD_PREBUILT, perche' il build rifiuta gli ELF in
# PRODUCT_COPY_FILES con
#   FAILED: ...check-non-elf-file-timestamps.../lib64/libXXX.so.timestamp
# Con 947 librerie quella strada non regge: 586 hanno un basename unico, le
# altre 361 collidono (la stessa libreria in lib e lib64, oppure in hw/ e nella
# radice), e due moduli con lo stesso LOCAL_MODULE si sovrascrivono a vicenda.
# AOSP prevede l'interruttore apposta -- BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES,
# in build/make/core/board_config.mk -- ed e' attivo nel BoardConfig.
#
# Restano moduli solo gli APK, che PRODUCT_COPY_FILES rifiuta comunque:
#   error: Prebuilt apk found in PRODUCT_COPY_FILES: ... use BUILD_PREBUILT instead!
#
# I collegamenti simbolici non si esprimono in un elenco di file: stanno in
# fondo a questo script, scritti a mano, e diventano un modulo che li crea
# dopo l'installazione.
set -euo pipefail

DEVICE=s88pro
VENDOR=doogee
HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/proprietary-files.txt"
OUT="$HERE/../../../vendor/$VENDOR/$DEVICE"

mkdir -p "$OUT"

# Cerca un percorso di DESTINAZIONE nell'elenco. Non si puo' usare grep -x:
# una riga puo' essere "system/lib64/x.so" oppure
# "product/lib64/x.so:system/lib64/x.so", e la seconda forma non
# corrisponderebbe mai.
elencata() {                       # $1 = percorso di destinazione
	awk -v p="$1" '
		/^[[:space:]]*(#|$)/ { next }
		{ sub(/^-/, ""); if (index($0, ":")) sub(/^[^:]*:/, "");
		  if ($0 == p) { trovato = 1; exit } }
		END { exit !trovato }' "$LIST"
}

# La partizione di destinazione, dedotta dal prefisso del percorso.
destinazione() {                 # $1 = percorso come compare nell'elenco
	case "$1" in
		vendor/*)  echo "\$(TARGET_COPY_OUT_VENDOR)/${1#vendor/}" ;;
		system/*)  echo "\$(TARGET_COPY_OUT_SYSTEM)/${1#system/}" ;;
		product/*) echo "\$(TARGET_COPY_OUT_PRODUCT)/${1#product/}" ;;
		odm/*)     echo "\$(TARGET_COPY_OUT_ODM)/${1#odm/}" ;;
		*)         echo "\$(TARGET_COPY_OUT_SYSTEM)/$1" ;;
	esac
}

# --- Android.mk: gli APK e i collegamenti ---
{
	cat << 'HEADER'
# Generato da device/doogee/s88pro/setup-makefiles.sh — non modificare a mano.

LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),s88pro)

HEADER

	while read -r line; do
		case "$line" in ''|'#'*) continue ;; esac
		f="${line#-}"
		case "$f" in *:*) f="${f#*:}" ;; esac
		case "$f" in
			system/*.so)
				# Le librerie che finiscono in system restano moduli: altri moduli
				# dipendono da loro per nome, e con la sola copia il build si ferma con
				#   TARGET module FMRadio requires non-existent TARGET module: libfmjni:64
				# Sono otto; le 947 del vendor passano da PRODUCT_COPY_FILES.
				name="$(basename "$f" .so)"
				case "$f" in *lib64*) bits=64 ;; *) bits=32 ;; esac
				altra="$(echo "$f" | sed 's#/lib64/#/lib/#')"
				if [ "$bits" = "32" ] && elencata "$(echo "$f" | sed 's#/lib/#/lib64/#')"; then
					continue
				fi
				if [ "$bits" = "64" ] && elencata "$altra"; then
					cat << MODULE
include \$(CLEAR_VARS)
LOCAL_MODULE := $name
LOCAL_MODULE_OWNER := $VENDOR
LOCAL_SRC_FILES_64 := proprietary/$f
LOCAL_SRC_FILES_32 := proprietary/$altra
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_SUFFIX := .so
LOCAL_MULTILIB := both
LOCAL_MODULE_TAGS := optional
LOCAL_STRIP_MODULE := false
LOCAL_CHECK_ELF_FILES := false
include \$(BUILD_PREBUILT)

MODULE
					continue
				fi
				cat << MODULE
include \$(CLEAR_VARS)
LOCAL_MODULE := $name
LOCAL_MODULE_OWNER := $VENDOR
LOCAL_SRC_FILES := proprietary/$f
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_SUFFIX := .so
LOCAL_MULTILIB := $bits
LOCAL_MODULE_TAGS := optional
LOCAL_STRIP_MODULE := false
LOCAL_CHECK_ELF_FILES := false
include \$(BUILD_PREBUILT)

MODULE
				;;
			*.apk)
				name="$(basename "$f" .apk)"
				proprietario=""
				case "$f" in vendor/*) proprietario="LOCAL_PROPRIETARY_MODULE := true" ;; esac
				# Privilegiata o no lo dice il percorso: priv-app oppure app. Con
				# LOCAL_PRIVILEGED_MODULE l'apk finisce in priv-app comunque, e
				# SensorHub -- che di fabbrica sta in vendor/app -- spariva da li'
				# senza un errore.
				privilegiato=""
				case "$f" in */priv-app/*) privilegiato="LOCAL_PRIVILEGED_MODULE := true" ;; esac
				# Gli overlay RRO non vanno firmati con la chiave di piattaforma
				# ne' resi privilegiati: sono risorse, non applicazioni.
				case "$f" in
					*overlay*)
						cat << MODULE
include \$(CLEAR_VARS)
LOCAL_MODULE := $name
LOCAL_MODULE_OWNER := $VENDOR
LOCAL_SRC_FILES := proprietary/$f
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := .apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_MODULE_TAGS := optional
LOCAL_DEX_PREOPT := false
$proprietario
LOCAL_MODULE_PATH := \$(TARGET_OUT_VENDOR)/overlay
include \$(BUILD_PREBUILT)

MODULE
						;;
					*)
						cat << MODULE
include \$(CLEAR_VARS)
LOCAL_MODULE := $name
LOCAL_MODULE_OWNER := $VENDOR
LOCAL_SRC_FILES := proprietary/$f
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := .apk
LOCAL_CERTIFICATE := PRESIGNED
$privilegiato
LOCAL_MODULE_TAGS := optional
LOCAL_DEX_PREOPT := false
$proprietario
include \$(BUILD_PREBUILT)

MODULE
						;;
				esac
				;;
		esac
	done < "$LIST"

	# I collegamenti simbolici del vendor di fabbrica. Un elenco di file non li
	# esprime, e copiarne il contenuto due volte sprecherebbe spazio: vulkan
	# punta a libGLES_mali.so, che da sola pesa piu' di venti megabyte.
	cat << 'LINKS'
# I collegamenti simbolici del vendor di fabbrica.
#
# Un elenco di file non li esprime, e copiare due volte il contenuto sarebbe
# uno spreco: vulkan punta a libGLES_mali.so, che da sola pesa piu' di venti
# megabyte. Non si puo' nemmeno usare BUILD_PHONY_PACKAGE, che con
# LOCAL_PROPRIETARY_MODULE si ferma con
#   error: unhandled install path "TARGET_OUT_VENDOR_FAKE"
# perche' un pacchetto finto non ha un posto dove installarsi. Restano le
# regole diritte, che e' poi come fanno gli altri device tree.

S88PRO_SYMLINKS :=

define s88pro-collegamento
S88PRO_SYMLINKS += $(2)
$(2):
	@mkdir -p $$(dir $$@)
	$$(hide) ln -sf $(1) $$@
endef

$(eval $(call s88pro-collegamento,libSoftGatekeeper.so,$(TARGET_OUT_VENDOR)/lib/hw/gatekeeper.default.so))
$(eval $(call s88pro-collegamento,libSoftGatekeeper.so,$(TARGET_OUT_VENDOR)/lib64/hw/gatekeeper.default.so))
$(eval $(call s88pro-collegamento,gatekeeper.trustkernel.so,$(TARGET_OUT_VENDOR)/lib/hw/gatekeeper.mt6771.so))
$(eval $(call s88pro-collegamento,gatekeeper.trustkernel.so,$(TARGET_OUT_VENDOR)/lib64/hw/gatekeeper.mt6771.so))
$(eval $(call s88pro-collegamento,gatekeeper.trustkernel.so,$(TARGET_OUT_VENDOR)/lib/hw/gatekeeper.e977_dg_m13_71_q0.so))
$(eval $(call s88pro-collegamento,gatekeeper.trustkernel.so,$(TARGET_OUT_VENDOR)/lib64/hw/gatekeeper.e977_dg_m13_71_q0.so))
$(eval $(call s88pro-collegamento,kmsetkey.trustkernel.so,$(TARGET_OUT_VENDOR)/lib/hw/kmsetkey.mt6771.so))
$(eval $(call s88pro-collegamento,kmsetkey.trustkernel.so,$(TARGET_OUT_VENDOR)/lib64/hw/kmsetkey.mt6771.so))
$(eval $(call s88pro-collegamento,/vendor/lib/egl/libGLES_mali.so,$(TARGET_OUT_VENDOR)/lib/hw/vulkan.mt6771.so))
$(eval $(call s88pro-collegamento,/vendor/lib64/egl/libGLES_mali.so,$(TARGET_OUT_VENDOR)/lib64/hw/vulkan.mt6771.so))
$(eval $(call s88pro-collegamento,/vendor/lib64/libem_sensor_jni.so,$(TARGET_OUT_VENDOR)/app/SensorHub/lib/arm64/libem_sensor_jni.so))
# Nota: /vendor/bin/bc esiste anche di fabbrica come collegamento a
# toybox_vendor, ma non va rifatto qui -- lo crea gia' AOSP, e ridefinirlo da'
#   error: overriding commands for target .../vendor/bin/bc

ALL_DEFAULT_INSTALLED_MODULES += $(S88PRO_SYMLINKS)

endif
LINKS
} > "$OUT/Android.mk"

# --- s88pro-vendor.mk: la copia di tutto il resto ---
{
	cat << 'HEADER'
# Generato da device/doogee/s88pro/setup-makefiles.sh — non modificare a mano.
#
# I blob di fabbrica: i .jar del framework MediaTek che vanno in system, e i
# 1622 file della partizione vendor -- HAL, librerie, firmware, configurazione
# e la policy SELinux del vendor, senza la quale i suoi servizi restano muti.

PRODUCT_COPY_FILES += \
HEADER

	while read -r line; do
		case "$line" in ''|'#'*) continue ;; esac
		f="${line#-}"
		case "$f" in *:*) f="${f#*:}" ;; esac
		case "$f" in
			# I frammenti VINTF non si copiano: il build li rifiuta con
			#   error: VINTF metadata found in PRODUCT_COPY_FILES: ...
			#   use DEVICE_MANIFEST_FILE / vintf_fragments instead!
			# Stanno in DEVICE_MANIFEST_FILE, nel BoardConfig.
			# I file VINTF non si copiano, il build li rifiuta:
			#   error: VINTF metadata found in PRODUCT_COPY_FILES: ...
			#   use DEVICE_MANIFEST_FILE / ODM_MANIFEST_FILES / vintf_fragments instead!
			# I due frammenti di vendor/etc/vintf/manifest (cas e gpu) stanno in
			# DEVICE_MANIFEST_FILE, nel BoardConfig. Gli otto di vendor/odm/etc/vintf
			# invece si lasciano fuori: sono le varianti per le diverse
			# configurazioni di SIM (ss, dsds, tsts, qsqs, con e senza SE), il
			# telefono usa tsts, e quello che tsts dichiara -- android.hardware.radio
			# e vendor.mediatek.hardware.mtkradioex -- il nostro manifest.xml lo ha
			# gia', perche' e' stato preso dal telefono a manifest gia' assemblato.
			*.apk|system/*.so|*/etc/vintf/*) continue ;;
			*) echo "    vendor/$VENDOR/$DEVICE/proprietary/$f:$(destinazione "$f") \\" ;;
		esac
	done < "$LIST"

	echo ""
	echo ""
	echo "PRODUCT_PACKAGES += \\"
	{
		while read -r line; do
			case "$line" in ''|'#'*) continue ;; esac
			f="${line#-}"
			case "$f" in *:*) f="${f#*:}" ;; esac
			case "$f" in
				*.apk)       basename "$f" .apk ;;
				system/*.so) basename "$f" .so ;;
			esac
		done < "$LIST"
	} | sort -u | sed 's/^/    /; s/$/ \\/'
	echo ""
} > "$OUT/$DEVICE-vendor.mk"

echo "generati:"
echo "  $OUT/Android.mk"
echo "  $OUT/$DEVICE-vendor.mk"
