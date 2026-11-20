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

## vendor_lineage-kernel-flags-for-soong.patch — REMOVED, no longer needed

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

**LineageOS 23.2 builds without it.** The patch no longer applies, forwards or
backwards (`config/BoardConfigKernel.mk` has moved under it), and it was not
applied in the tree that produced every 23.2 build of this device: from the
first boot in September to the builds of 4 October, `vendor/lineage` had no
local changes. `TARGET_KERNEL_ADDITIONAL_FLAGS` is still read only in
`build/tasks/kernel.mk`, so what changed is on the soong side; which change it
was has not been traced. The kernel flags themselves are still needed and
still in `BoardConfig.mk`.

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

**Change**: take the answer as a `CommandStatusOrCompleteView` instead of a
`CommandCompleteView`, and return when it turns out to be a status. Erroneous
data reporting is an optional audio-quality feature, which is why every other
failure in that handler returns as well.

**Why the shape of the fix changed on 23.2**: on 22.2 it was enough to check
`view.IsValid()` at the top of the handler, because `hci_layer` handed the
event over and only the unvalidated read aborted. Android 16 asserts one step
earlier, before the handler is called at all:

```
hci_layer.cc:278 handle_command_response:
  READ_DEFAULT_ERRONEOUS_DATA_REPORTING(0x0c5a) was not expecting status event
```

The parameter type of the handler is what decides this. `EnqueueCommand` picks
its overload from the callback signature, and a `CommandCompleteView` callback
tells `hci_layer` to expect a complete and nothing else. Asking for either lets
the event through, and the check inside stays where it was.

Symptom on 23.2: seven `com.android.bluetooth` tombstones in one boot, all with
the same abort message.

## packages_modules_vndk-restore-vndk-29-apex.patch

**Project**: `packages/modules/vndk`

**Branch**: from `lineage-22.2` on. LineageOS 21 still declares the module.

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

**Branch**: from `lineage-22.2` on. LineageOS 21 still builds the V5 client.

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

**Branch**: from `lineage-23.2` on. LineageOS 22.2 and 21 already carry the change
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

## system_core-cgroups-json.patch

**Project**: `system/core`

**Branch**: from `lineage-23.2` on. On 22.2 the same failure is not fatal.

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

**The alternative, and why it is not one**: turning on `CONFIG_BLK_CGROUP` in
the kernel would give the controller for real. It was tried, and measured:

```
module_layout:  0x2d522840 -> 0xb801cb84
```

`module_layout` is the first symbol every module checks, so a kernel built that
way loads none of them: no Wi-Fi, no Bluetooth, no GPS, no FM radio. Nor is it
one symbol -- 92 of the 231 that `wlan_drv_gen3` asks for move, 85 of 247 for
`wmt_drv`, 47 of 159 for `met`. The cause is `CONFIG_CGROUP_WRITEBACK`, which
`BLK_CGROUP` brings with it: it puts a field in `struct inode`, and `struct
inode` sits in the expansion of half the VFS symbols.

So the controller is not available on this device. Not inadvisable: not
available.

**How that was measured**, because it makes any other defconfig change
decidable too. Every `.ko` carries the CRCs it demands in its own `__versions`
section, 8 bytes of CRC and 56 of name per entry, and the kernel's
`Module.symvers` carries what it offers. Pull the modules out of `vendor.img`
with `debugfs`, read both sides, compare. The eight stock modules ask for 514
distinct symbols, of which this kernel exports 486, and the baseline has zero
diverging; a change that keeps it at zero is safe to flash. Disabling
`CONFIG_MTK_MMC_DEBUG` passed that check in the same sitting and freed 488 kB.

## The second change in the same file: memory back to cgroup v1

**Symptom**: the phone boots all the way -- `Boot is finished (74802 ms)`, the
launcher runs -- and then, about two minutes later, the screen goes black with
the backlight on and "System UI isn't responding" appears. `system_server` is
killed:

