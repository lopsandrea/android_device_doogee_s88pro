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

# The stock vendor image, minus one line: the fstab.
#
# Vendor arrives as a ready-made image (BOARD_PREBUILT_VENDORIMAGE), and the
# build no longer installs anything inside it. That is fine for everything but
# one file: /vendor/etc/fstab.mt6771. The stock one describes the phone as it
# was under Android 10 and is wrong here in two places -- it lists /product,
# which has been removed from super, and it asks for fileencryption on /data,
# which the MediaTek TEE (TrustKernel keymaster v4) does not grant.
#
# And putting a copy elsewhere in the hope that it wins is not enough: the
# vendor init files mount it by name, bypassing the fs_mgr suffix --
#
#     init.mt6771.rc:107   mount_all /vendor/etc/fstab.mt6771
#     factory_init.rc:297  mount_all /vendor/etc/fstab.mt6771 ...
#     meta_init.rc:295     mount_all /vendor/etc/fstab.mt6771 ...
#
# That path is the only one that counts, so our fstab has to live there. With a
# prebuilt image the only way is to write it inside, and debugfs does that
# without unmounting anything and without rebuilding the image: same inode,
# same overall size, everything else untouched. Permissions and context are the
# ones the stock file had (0644 root:root vendor_configs_file): were they
# wrong, init could not read it and the phone would stop before /data.
S88PRO_VENDOR_STOCK := vendor/doogee/s88pro/vendor.img
# Explicit path, not $(LOCAL_PATH): above there is all-subdir-makefiles, which
# leaves LOCAL_PATH pointing at the last subdirectory included (ims).
S88PRO_VENDOR_FSTAB := device/doogee/s88pro/rootdir/etc/fstab.mt6771
S88PRO_VENDOR_CTX := u:object_r:vendor_configs_file:s0

$(S88PRO_VENDOR_WITH_FSTAB): $(S88PRO_VENDOR_STOCK) $(S88PRO_VENDOR_FSTAB) \
        $(HOST_OUT_EXECUTABLES)/debugfs
	@echo "vendor: our fstab in place of the stock one"
	$(hide) mkdir -p $(dir $@)
	$(hide) cp -f $(S88PRO_VENDOR_STOCK) $@
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
