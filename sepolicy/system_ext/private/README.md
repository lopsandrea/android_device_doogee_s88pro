# SELinux rules between system types

There is only `file_contexts` here.

## Why there are no `allow` rules

Two rules used to be here, for two denials measured on the phone:

    allow system_app sysfs_leds:dir search;          # S88ProParts' LEDs
    allow nfc system_data_file:file { ... };         # the NFC state

**They do not compile**: they violate AOSP `neverallow` rules, and the build
stops at `checkpolicy`:

    neverallow check failed ... from system/sepolicy/private/coredomain.te:32
      (neverallow base_typeattr_636 sysfs_leds (file (... write ...)))
        allow (allow system_app sysfs_leds (file (... write ...)))

    neverallow check failed ... from system/sepolicy/public/domain.te:1123
      (neverallow base_typeattr_293 system_data_file (file (write create ...)))
        allow (allow nfc system_data_file (file (read write getattr open)))

These prohibitions are deliberate: a `coredomain` must not touch `sysfs_leds`
on its own, and nobody may write to `system_data_file`, which is the generic
type.

## How they are actually closed

- **NFC**: the correct way is to label `/data/nfc` as `nfc_data_file`, which is
  exactly what the `file_contexts` next door does. Files already created with
  the old type are relabelled with `restorecon -R /data/nfc`.

- **LEDs**: `S88ProParts` should not write directly into `/sys/class/leds`, but
  go through the lights HAL. Alternatively one declares a device-specific type
  for those files and grants access to that -- but that has to be done in the
  vendor sepolicy, not among the system types.

Until one of the two is done, the denials stay in the log. Neither of them
prevents boot.

## The map of denials in enforcing mode (9 September)

Measured on the phone with SELinux Enforcing, after one boot and a real round
of use (photos, video, torch, LEDs, Bluetooth, NFC, FM radio, settings):
194 lines, 41 distinct combinations. Split by **who can close them**, which is
not an academic distinction: three quarters are not up to us.

### Closed in the kernel, not here

`network_stack -> fs_bpf : file read`, fourteen occurrences, had been filed
under "forbidden by a neverallow" -- `bpfloader.te:36` forbids exactly
`network_stack` from reading `fs_bpf`. The prohibition was right, though, and
the defect was elsewhere: those maps **should not have had that type**. The
maps were already in the right place (`/sys/fs/bpf/tethering/`), but the kernel
gave everything under bpffs the root's type, ignoring the per-path `genfscon`
entries the policy has always had:

    policy   genfscon bpf /tethering u:object_r:fs_bpf_tethering:s0
    device   /sys/fs/bpf/tethering -> u:object_r:fs_bpf:s0

One line is missing in `security/selinux/hooks.c`, and it has been upstream
since 2020: 4ca54d3d3022, *"security: selinux: allow per-file labeling for
bpffs"*. With it the six subdirectories get the type they deserve, the fourteen
denials disappear and tethering offload works. It lives in the kernel repo.

**The lesson**: a denial forbidden by a `neverallow` does not mean "leave it
open". It means AOSP expects a different configuration, and it is worth asking
which one before giving up.

### Closed here

| denial | how |
|---|---|
| `init -> socket_device : sock_file create` | `init.te`. These are the `volte_imsa2`, `volte_ut` and `vendor.bip` sockets, declared in the vendor `.rc` files without an explicit context |
| `system_server -> unlabeled : dir write` | `restorecon_recursive` in `s88pro-cache.rc`. It is `/cache/recovery`, that is the update path. AOSP already has the labels (`private/file_contexts:794`, which maps `/data/cache` because `/cache` is a symlink here): all that was missing was applying them to what was already there |
| `system_app -> sysfs_leds : dir search` | `system_app.te`. The LED nodes are not sysfs_leds but types of their own, already granted by the MediaTek policy: all that was missing was traversing the directory, and the neverallow in `coredomain.te:32` is on `:file` |
| `system_app -> sysfs_batteryinfo : dir r_dir_perms` | `system_app.te`. It only serves to tell whether the device has reverse charging; the state is read elsewhere, see below |
| `system_app -> sysfs_rvs : file rw` | `file.te` and `genfs_contexts`. The reverse charging node had the generic `sysfs` type, which nobody may write -- not even init, and AOSP explains why: *"Init should not access sysfs node that are not explicitly labeled"*. Once labelled, the problem is gone |

### Forbidden by an AOSP neverallow

This is not a limitation of ours: AOSP explicitly declares that those domains
must not have that access, and `secilc` rejects the rule. Be careful to read
*what* is forbidden, though: prohibitions on sysfs are nearly always on the
`file` class and not on `dir`, and that distinction was enough to recover the
LEDs.