```
Watchdog: *** WATCHDOG KILLING SYSTEM PROCESS: Blocked in handler on main
          thread (main) for 60s
    at ActivityManagerService.serviceDoneExecuting
    - waiting to lock <0x07e79054> (a ActivityManagerService)
```

The counts in that boot's log say the rest:

```
7535  W ActivityManager: Failed to connect to lowmemorykiller, retry later
  31  E lowmemorykiller: init_mp_common: global monitoring is only available
                         for the v1 cgroup hierarchy
```

**Why**: lmkd asks the kernel for PSI and falls back to vmpressure when there
is none. PSI landed in 4.20 and this device runs 4.14.180, so the fallback is
the only path -- and it needs the memory controller in the **v1** hierarchy,
because `memory.pressure_level` and `cgroup.event_control` are v1 features.
`cgroups.json` declares memory under `Cgroups2`, so `memcg_version()` answers
v2, `init_mp_common` refuses, and lmkd exits. init restarts it, it exits again,
and ActivityManagerService retries the connection from inside
`updateOomAdjLocked` -- while holding the AMS lock. Hence the 3-second stalls
all over that boot (`Slow operation: 3011ms so far, now at
attachApplicationLocked: after updateOomAdjLocked`) and, in the end, the
watchdog.

**What it does**: moves the memory controller out of `Cgroups2` and into the v1
list at `/dev/memcg`, mode 0700 root:system -- which is where it was until
Android 13. The v2 entry was already marked `"Optional": true`, so AOSP already
allows for devices that do not have it there.

**See also**: `sepolicy/system_ext/private/lmkd.te`. Writing the eventfd triplet
into `cgroup.event_control` needs a permission AOSP does not grant, for the same
reason: on a kernel new enough for PSI this path is never taken.


## frameworks_native-epoll-pwait2-fallback.patch — REMOVED, no longer needed

**Project**: `frameworks/native`

**Branch**: `lineage-23.2` only. LineageOS 22.2 does not call epoll_pwait2,
and 24.0 no longer does.

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

**LineageOS 24.0 no longer needs it.** `BufferReleaseReader::readBlocking`
calls `epoll_wait` there, rounding the timeout up to a millisecond as this
patch did, with a TODO about moving to `epoll_pwait2` once libgui can use it.
Verified against the tree synced on 19 November 2026.

## packages_modules_Connectivity-bpfloader-kernel-version.patch

**Project**: `packages/modules/Connectivity`

**Branch**: from `lineage-23.2` on. LineageOS 22.2 logs the same condition and
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

**LineageOS 24.0** adds a third refusal to the loader, `Android 25Q4 requires
kernel 5.10.`, which returns 7 and reboots the phone the same way; it is a
warning too. The programs that need 5.10 carry their own minimum kernel
version, and the loader skips them below it as it does for 4.19 and 5.4. The
next step is already in the file: 26Q4 requires 5.15, and is not reached on
24.0, which is API 37.0 (26Q4 is 37.1).

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

## frameworks_base-hintmanager-no-aidl-power-hal.patch

**Project**: `frameworks/base`

**Branch**: from `lineage-23.2` on. LineageOS 22.2 has no `SupportInfo`.

**Symptom**: the phone reaches the LineageOS boot animation and stays there.
`system_server` throws, zygote dies with it, and init restarts the whole group
— zygote, zygote_secondary, netd, media, wificond, audioserver, cameraserver —
every seventeen seconds, indefinitely. Nothing else looks wrong: SELinux is up,
`/data` is mounted, the APEXes mount and unmount on every attempt. There is no
tombstone, because the crash is a Java exception:

```
E Zygote: System zygote died with fatal exception
java.lang.RuntimeException: Failed to create service
  com.android.server.power.hint.HintManagerService
Caused by: java.lang.NullPointerException: Attempt to read from field
  'android.hardware.power.SupportInfo$HeadroomSupportInfo
   android.hardware.power.SupportInfo.headroom' on a null object reference
  at HintManagerService.<init>(HintManagerService.java:337)
```

