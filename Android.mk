#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),s88pro)
include $(call all-subdir-makefiles,$(LOCAL_PATH))
endif

# La vendor di fabbrica, meno una riga: il fstab.
#
# Il vendor arriva come immagine gia' pronta (BOARD_PREBUILT_VENDORIMAGE), e
# il build non ci installa piu' niente dentro. Va bene per tutto tranne che
# per un file: /vendor/etc/fstab.mt6771. Quello di fabbrica descrive il
# telefono com'era con Android 10 e qui sbaglia in due punti -- elenca
# /product, che dal super e' stata tolta, e chiede fileencryption su /data,
# che il TEE MediaTek (TrustKernel keymaster v4) non concede.
#
# E non basta metterne una copia altrove sperando che vinca: i file init del
# vendor lo montano per nome, senza passare dal suffisso di fs_mgr --
#
#     init.mt6771.rc:107   mount_all /vendor/etc/fstab.mt6771
#     factory_init.rc:297  mount_all /vendor/etc/fstab.mt6771 ...
#     meta_init.rc:295     mount_all /vendor/etc/fstab.mt6771 ...
#
# Quel percorso e' l'unico che conta, quindi il nostro fstab deve stare li'.
# Con l'immagine prebuilt l'unico modo e' scriverlo dentro, e debugfs lo fa
# senza smontare niente e senza ricostruire l'immagine: stesso inode, stessa
# dimensione complessiva, tutto il resto intatto. Permessi e contesto sono
# quelli che aveva il file di fabbrica (0644 root:root vendor_configs_file):
# se sbagliassero, init non riuscirebbe a leggerlo e il telefono si
# fermerebbe prima di /data.
S88PRO_VENDOR_FABBRICA := vendor/doogee/s88pro/vendor.img
# Percorso esplicito, non $(LOCAL_PATH): qui sopra c'e' all-subdir-makefiles,
# che lascia LOCAL_PATH puntato all'ultima sottodirectory inclusa (ims).
S88PRO_VENDOR_FSTAB := device/doogee/s88pro/rootdir/etc/fstab.mt6771
S88PRO_VENDOR_CTX := u:object_r:vendor_configs_file:s0

$(S88PRO_VENDOR_CON_FSTAB): $(S88PRO_VENDOR_FABBRICA) $(S88PRO_VENDOR_FSTAB) \
        $(HOST_OUT_EXECUTABLES)/debugfs
	@echo "vendor: il nostro fstab al posto di quello di fabbrica"
	$(hide) mkdir -p $(dir $@)
	$(hide) cp -f $(S88PRO_VENDOR_FABBRICA) $@
	$(hide) printf '$(S88PRO_VENDOR_CTX)\0' > $@.ctx
	$(hide) ( \
	    echo "cd /etc"; \
	    echo "rm fstab.mt6771"; \
	    echo "write $(S88PRO_VENDOR_FSTAB) fstab.mt6771"; \
	    echo "sif fstab.mt6771 mode 0100644"; \
	    echo "sif fstab.mt6771 uid 0"; \
	    echo "sif fstab.mt6771 gid 0"; \
	    echo "ea_set -f $@.ctx fstab.mt6771 security.selinux"; \
	  ) > $@.cmds
	$(hide) $(HOST_OUT_EXECUTABLES)/debugfs -w -f $@.cmds $@ > /dev/null 2>&1
	$(hide) rm -f $@.ctx $@.cmds
