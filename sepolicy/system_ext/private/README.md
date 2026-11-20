# SELinux rules on the system side

This directory is `SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS` (see `BoardConfig.mk`).
The vendor policy is the stock Android 10 one, taken whole from the vendor
image (`TARGET_USES_PREBUILT_VENDOR_SEPOLICY`), and init compiles it at boot
together with ours, bridged by the 29.0 mapping. Every rule here answers a
denial measured on the phone under enforcing, and is as narrow as it can be.

## What is where

| file | what it is for |
|---|---|
| `file_contexts`, `genfs_contexts`, `file.te` | `/data/nfc` as `nfc_data_file`; the fstab at the root of system; the two HAL binaries; the reverse charging node, which had the generic `sysfs` type and so could not be written by anyone |
| `hal_light_s88pro.te`, `hal_vibrator_s88pro.te` | the AIDL lights and vibrator services that stand in for the stock HIDL ones. The lights one also needs `patches/system_sepolicy-core-domain-lights-hal.patch`, because `sysfs_leds` is kept from core domains |
| `init.te` | the `volte_imsa2`, `volte_ut` and `vendor.bip` sockets, which vendor `.rc` files declare without a context |
| `lmkd.te` | see below |
| `system_app.te` | S88ProParts: the LED directories and the reverse charging node. Plus a quiet refusal for Settings' memory page |
| `seapp_contexts`, `platform_app.te` | the FM radio app, see below |
| `property_contexts` | `ro.audio.legacy_call_routing` |
| `service_contexts` | the binder services of MediaTek's ImsService, which runs in the phone UID |
| `compat/29.0/29.0.compat.cil` | every rule that names a vendor type, see below |

## Rules that name vendor types

A `.te` file here is compiled at build time against the platform policy
alone, where vendor types do not exist: `allow vold sysfs_mmcblk:file write`
does not compile. `compat/29.0/29.0.compat.cil` does not go through that
compiler. The build only appends it to
`system_ext/etc/selinux/mapping/29.0.compat.cil`, and init compiles it at boot
(`LoadSplitPolicy`) together with the vendor policy, where those types exist.

The other files init merges were tried first and are dead ends: vendor is the
stock partition, odm too (`/odm/etc` is a link to `/vendor/odm/etc`), and the
product policy is built against the platform exactly like this directory.

Two things to know before touching that file:

- A misspelt type does not fail the build, it fails init: the policy does not
  compile at boot and the phone stops at the logo. Replay init's compile on
  the build host, with `secilc` and the files init would load, before
  flashing any change to it.
- An `ioctl` permission needs an `allowx` as well. AOSP gives every domain
  an `allowx` for `FIOCLEX` on every file type, and once a source, target and
  class have any `allowx`, a plain `allow` on `ioctl` no longer lets the other
  commands through.

Some denials are the vendor asking for something it does not need, such as
idle maintenance trimming the persist partition. Those are `dontaudit`, each
with the reason next to it.

## lmkd.te

    allow lmkd cgroup:file w_file_perms;

lmkd asks the kernel for PSI and falls back to vmpressure when there is none.
PSI landed in 4.20 and this device runs 4.14, so the fallback is the only path
-- and it registers an eventfd by *writing* into
`/dev/memcg/cgroup.event_control`. AOSP grants lmkd only `r_file_perms` on
cgroup files, because on a kernel new enough for PSI this never happens.

Without it lmkd exits, init restarts it, and ActivityManagerService retries the
connection from inside `updateOomAdjLocked` -- holding the AMS lock -- until the
watchdog kills `system_server`. 7535 retries in one boot. The other half of that
fix is in `patches/system_core-cgroups-json.patch`, which puts the memory
controller back in the v1 hierarchy where `cgroup.event_control` exists.

## The FM radio app

    avc: denied { read write } for name="fm" scontext=u:r:system_app:s0
      tcontext=u:object_r:fm_device:s0 tclass=chr_file permissive=0

`fm_device` is the vendor's, and AOSP forbids `system_app` from it. The vendor
policy, though, already grants the tuner to `platform_app_29_0`, which the
mapping turns into our `platform_app`: that is where the stock FM app ran. So
`seapp_contexts` puts the LineageOS app, which shares the system UID and would
land in `system_app`, into `platform_app`, and `platform_app.te` gives it back
what `system_app` had over its own data.

## Lessons that still hold

- **A neverallow is usually on files, not directories.** AOSP forbids core
  domains from writing `sysfs` files; searching the directories is allowed,
  and that was all the LEDs needed.
- **When a type is the vendor's, look at whom the vendor already grants it
  to.** The vendor policy was written for a phone that worked: something was
  allowed to reach that hardware, as the FM radio shows.
- **A denial forbidden by a neverallow can mean a wrong label.**
  `network_stack -> fs_bpf` was not a rule to add: the kernel gave everything
  under bpffs the root's type, ignoring the per-path `genfscon` entries. The
  fix was upstream commit 4ca54d3d3022 ("security: selinux: allow per-file
  labeling for bpffs"), in the kernel tree.