**Why**: the constructor only asks the HAL for its `SupportInfo` when the AIDL
power HAL exists:

```java
mPowerHal = injector.createIPower();
if (mPowerHal != null) {
    mSupportInfo = getSupportInfo();
}
if (mSupportInfo.headroom.isCpuSupported) {   // NPE when it does not
```

`createIPower` is `waitForDeclaredService(android.hardware.power.IPower)`. This
vendor declares `android.hardware.power` **HIDL 1.3** over hwbinder and
MediaTek's own `vendor.mediatek.hardware.power` 2.1, and no AIDL power HAL at
all, so it returns null and `mSupportInfo` stays null. AOSP assumes every
device has the AIDL HAL; a 2019 vendor image predates it.

**What it does**: lets the no-HAL case fall through to the defaults
`getSupportInfo()` already builds for a HAL too old to answer, instead of
leaving `mSupportInfo` null. The null check moves into `getSupportInfo()`,
where `mPowerHalVersion` stays 0 and both headroom flags are set false.

**Note**: this costs nothing that was working. With no AIDL HAL,
`isHintSessionSupported()` is already false — it reads
`mHintSessionPreferredRate`, which the native wrapper leaves at -1 — so ADPF
hint sessions were never available. Every other `mPowerHal` call site sits
behind `usesSessions` or `isCpuSupported`/`isGpuSupported`, all of which are
false on this device.

## packages_modules_Connectivity-lpm-trie-no-next-key.patch

**Project**: `packages/modules/Connectivity`

**Branch**: from `lineage-23.2` on. The map does not exist before Android 16.

**Symptom**: the phone stays on the LineageOS boot animation. `system_server`
throws, zygote dies with it, and init restarts the whole group every seventeen
seconds. There is no tombstone, because the crash is a Java exception:

```
Failed to create service com.android.server.NetworkStatsServiceInitializer
Caused by: IllegalStateException: Cannot open local_net_access map
Caused by: ErrnoException: nativeGetNextMapKey failed: errno 524
  at BpfMap.getFirstKey(BpfMap.java:247)
  at SingleWriterBpfMap.<init>(SingleWriterBpfMap.java:78)
```

and, once that one is fixed, the same errno one line further on, from
`IBpfMap.clear()`.

**Why**: 524 is ENOTSUPP. `local_net_access_map` is an `LPM_TRIE`
(`bpf/progs/netd.c`), and the kernel only learned `MAP_GET_NEXT_KEY` for that
map type in 4.16. This device runs 4.14.180, so the map can be created, read
and written, but not walked.

**What it does**: two changes in `SingleWriterBpfMap`. The constructor tolerates
ENOTSUPP while priming its cache -- at boot the loader has just created the map
and an empty cache is the right answer. And `clear()` is overridden to delete
the keys it has cached instead of walking the map in the kernel, which is
consistent with how the class already works: it is the map's exclusive writer,
and `containsKey()` and `getValue()` answer from the cache alone.

**What it costs**: after a runtime restart the cache starts empty while the map
may still hold entries, so it can under-report what is there. Nothing walks
this map on a fresh boot, which is the case that matters here.

**Verified on the phone**: per-uid accounting works. All six eBPF maps report
`OK` in `dumpsys netstats`, and a 1 MB download as uid 2000 shows up in the
per-uid history (`rb=2174394` across the session). Firewall rules reach netd
without error (`UID=10072 policy=1 (REJECT_METERED_BACKGROUND)`). Tethering
starts with `enableBpfOffload: true`; hardware offload is absent because the
vendor has no offload HAL, which is not new. Tethering itself was not driven
end to end -- that needs a second device.

## frameworks_base-choreographer-stuffing-tuning.patch

**Project**: `frameworks/base`

**Symptom**: no crash and no visible jank, but scrolling runs three to four
frames behind the finger, 50 to 65 ms from intended vsync to present on this
61 Hz panel, against a floor of two frames (about 33 ms).