| denial | occurrences | the prohibition |
|---|---|---|
| `kernel -> capability dac_override` | 6 | the `mtk_wmtd_worker` worker of the MediaTek Wi-Fi driver |

### Not expressible: the type is defined by the vendor

With `TARGET_USES_PREBUILT_VENDOR_SEPOLICY` the vendor policy arrives already
compiled, and its types do not exist in the platform policy: an `allow` naming
them does not compile. The domain, on the other hand, is ours, so they cannot
be put elsewhere either.

| denial | occurrences |
|---|---|
| `vold -> sysfs_mmcblk : file write` | 49 |
| `mediaswcodec -> proc_ged : file read` | 28 |
| `cameraserver -> vendor_default_prop : file read` | 6 |
| `mediacodec -> default_prop : file read` | 5 |
| `mediaserver`, `nfc` -> `debugfs_ion : dir search` | 6 |
| `system_server -> tkcore_systa_file : dir getattr` | 1 |

### The vendor's, domain included

`ccci_mdinit` (8), `stflashtool` (6), `rild` (6), `mtk_hal_camera` (6),
`aee_aedv` (4), `nvram_daemon` (4), `mnld` (4), `fuelgauged_nvram` (3),
`mtk_hal_audio` (3), `mtk_hal_wifi` (2), `mtk_hal_sensors` (2),
`mtk_hal_bluetooth` (1). Nothing is touched here: the rules would belong in the
MediaTek blob.

**None of these blocks a measured function.** The `tools/prova-driver.sh` test
battery, run with `setenforce 0` and `setenforce 1` on the same boot, shows not
a single functional difference.

## Why the vendor denials are not closed, and how that was verified

The rules would apply to domains or types defined by the MediaTek policy.
Before leaving them open every avenue was tried, and it is worth writing them
down: they all look viable until you try them.

### The rules were ready and valid

Thirty-three `allow` rules closing ninety-three of the hundred and twenty-nine
lines, among them all forty-nine `vold` ones on the `uevent` node. They were
validated for real: the policies were taken from the phone (`plat`,
`mapping/29.0`, `plat_pub_versioned`, `vendor`, `system_ext`) and fed to
`secilc` with the neverallow checks **enabled**, counting the violations.

| | violations |
|---|---|
| without our rules | 196 |
| with our rules | 196 |

The 196 are pre-existing: they are conflicts between the Android 10 MediaTek
policy and platform 13 (`llkd` against `teeregistryd_app` and the like), and
they are why init compiles with the neverallow checks disabled. The first round
added seven: those rules -- reserved properties for `rild`, `mtk_hal_camera`,
`stflashtool`, `mtk_hal_wifi`, and `dac_override` for `kernel` -- were dropped,
because there the prohibition is deliberate.

### The wall: where to put them

When init recompiles the policy at boot, it merges five files. None of the
three that could host them is reachable:

**`/vendor/etc/selinux/vendor_sepolicy.cil`** is the MediaTek blob. Modifying
it would mean altering a stock partition: the build does not do it, it is not
reproducible, and it is not something to submit.

**`/odm/etc/selinux/odm_sepolicy.cil`** looks like the right way -- it is where
AOSP expects rules to be added without touching vendor -- but here `/odm/etc`
is a symlink to `/vendor/odm/etc`, so we are back inside the stock partition.
Only those who look notice:

    lrw-r--r-- 1 root root 15 /odm/etc -> /vendor/odm/etc

Before finding that out, the file had been put in the boot.img ramdisk, which
is useless for a second reason: the "/" of a running phone is `dm-0`, that is
the system partition mounted as root, and the ramdisk disappears after first
stage init.

**`/product/etc/selinux/product_sepolicy.cil`** is the only one living inside
system.img (`/product` is a symlink to `/system/product`), and indeed it can be
written. But the rules still do not get there: that path is already a soong
target (`overriding commands for target ...`), and using the intended mechanism
(`PRODUCT_PRIVATE_SEPOLICY_DIRS`) the compiler stops at the first vendor type:

    sepolicy/product/private/vendor_bridge.te:3:
      ERROR 'unknown type sysfs_mmcblk'

Declaring it in `sepolicy/vendor/` does not help: the product policy conf does
not include the vendor directories. **This is Treble separation working as
intended**: system-side policy cannot name vendor types, by construction. It is
not an obstacle to be worked around with more cleverness.

### What would remain to be done, if it were ever needed

Build the vendor policy instead of taking it from the blob, bringing the
MediaTek HAL rules in. That is the work
`TARGET_USES_PREBUILT_VENDOR_SEPOLICY` avoids, and the comment in
`BoardConfig.mk` recounts how it went the last time it was replaced: the vendor
services fell silent and `system_server` hung waiting for them.
