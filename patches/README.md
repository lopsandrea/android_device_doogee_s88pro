# Patches to the LineageOS tree

Changes that do not belong in the device tree because they touch common
projects. They have to be reapplied after every `repo sync`.

## frameworks_opt_telephony-baseband-version-length.patch

**Project**: `frameworks/opt/telephony`

**Symptom**: `com.android.phone` crashes as soon as the modem answers,
restarts, crashes again, until `ActivityManager` gives up ("crashed too many
times, killing"). No usable SIM.

```
java.lang.IllegalArgumentException: value of system property 'gsm.version.baseband'
  is longer than 91 characters: E977_VSIM_71_Q0_L...
    at android.sysprop.TelephonyProperties.baseband_version(TelephonyProperties.java:177)
    at android.telephony.TelephonyManager.setBasebandVersionForPhone(TelephonyManager.java:10838)
    at com.android.internal.telephony.GsmCdmaPhone.handleMessage(GsmCdmaPhone.java:3040)
```

**Cause**: AOSP truncates the baseband version string to `PROP_VALUE_MAX/2` (46
characters), but does so **per phone**; the values are then concatenated into a
single property, which cannot exceed 91 characters. This device declares
`ro.telephony.sim.count=3`, and the MediaTek RIL returns long strings: 3 × 46
goes past the limit and `SystemProperties.set` raises the exception. With only
two SIMs the total would still be 93 characters.

**Change**: the per-phone budget goes from `PROP_VALUE_MAX/2` to
`PROP_VALUE_MAX/4` (23 characters): 3 × 23 plus two commas makes 71, within the
limit. The truncation keeps the **tail** of the string, which is the part
identifying the modem build.

## packages_apps_Nfc-null-native-data.patch — REMOVED, no longer needed

**Project**: `packages/apps/Nfc`

**Symptom**: `com.android.nfc` dies and restarts roughly every 0.8 seconds,
forever, with a native crash:

```
signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x10
Cause: null pointer dereference
  #00 libnfc_nci_jni.so (android::nfaDeviceManagementCallback(...)+808)
  #01 libnfc-nci.so (nfa_dm_nfc_response_cback(...))
  #02 libnfc-nci.so (nfc_ncif_proc_rf_field_ntf(unsigned char))
```

**Cause**: in `nfaDeviceManagementCallback` the code calls
`getNative(NULL, NULL)` and immediately uses the result with
`ScopedAttach attach(nat->vm, &e)`, without checking it is not `NULL`. The ST
HAL sends the RF field notification before the JNI side is initialised: `nat`
is `NULL` and `nat->vm` dereferences offset `0x10` — the exact address reported
in the tombstone.

**Change**: a `nat == NULL` check before use, at the two places with the same
defect (`NFA_DM_RF_FIELD_EVT` and `NFA_DM_NFCC_TRANSPORT_ERR_EVT`/`TIMEOUT`). A
notification that arrives too early is ignored instead of taking the process
down.

**LineageOS 21 now has it of its own**, and in three places rather than two:
`NativeNfcManager.cpp` guards `getNative(NULL, NULL)` at lines 771, 800 and
1030 of the tree synced on 11 September 2026. The wording differs -- `if
(!nat)` with "cached nat is null", and at the second site the check folded
into `if (recovery_option && nat != NULL)` -- but the defect is the same one,
and the patch no longer applies.

## packages_apps_Nfc-mifare-classic-extras.patch — REMOVED, no longer needed

It added to `NativeNfcTag.java` the missing `case
TagTechnology.MIFARE_CLASSIC`: without it the extras `Bundle` stayed null and
every app opening a Mifare card died with `NullPointerException` inside
`NfcA.<init>`.

**LineageOS 20 now has it of its own.** At line 756 of that file there is the
exact same code -- SAK taken from `mTechActBytes[i][0]`, ATQA from
`mTechPollBytes[i]` -- and the patch no longer applied. Verified against the
tree synced on 8 September 2026.


## packages_apps_FMRadio-antenna-selection.patch

**Project**: `packages/apps/FMRadio`

**What it is for**: choosing which antenna path the FM tuner uses, on a phone
that has no headphone jack.

The app selects the antenna only when it receives the `HEADSET_PLUG` broadcast:

```java
mValueHeadSetPlug = (intent.getIntExtra("state", -1) == HEADSET_PLUG_IN) ? 0 : 1;
switchAntennaAsync(mValueHeadSetPlug);
```

Here that broadcast never arrives — there is no jack to plug anything into —
and the chip stays on the default value. The patch calls `switchAntenna` at
startup, when the device declares the internal antenna, reading the value from
a property:

```bash
setprop persist.vendor.fm.antenna 0    # long antenna: the cable in the connector
setprop persist.vendor.fm.antenna 1    # short antenna: the internal one (default)
```

It is a property and not a constant precisely so the two can be compared
without rebuilding.

**Status**: with the internal antenna alone reception stays weak — you hear
noise. The tuner does work, though: it powers up, tunes and recognises RDS. A
real antenna is needed, that is, a connected cable.

## frameworks_base-screenrecord-encoder-limits.patch

**Project**: `frameworks/base`

**Symptom**: screen recording produces a **black** video, without a single
error message.

**Cause**: an AOSP defect that surfaces here.
`ScreenMediaRecorder.getSupportedSize()` asks the **decoder** for the maximum
size:

```java
// Get max size from the decoder, to ensure recordings will be playable on device
MediaCodec decoder = MediaCodec.createDecoderByType(videoType);
```

The intent is to make sure the video is playable, but nobody asks the
**encoder** whether it can produce it. On this phone the decoder reaches
3840×2176 and the encoder stops well before: the native resolution
(1080×2340) therefore counts as "supported", is not scaled down, and the
recording comes out empty. Where the two limits coincide the defect does not
show.

**Change**: query the encoder too and use the tighter of the two limits, both
for the maximum size and for the alignment, and check `isSizeSupported` on
both.

## frameworks_av-wfd-encoder-choice.patch

**Project**: `frameworks/av`

**What it is for**: making the WiFi Display encoder selectable, which it
otherwise is not. `Converter::initEncoder()` takes the first available encoder
with `CreateByType` and, unlike `MediaCodecSource`, has no fallback if that one
fails. The patch first reads the property

```
media.wfd.video-encoder
```

and, when set, uses that codec.

**Still needed?** Not to make Miracast work: since AFBC was turned off
(`debug.gpu.afbc.disable=1` in the device tree) the hardware encoder correctly
encodes buffers coming from a Surface too, and WiFi Display runs accelerated
without being told anything. The property is in fact no longer set in the
device tree.

It stays in tree because it is the only lever on that path: should an encoder
one day misbehave at a particular resolution, it is the only way to fall back
to software without rebuilding —

```bash
setprop media.wfd.video-encoder c2.android.avc.encoder
```

The full story of the AFBC defect, with the reverse engineering of the blob and
the hypotheses that were ruled out, is in
`docs/bringup/hardware-riferimento.md`.

## build_make-vendor-prebuilt-in-target-files.patch

**Project**: `build/make`

**Symptom**: the build completes but the OTA package cannot be generated:

```
vendor is in target super_..._partition_list but no BlockDifference object
is provided
```

and, once past that, `blockimgdiff.py` stops on an `AssertionError` about a
missing block map.

**Cause**: this device ships the stock vendor image whole
(`BOARD_PREBUILT_VENDORIMAGE`), and three passes of the build assume every
partition is one it constructs. The `VENDOR/` directory never enters the
target-files, so the OTA generator finds no partition to diff;
`generate-image-prop-dictionary` is only called for constructed partitions, so
`vendor_disable_sparse=true` never lands in the misc_info and a ready-made
image is treated as sparse; and the non-sparse branch insists on a block map
existing beside the image even though it never reads it.

On LineageOS 21 a fourth one appeared. `ota_from_target_files` now runs
`checkvintf --check-compat` over the target-files, and stops on:

```
No device manifest file from device or from update package
ERROR: No such device
common.ExternalError: Failed to run command 'checkvintf --check-compat ...'
  (exit code 70)
```

The device manifest and the device compatibility matrix are read from
`VENDOR/`, and the block above copies the *staging* directory there — which
for a prebuilt vendor holds little more than the SELinux policy, 16 files in
all. The real `manifest.xml` (24 kB) and `compatibility_matrix.xml` are inside
the image.

**Change**: four additions to `core/Makefile` that cover the prebuilt case
alongside the constructed one. The fourth pulls `/etc/vintf` out of the image
itself with `debugfs_static -R rdump`, rather than keeping a copy of those
files in the device tree: a copy could drift from the image it is supposed to
describe, and this cannot.

**Status**: needed. The vendor image is still prebuilt — that is what the
charter asks for, since a maintainer must not require a *modified* one.

The note that once stood here, that this patch would have to be rewritten for
LineageOS 21 around `map_file_generator` instead of `e2fsdroid`, turned out to
be unfounded: `e2fsdroid -e -B` still produces the block map, `vendor.map`
comes out at 110 kB and `vendor_disable_sparse=true` reaches the misc_info.
Measured on the tree of 11 September 2026, not assumed.

## vendor_lineage-kernel-flags-for-soong.patch

**Project**: `vendor/lineage`

**Symptom**: the kernel builds, but the soong modules that read its headers
are compiled without the device's extra flags — so `LLVM_IAS=0` and
`KCFLAGS=-gdwarf-4` are missing exactly where they are needed, and the build
fails on assembly that clang-17's integrated assembler rejects.

**Cause**: `TARGET_KERNEL_ADDITIONAL_FLAGS` was applied only in
`vendor/lineage/build/tasks/kernel.mk`, which make reads *after* the
BoardConfigs. That is in time for the kernel, built in that phase, but not for
soong: `lineage_generator` (`generated_kernel_includes`) captures
`KERNEL_MAKE_FLAGS` as it stands when exported to soong, that is, without
them.

**Change**: apply the device's flags in `config/BoardConfigKernel.mk` too, so
they are already there when the export happens.

**Status**: needed as long as this device builds a 4.14 kernel with the
toolchain LineageOS ships. The four obstacles that make that necessary are in
`docs/bringup/` in the oracolo repository.

## packages_modules_Bluetooth-erroneous-data-reporting.patch

**Project**: `packages/modules/Bluetooth`

**Symptom**: Bluetooth never turns on. `com.android.bluetooth` dies and is
restarted over and over, the adapter stays `OFF` with a null address, and
`BluetoothManagerService` eventually gives up with `MESSAGE_TIMEOUT_BIND`:

```
check_complete: Error code UNSUPPORTED_LMP_OR_LL_PARAMETER, opcode 0x2001
on_command_status: Received UNEXPECTED command status:UNKNOWN_HCI_COMMAND
  opcode:0xc5a (READ_DEFAULT_ERRONEOUS_DATA_REPORTING)
Fatal signal 6 (SIGABRT) in tid (bt_stack_manage), pid (droid.bluetooth)
Abort message: 'assertion 'was_validated_' failed'
  #04 libbluetooth_jni.so (bluetooth::hci::CommandCompleteView::GetCommandOpCode)
  #05 libbluetooth_jni.so (bluetooth::hci::Controller::impl::read_default_...)
```

**Cause**: the controller announces `READ_DEFAULT_ERRONEOUS_DATA_REPORTING` in
its supported-commands bitmap, so `Controller::impl` sends it — and then
answers `UNKNOWN_HCI_COMMAND`, with a **command status** rather than a command
complete. `hci_layer` hands that event to the handler registered for the
command anyway; building a `CommandCompleteView` out of it yields an invalid
view, and the first line of the handler reads `GetCommandOpCode()` from it.
Reading any field of an unvalidated view aborts the process.

AOSP already expects controllers that lie about supporting this command — the
comment in the handler says so, bug b/277589118 — but the guard sits one line
below the first read, so it never runs for a controller that lies this way.

**Change**: check `view.IsValid()` at the top of
`read_default_erroneous_data_reporting_handler`, before anything is read from
the view. An invalid answer is logged and ignored, which is what the existing
guard was meant to do. Erroneous data reporting is an optional audio-quality
feature; nothing else depends on it.

## packages_modules_vndk-restore-vndk-29-apex.patch

**Project**: `packages/modules/vndk`

**Branch**: `lineage-22.2` only. LineageOS 21 still declares the module.

**Symptom**: the phone hangs on the vendor logo and never reaches the boot
animation. USB does not even enumerate, so there is nothing to read over adb;
the log below was taken with `initlog`.

```
linkerconfig: Unable to access VNDK APEX at path: /apex/com.android.vndk.v29:
  No such file or directory
linkerconfig: Check failed: !"undefined var" SANITIZER_DEFAULT_VENDOR is not defined
linkerconfig: libc: Fatal signal 6 (SIGABRT) in tid 382 (linkerconfig)
  ... in BuildVendorNamespace(...)
```

`linkerconfig` aborts, `/linkerconfig/ld.config.txt` is never written, and the
linker falls back to a single namespace. Everything that needs a real one then
dies:

```
CANNOT LINK "/vendor/bin/hw/android.hardware.keymaster@4.0-service.trustkernel":
  cannot locate symbol "_ZN9keymaster24PureSoftKeymasterContextC1Ev"
  referenced by "/vendor/lib64/libkeymaster4.so"
CANNOT LINK "/system/bin/keystore2":
  library "libandroidicu.so" not found: needed by /system/lib64/libsqlite.so
CANNOT LINK "/vendor/bin/hw/android.hardware.nfc@1.2-service-st":
  library "android.hardware.nfc@1.0.so" not found
```

and vold waits for keystore2 forever, one line per second, without ever giving
up:

```
ServiceManagerCppClient: Waited one second for
  android.system.keystore2.IKeystoreService/default
```

**Why**: AOSP commit 6e59419, *"Removing vndk apex v29 — It's not used"*,
deleted the module. For AOSP that is true: nothing there targets VNDK 29 any
more. This vendor is Android 10 and targets exactly that, and
`PRODUCT_TARGET_VNDK_VERSION := 29` in device.mk says so.

Putting `prebuilts/vndk/v29` back in the local manifest is necessary and not
sufficient: the libraries are there, but without this module nothing packages
them into an APEX, and `/apex/com.android.vndk.v29` is what linkerconfig looks
for.

**What it does**: reverts that commit, and nothing else. The eight lines it
restores are the same shape as the v30 block right above them, and everything
they rely on is still in the tree — `vndk-apex-defaults`, `apex_vndk`,
`build/soong/apex/vndk.go`.

**Measured after**: `m com.android.vndk.v29` installs
`system/system_ext/apex/com.android.vndk.v29.apex` together with the
`vndk-29` and `vndk-sp-29` symlinks in `system/lib` and `system/lib64`, the
same layout LineageOS 21 produces, and passes `apex_linkerconfig_validation`,
`apex_sepolicy_tests` and `host_apex_verifier`.

## frameworks_av-restore-audio-hal-v5.patch

**Project**: `frameworks/av`

**Branch**: `lineage-22.2` only. LineageOS 21 still builds the V5 client.

**Symptom**: the phone reaches the LineageOS boot animation and stays there.
`audioserver` dies every five seconds and `system_server` files an ANR about
once a minute:

```
F libc  : Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0
          in tid 724 (audioserver), pid 724 (audioserver)
F DEBUG : Cause: null pointer dereference
F DEBUG : #00 pc 000ccb58  /system/bin/audioserver
            (android::AudioFlinger::onFirstRef()+704)
F DEBUG : #01 pc 00078bf4  /system/bin/audioserver (main+332)
```

**Why**: `libaudiohal` only looks for the HAL versions it knows, and Android 15
knows four:

```cpp
static const std::array<AudioHalVersionInfo, 4> sAudioHALVersions = {
    AIDL 1.0, HIDL 7.1, HIDL 7.0, HIDL 6.0,
};
```

This vendor is Android 10 and offers `android.hardware.audio@5.0::IDevicesFactory`.
None of the four matches, `createPreferredImpl` returns null, and
`AudioFlinger::onFirstRef()` dereferences it. LineageOS 21 has the same array
with five entries, the fifth being HIDL 5.0, which is why the same vendor works
there.

**What it does**: reverts AOSP commit 559e9765c5, *"Remove framework support for
audio HIDL HAL V5 — This HAL version has been deprecated in Android V"*. That
commit is a clean deletion of 29 lines across three files: the version from the
array, the `libaudiohal@5.0` module, and its entry in the parent Android.bp.

Nothing else had to be restored, and that is the point: the conditional code
the V5 client needs is still in the tree — `#if MAJOR_VERSION <= 5` and
`#if MAJOR_VERSION < 5` are still in `impl/DeviceHalHidl.cpp` and
`impl/StreamHalHidl.cpp`, and `hardware/interfaces/audio/5.0` still exists.
Only the build target and the lookup entry were taken away.

## packages_apps_FMRadio-frequency-units.patch

**Project**: `packages/apps/FMRadio`

**Symptom**: on LineageOS 22, where the app builds its own libfmjni, the tuner
opens and then refuses to power up:

```
FMLIB_COM : COM_open_dev, [fd=105] [ret=0]
FMLIB_CORE: FMR_open_dev, [fd=105] [chipid=0x6631] [ret=0]
FMLIB_CORE: FMR_pwr_up,[freq=1000]
FMLIB_CORE: FMR_pwr_up error freq: 1000
```

1000 is outside the 8750..10800 band, so `FMR_pwr_up` rejects it.

**Why**: `libfm_jni.cpp` is not consistent with itself. The app always speaks
in MHz, and the JNI converts:

```c
powerUp:  tmp_freq = (int)(freq * 10);    // 100.0 -> 1000
tune:     tmp_freq = (int)(freq * 10);
seek:     tmp_freq = (int)(freq * 100);   // 87.55 -> 8755
          val = (float)ret_freq / 100;
```

`seek` works in tens of kHz, `powerUp` and `tune` in hundreds. The band this
library is configured with -- and the units MediaTek's driver takes, which is
what `COM_pwr_up` passes straight to `FM_IOCTL_POWERUP` without converting --
are tens of kHz. So `seek` is right and the other two are wrong.

The inconsistency is old: LineageOS 21 has it too. It never showed there
because that release shipped MediaTek's own libfmjni, which was consistent at
x100 throughout. It only bites once the app builds the library itself.

**What it does**: makes `powerUp` and `tune` convert the way `seek` already
does. Two lines. It is not an adaptation to this device: it is one file
agreeing with itself.

## build_make-no-recovery-patch-with-prebuilt-vendor.patch

**Project**: `build/make`

**Branch**: `lineage-23.2` only. LineageOS 22.2 and 21 already carry the change
this restores.

**Symptom**: the build reaches 95% and then stops packaging the target files:

```
FileNotFoundError: [Errno 2] No such file or directory:
  '.../lineage_s88pro-target_files/VENDOR/bin/install-recovery.sh'
```

**Why**: `make_recovery_patch.py` writes the recovery-from-boot patch into the
target files, and has to decide where. It knows two cases in 23.2:

```python
if board_uses_vendorimage:  target_files_dir = "VENDOR"
else:                       target_files_dir = "SYSTEM"
```

There is a third, and it is ours: a device that *uses* a vendor image without
*building* it. `BOARD_PREBUILT_VENDORIMAGE` means the image is copied whole, so
target files hold `IMAGES/vendor.img` and no `VENDOR/` tree to write into.

LineageOS already solved this. Commit 27376ac8dd by TheScarastic,
*"Don't make recovery patch for devices with prebuilt vendor"*, adds
`board_builds_vendorimage` next to `board_uses_vendorimage` and makes the
writer do nothing when the vendor image is not built. It is on lineage-22.2 and
on lineage-21; it has not been forward-ported to lineage-23.2.

**What it does**: the same three changes, re-applied by hand because the
surrounding code has moved since 2020 — `core/Makefile` declares
`board_builds_vendorimage` when `BUILDING_VENDOR_IMAGE` is set,
`make_recovery_patch.py` gains the third case and returns early from
`output_sink`, and `non_ab_ota.py` stops looking for a patch nobody wrote.

**When it can be dropped**: as soon as LineageOS forward-ports 27376ac8dd.
Check with `git log -S board_builds_vendorimage -- tools/releasetools/` before
carrying it to the next release.

## system_core-blkio-cgroup-optional.patch

**Project**: `system/core`

**Branch**: `lineage-23.2` only. On 22.2 the same failure is not fatal.

**Symptom**: LineageOS 23.2 installs and then reboots to the bootloader about
fourteen seconds in, over and over. It is not a crash: init does it on purpose.

```
init: starting service 'apexd-bootstrap'...
init: Command 'exec_start apexd-bootstrap' ... failed: Could not start exec
  service: createProcessGroup(0, 327, 0) failed for service
  'apexd-bootstrap': No such file or directory
init: Service 'apexd-bootstrap' failed to start due to a fatal error
reboot: Restarting system with command 'bootloader,bootstrap-apexd-failed'
```

apexd is not the culprit, it is simply the first service init tries to start.
The real failure is ten lines earlier:

```
libprocessgroup: Failed to mount controller blkio: No such file or directory
libprocessgroup: Failed to setup blkio cgroup
init: Command 'SetupCgroups' ... failed: Failed to setup cgroups
```

**Why**: this kernel has no blkio controller. `/proc/cgroups` on the phone
lists cpuset, cpu, cpuacct, schedtune, memory and freezer, and nothing else.
That is equally true under 22.2, where the same two lines appear in the boot
log and the phone boots anyway.

What differs is what happens next. `CgroupSetup()` in
`libprocessgroup/setup/cgroup_map_write.cpp` stops at the first controller that
fails:

```cpp
if (!SetupCgroup(descriptor)) {
    LOG(ERROR) << "Failed to setup " << name << " cgroup";
    return false;
}
// System / app isolation.
```

and the block it never reaches, "System / app isolation", is the one that
creates `/sys/fs/cgroup/system`. Without that directory `createProcessGroup`
cannot place any service, so no service starts at all.

`MountV1CgroupController` already has the answer written into it:

```cpp
if (mount(...)) {
    if (IsOptionalController(controller)) {
        PLOG(INFO) << "Failed to mount optional controller " << ...;
        return true;
    }
    PLOG(ERROR) << "Failed to mount controller " << ...;
    return false;
}
```

and the log says `Failed to mount controller blkio`, the second branch.

**What it does**: marks blkio `"Optional": true` in `cgroups.json`. One line.
It states a fact about this device rather than working around a check.

**The alternative, and why not**: turning on `CONFIG_BLK_CGROUP` in the kernel
would give the controller for real. It also changes block layer structures,
and on this device a kernel configuration change that moves symbol CRCs stops
the factory Wi-Fi, Bluetooth and GPS modules from loading. That trade is not
worth making for a controller Android has booted without here since 21.

## frameworks_native-epoll-pwait2-fallback.patch

**Project**: `frameworks/native`

**Branch**: `lineage-23.2` only. LineageOS 22.2 does not call epoll_pwait2.

**Symptom**: the phone reaches the LineageOS boot animation and stays there for
ever. Nothing crashes, no tombstone is written, and one line repeats:

```
E BLASTBufferQueue: epoll_wait error while waiting for buffer release.
  errno=38 message='Function not implemented'
```

**Why**: errno 38 is ENOSYS. `BufferReleaseReader::readBlocking` calls
`epoll_pwait2`, added in Linux 5.11; this device runs 4.14.180.

**What it does**: tries `epoll_pwait2`, and on ENOSYS falls back to
`epoll_pwait`, which differs only in taking a millisecond timeout instead of a
timespec. The timeout is rounded up: truncating a sub-millisecond wait to zero
would turn a blocking read into a busy loop.

**Note**: this is a portability fallback, not a guard being overridden. The two
calls do the same thing.

## packages_modules_Connectivity-bpfloader-kernel-version.patch

**Project**: `packages/modules/Connectivity`

**Branch**: `lineage-23.2` only. LineageOS 22.2 logs the same condition and
carries on.

**Symptom**: two failures in a row, both before any service starts. First the
loader refuses to run and init reboots the phone:

```
NetBpfLoad: Android V requires kernel 4.19.
init: bpfloader-failed
```

With that cleared, netd aborts every five seconds instead:

```
NetdUpdatable: libnetd_updatable_init: Failed:
  V+ platform with kernel version < 4.19.0 is unsupported
```

**Why**: Android 15 bumped the eBPF kernel requirement to 4.19 and 25Q2 to 5.4.
This phone is a 2019 MediaTek on 4.14.180, and it cannot be moved: the factory
Wi-Fi, Bluetooth and GPS modules are binaries built against that kABI.

**What it does**: turns four refusals into warnings, two in the loader and two
in netd.

**Note**: read this one carefully before assuming it is a guard being
overridden. The distinction is in `BpfHandler.cpp` itself, a few lines below
the change:

```
// V requires 4.19+, so technically this 2nd 'if' is not required, but
// it doesn't hurt us to try to support AOSP forks that try to support
// older kernels.
```

Every `attachProgramToCgroup` and every `queryProgram` in that function is
already guarded by its own `isAtLeastKernelVersion`, so on 4.14 it attaches
what the kernel takes and skips the rest. Of the sixteen kernel-version tests
in Connectivity and netd, only four are refusals; the other twelve are branches
that handle the old kernel. These four are a statement about what AOSP
supports, not about what the code can do.

**Still to verify on a booted phone**: per-uid traffic accounting, firewall and
data saver rules, and tethering. A phone that boots with these quietly broken
would be worse than 22.2, which works.