**Cause**: buffer stuffing that is never drained. Every missed deadline -- the
app's, whose real work per frame is about 15 ms out of 16.4, or
SurfaceFlinger's, when a vsync is delivered late by the vendor HWC -- leaves
one more buffer queued, and the queue then stays that deep for the rest of the
gesture. Choreographer's recovery skips a vsync to drain it, but:

- this tree carries AOSP's multi-recovery change ("Recover from buffer
  stuffing multiple times in 1 animation"), behind the read-write aconfig flag
  `android.view.flags.buffer_stuffing_multi_recovery`. The flag has no value
  in the release config and is missing from the device's flag storage, so it
  reads false and `device_config` cannot turn it on: only the first stuffing
  of an animation is ever drained;
- a wait counts as stuffing only past half a frame interval, while in the
  three-frame state the app waits 1 to 2 ms on `dequeueBuffer`. That state is
  never detected at all.

Measured on traces: of 474 frames in a scroll, 410 Buffer Stuffing, 59 App
Deadline Missed, 1 on time; recovery started once in 12 s and never again.

**Change**: two hooks read when a Choreographer instance is created, so a
change applies on the next app start (the class is preloaded in zygote, and
static fields would freeze the value for every app):

- `debug.choreographer.multi_recovery`: when true, behave as if the flag were
  on;
- `debug.choreographer.stuffing_wait_us`: the dequeue wait that counts as
  stuffing; unset or negative keeps half a frame interval.

Unset, behaviour is unchanged. `debug.choreographer.*` is a namespace
Choreographer already reads and that every app may read; `persist.sys.*` would
be invisible to third-party apps, which would silently get the default. The
values the device ships are set in `device.mk`, with the measurements behind
them.

## system_sepolicy-core-domain-lights-hal.patch

**Project**: `system/sepolicy`

**Branch**: from `lineage-24.0` on. Up to 23.2 the framework still talks to the
factory HIDL lights HAL.

**Symptom**: the build stops at the system_ext policy:

```
neverallow check failed at plat_sepolicy.cil:22288 from system/sepolicy/private/coredomain.te:40
  (neverallow base_typeattr_374 sysfs_leds (file (ioctl read write create ...)))
    allow at plat_sepolicy.cil:38058 from system/sepolicy/private/hal_light.te:14
      (allow hal_light sysfs_leds (file (ioctl read write getattr lock append map open watch watch_reads)))
```

**Why**: Android 17 deleted `android.hardware.light@2.0`, the only lights
interface the factory vendor offers, and on this phone the backlight goes
through the lights HAL as well as the LEDs: the composer is 2.1 and cannot set
brightness. So 24.0 needs an AIDL lights HAL, and with the vendor image
prebuilt it lives in system_ext (`light/` in the device tree), where every
process is a core domain. The vendor labels the nodes of the LED driver
`sysfs_leds`; `coredomain.te` forbids core domains file access of any kind on
that type, and `hal_light.te` grants it to every lights HAL. A core-domain
lights HAL breaks the rule just by being one, whatever it touches.

**What it does**: adds `hal_light_server` to the exceptions of that
neverallow, next to `init`, `apexd`, `ueventd` and `vold`.

**Note**: neither way round it inside the device tree builds. Taking
`hal_light_server` without `hal_light` gets past this rule but trips
`{ hal_light_server -hal_light } domain:process fork` in `hal_attribute()`
(`public/te_macros`), which every domain breaks, since all of them may fork.
Relabelling the four nodes with a type of our own leaves the `hal_light` rule
where it is. The change is to private policy, which the freeze test does not
compare against the prebuilts.

## system_sepolicy-restore-vendor-29-mapping.patch

**Project**: `system/sepolicy`

**Branch**: from `lineage-24.0` on. Up to 23.2 the mappings are upstream.

**Symptom**: the install succeeds, and the first boot drops into the
bootloader: the screen shows "FASTBOOT mode". The last lines `init` leaves in
`console-ramoops` are

