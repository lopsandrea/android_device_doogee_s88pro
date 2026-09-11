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

## packages_apps_Nfc-null-native-data.patch

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
