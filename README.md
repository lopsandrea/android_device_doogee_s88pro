Device tree for DOOGEE S88 Pro (s88pro)
=======================================

The DOOGEE S88 Pro is a rugged smartphone from 2020. This tree builds
LineageOS 20.

Specifications, measured on the device
--------------------------------------

| item | value | how it was read |
|------|-------|-----------------|
| SoC | MediaTek Helio P70 (MT6771) | `ro.board.platform` |
| CPU | 8 cores, up to 2.106 GHz | `/proc/cpuinfo`, `cpufreq/cpuinfo_max_freq` |
| GPU | Mali-G72 MP3 | `glGetString(GL_RENDERER)` |
| RAM | 6 GB | `MemTotal: 5900900 kB` |
| Storage | 128 GB | `df` on `/data`: 107 GiB usable |
| Display | 1080x2340, density 480 | `wm size`, `wm density` |
| Rear camera | Sony IMX230, 5344x4016 capture | imgsensor driver |
| Front camera | Samsung S5K3P3SX | imgsensor driver |

Building
--------

Until the repos live under the LineageOS organisation a local manifest is
needed (see the comment inside `s88pro.xml` for why):

    mkdir -p .repo/local_manifests
    curl -o .repo/local_manifests/s88pro.xml \
      https://raw.githubusercontent.com/lopsandrea/android_device_doogee_s88pro/lineage-20/s88pro.xml
    repo sync

    source build/envsetup.sh
    breakfast lineage_s88pro-userdebug
    mka bacon

Before building, apply the six patches in [`patches/`](patches): they touch
common projects, so they cannot live in the device tree, and without three of
them the phone is unusable -- no working SIM and NFC crashing over and over.
The README next to them explains, for each one, symptom, cause and change.

The kernel
----------

The kernel is built from source: the charter requires it, and
`BoardConfig.mk` points at `kernel/doogee/s88pro`. The sources are in
[android_kernel_doogee_s88pro](https://github.com/lopsandrea/android_kernel_doogee_s88pro):
an ALPS 4.14.141 tree in which the missing drivers were reconstructed by
reverse engineering the stock kernel, checking every fix against the original
binary.

`prebuilt/kernel` is a pre-built `Image.gz-dtb` kept for anyone who only wants
to install without rebuilding; it is used only with
`TARGET_FORCE_PREBUILT_KERNEL`. `prebuilt/README.md` explains how to
regenerate it.

What does not work
------------------

- **video recording with the rear camera**: the file comes out with every frame
  a flat colour. It is not the kernel -- the stock one gets it wrong the same
  way -- and it is not the HAL, because OpenCamera and Telegram record fine on
  the same camera.
- **52 SELinux denials at boot**, between MediaTek vendor types: not closable
  from the device tree because the vendor policy arrives precompiled. None of
  them prevents anything. See `sepolicy/`.