```
init: /system/etc/selinux/plat_sepolicy_and_mapping.sha256 and /vendor/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 differ
init: Compiling SELinux policy
init: Missing /system/etc/selinux/plat_sepolicy_genfs_202404.cil; skipping
```

and then nothing: `secilc` fails silently, and `InitFatalReboot` reboots into
the bootloader.

**Why**: AOSP commit `4758f73f98` ("Remove 29.0 and 30.0 SEPolicy support")
deleted the mapping files for vendor policies 29.0 and 30.0. The factory
vendor of this phone is 29.0 (`/vendor/etc/selinux/plat_sepolicy_vers.txt`),
and `init` compiles the policy at every boot with
`/system/etc/selinux/mapping/29.0.cil`, which the system image no longer
carries. The chain also goes through 30.0: the 29.0 mapping names types that
only the 30.0 mapping carries forward to 31.0.

**What it does**: restores, as they were before `4758f73f98`:
- `private/compat/29.0/` and `private/compat/30.0/` (mapping, compat and
  ignore files);
- the `se_build_files` and `se_cil_compat_map` modules for plat, system_ext
  and product in `compat/Android.bp`;
- the 29.0 and 30.0 entries in the phony lists of `Android.bp`, so the
  modules get installed.

One line is added to both compat files, which they never had upstream:
`(allow domain ashmem_libcutils_device (chr_file (open)))`. Android 17 no
longer lets every domain open `/dev/ashmem*`, and AOSP commit `7de96a86be`
put that rule back for older vendors in the 31.0 to 202504 compat files --
after 29.0 and 30.0 had been deleted. An Android 10 vendor only knows
`ashmem_device`, so without it every vendor and system process is refused
ashmem under enforcing (in permissive: 56 denials for
`hal_allocator_default` alone, plus `system_server`, `mediaserver`,
`audioserver`).

**Note**: the `treble_sepolicy_tests_29.0` and `_30.0` lines are left out on
purpose: they compare against `prebuilts/api/29.0` and `30.0`, which that
commit deleted too, and they only check the build. The patch was checked
before flashing by repeating the compilation `init` does
(`system/core/init/selinux.cpp`, `LoadSplitPolicy`) on the build host, with
the build outputs and the files of the factory `vendor.img`: it fails without
the patch and succeeds with it.

## system_core-ueventd-legacy-paths.patch

**Project**: `system/core`

**Branch**: from `lineage-24.0` on.

**Symptom**: the first boot stops on the DOOGEE logo, with no boot animation
and no adb. `vold` waits for keystore2 forever, keystore2 waits for the
keymaster, and the TrustKernel keymaster fails once a second:

```
tkcore-teec: error opening [/dev/tkcoredrv]: Permission denied(13)
init: Service 'teed' (pid 504) exited with status 253
KeymasterHAL: TrustKernelKeymasterImplementation.cpp:2005:  InitializeContext failed with 0xffff0008
libbinder.ServiceManagerCppClient: Waited one second for android.system.keystore2.IKeystoreService/default
```

The error is from the file mode, not from SELinux: it was measured with
SELinux permissive. `wmt_loader` and `wmt_launcher` (the Wi-Fi, Bluetooth and
GPS combo chip) loop on the same kind of error.

**Why**: AOSP commit `1b926a3444` ("Clean unused legacy_path from ueventd")
dropped the legacy configuration paths `/vendor/ueventd.rc`,
`/odm/ueventd.rc` and `/ueventd.<hardware>.rc`, which ueventd read for devices
whose `ro.product.first_api_level` is below 33. Now it reads
`/system/etc/ueventd.rc` only, which imports `/vendor/etc/ueventd.rc`. The
factory vendor is Android 10 and keeps its rules in `/vendor/ueventd.rc`, so
every MediaTek node is created with the default mode `0600 root root`. For
`/dev/tkcoredrv` the vendor says `0666`, and `teed` runs as `system`.

**What it does**: reverts `1b926a3444`. The legacy paths are read again only
when `ro.product.first_api_level` is below 33; here it is 29.

