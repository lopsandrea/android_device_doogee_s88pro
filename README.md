Device tree for DOOGEE S88 Pro (s88pro)
=======================================

The DOOGEE S88 Pro is a rugged smartphone from 2020. This tree builds
LineageOS 24.0 on it, over the stock Android 10 vendor partition.

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
      https://raw.githubusercontent.com/lopsandrea/android_device_doogee_s88pro/lineage-24.0/s88pro.xml
    repo sync

Then apply the patches in [`patches/`](patches): they touch common projects,
so they cannot live in the device tree, and they have to be reapplied after
every `repo sync`. The README next to them explains, for each one, symptom,
cause and change.

For VoLTE, prepare MediaTek's ImsService once with
`ims/prepare-imsservice.sh` (the comment at its top says where the APK comes
from). Without it the build works the same, without VoLTE.

    source build/envsetup.sh
    lunch lineage_s88pro-cp2a-userdebug
    mka bacon

The kernel
----------

The kernel is built from source: the charter requires it, and
`BoardConfig.mk` points at `kernel/doogee/s88pro`. The sources are in
[android_kernel_doogee_s88pro](https://github.com/lopsandrea/android_kernel_doogee_s88pro):
an ALPS 4.14 tree in which the missing drivers were reconstructed by reverse
engineering the stock kernel, checking every fix against the original binary.

Known limitations
-----------------

- **Video calls and Wi-Fi calling are off.** VoLTE voice works; the video and
  Wi-Fi halves of MediaTek's IMS stack are not set up.
- **Emergency calls go over the circuit-switched network**, falling back from
  LTE, even with VoLTE registered: emergency over IMS has not been tried.
- **The kernel is 4.14.** A few things Android 17 expects from a newer one are
  not there, local network protection among them; the patches in `patches/`
  keep the platform from tripping over their absence.