## system_core-init-session-keyring.patch and system_vold-session-keyring.patch

**Projects**: `system/core` and `system/vold`

**Branch**: from `lineage-24.0` on. LineageOS 23.2 carried the same reverts
itself (Michael Bestas: `97da59b5a5` and `9c5c0bad95` in `system/core`,
`5cbee143` in `system/vold`); 24.0 dropped them.

**Symptom**: about five seconds into the first boot the phone reboots into
recovery:

```
vold: Stored key /data/unencrypted/key
vold: Failed to install fscrypt key to /data: Inappropriate ioctl for device
init: Exec service failed, status 25: Rebooting into recovery, reason: enablefilecrypto_failed
```

**Why**: AOSP removed the way older kernels take file encryption keys, the
`fscrypt` keyring under init's session keyring ("remove session keyring
workaround for old kernels", Eric Biggers, `5d7c35ce20` in init and
`0e87a83c` in vold), and then `libkeyutils`, left without users
(`6dce39d61c`). vold now calls `FS_IOC_ADD_ENCRYPTION_KEY` unconditionally.
The commit message counts on android-4.14-stable having that ioctl; this
MediaTek 4.14 does not, and returns `ENOTTY`. The policy is v1 here
(`first_api_level` 29), which is what the session keyring serves.

**What it does**: reverts the three commits. Init creates the `fscrypt`
keyring again, and vold checks once whether the kernel has the ioctl, falling
back to `add_key()` on that keyring when it does not. In `installKey()` the
revert had to be merged with LineageOS's wrapped-key branch: the fallback now
comes right after the key reference is computed, whichever branch computed
it. This phone uses raw keys.

## system_bpf-restore-kver-5-10.patch

**Project**: `system/bpf`

**Branch**: from `lineage-24.0` on.

**Symptom**: a boot loop. The DOOGEE logo comes up, the phone restarts after
about ten seconds, and again, never reaching the boot animation:

```
BpfLoader-rs: Error when loading /system/etc/bpf/memevents/bpfMemEvents.bpf: Invalid argument (os error 22)
BpfLoader-rs: panicked at system/bpf/loader/bpfloader.rs:736:17:
Error when loading /system/etc/bpf/bpfRingbufProg.bpf: Invalid argument (os error 22)
init: Service bpfloader has 'reboot_on_failure' option and failed, shutting down system.
init: Reboot start, reason: reboot,bpfloader-failed, reboot_target: bpfloader-failed
```

**Why**: the programs in `bpfRingbufProg.bpf` and in the two memevents
files use BPF ring buffers, which arrived in Linux 5.8. Up to 23.2 the
platform loader skipped them on kernels older than 5.10; AOSP commit
`94106e81` ("bpfloader.rs: remove KVER_5_10") dropped that bound, since the
platform now requires 5.10. On this 4.14 the kernel refuses the ring buffer
map, and `bpfRingbufProg.bpf` is marked `critical`, so the loader panics and
init, which runs it with `reboot_on_failure`, restarts the phone.

**What it does**: reverts `94106e81`. Those maps and programs carry the
5.10 lower bound again and are skipped here, as they were in 23.2. The
tethering programs loaded by `netbpfload` are a separate matter: the ones
this kernel refuses are marked optional and only log a line.

## packages_modules_Connectivity-netd-stats-old-kernels.patch

**Project**: `packages/modules/Connectivity`

**Branch**: from `lineage-24.0` on.

**Symptom**: a boot loop, ten seconds a turn:

```
NetBpfLoad: skipping prog ingress_stats: api 3700 is outside required range [3300, 3500)
NetBpfLoad: skipping prog egress_stats: api 3700 is outside required range [3300, 3500)
NetdUpdatable: libnetd_updatable_init: Failed: Failed to get program from /sys/fs/bpf/netd_shared/prog_netd_egress_stats: No such file or directory
init: Service netd1shot has 'reboot_on_failure' option and failed, shutting down system.
```

**Why**: `netd.o` carries one `ingress_stats` and one `egress_stats` program
per range of kernel and platform versions. The one for kernels 4.9 to 4.19
was valid on every platform from T on, until AOSP commit `a54d8876674`
("bpf/netd: adjust api levels to reflect comments") capped it below V, since
no V device runs those kernels. Android 17 is API 37: on 4.14 no variant is
left, the loader pins nothing, and netd, which attaches both programs to the
root cgroup, aborts.

**What it does**: lifts the cap on the two 4.9 to 4.19 programs, as before
that commit. They are the same programs 23.2 ran on this kernel. The other
`netd.o` programs this kernel cannot take (bind, connect, sendmsg/recvmsg,
sockopt, AccECN) need 4.19 or later, were skipped in 23.2 too, and netd only
attaches them on kernels that have them.

## packages_modules_Connectivity-netd-ringbufs-old-kernels.patch

**Project**: `packages/modules/Connectivity`

**Branch**: from `lineage-24.0` on.

**Symptom**: the boot animation runs forever. system_server aborts ten
seconds after it starts, zygote goes down with it, and the cycle repeats:

```
signal 6 (SIGABRT)
  #01 libservice-connectivity.so (LocalNetEventHandler::GetRingbuf()::$_0::operator()() const+224)
  #03 libservice-connectivity.so (android::nativeGetLocalNetAccessRingbufFd(_JNIEnv*, _jclass*)+44)
  #08 service-connectivity.jar (LocalNetEventListener.<init>+60)
  #14 service-connectivity.jar (ConnectivityService.<init>+1402)
```

**Why**: on Android 16 and later, `ConnectivityService` always builds a
`LocalNetEventListener`, which opens the BPF ring buffer
`map_netd_local_net_note_op_ringbuf`. `netd.o` creates that map on 5.10 and
later kernels only (ring buffers came with 5.8); on 4.14 it is skipped, and
`BpfRingbuf` aborts when the map it is given cannot be opened.

Once past that, `systemReady()` does the same with the loopback access ring
buffer, `map_netd_loopback_access_ringbuf`, also 5.10 and later:

```
signal 6 (SIGABRT)
  #01 libservice-connectivity.so (LoopbackEventHandler::GetPoller()::$_0::operator()() const+512)
  #05 service-connectivity.jar (ConnectivityService.systemReadyInternal+438)
```

**What it does**: touches netd's ring buffers only when the kernel is 5.10
or later, checked with `Os.uname()`. Below that `mLocalNetEventListener`
stays `null`, the value `ConnectivityService` already handles for releases
before 16, and the loopback event consumer is not started. What goes missing
is the local network and loopback access metrics and the app-op notes, which
need BPF programs this kernel cannot load anyway.

## packages_modules_Connectivity-netstats-counters-npe.patch

**Project**: `packages/modules/Connectivity`

**Branch**: from `lineage-24.0` on.

**Symptom**: system_server dies in boot phase 550, now and then:

```
java.lang.RuntimeException: Failed to boot service com.android.server.NetworkStatsServiceInitializer: onBootPhase threw an exception during phase 550
Caused by: java.lang.NullPointerException: Attempt to invoke virtual method 'int android.net.connectivity.com.android.server.net.PersistentInt.get()' on a null object reference
    at android.net.connectivity.com.android.server.net.NetworkStatsService.makeRecordersLocked(NetworkStatsService.java:1173)
```

preceded by

```
TerribleErrorLog: Failed to create persistent counters, skip: java.io.IOException: Failed to create directory for /data/misc/apexdata/com.android.tethering/netstats/fastdatainput.successes.new
```

**Why**: an upstream bug. `makeRecordersLocked()` catches the failure to
create its two FastDataInput counters and turns the feature off, and then
reads the counters anyway, which are still `null`.

**What it does**: reads the counters only when they were created. Why the
file could not be created is a separate question (an occasional `EINVAL` on
file creation in `/data`, under investigation); this only stops it from
taking system_server down.

