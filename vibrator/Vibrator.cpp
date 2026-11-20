/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "vibrator-s88pro"

#include "Vibrator.h"

#include <android-base/file.h>
#include <android-base/logging.h>

#include <string>

namespace aidl {
namespace android {
namespace hardware {
namespace vibrator {

namespace {

/*
 * The motor is a LED class device. Writing the length in milliseconds to
 * "duration" and then 1 to "activate" starts it, and the driver clears
 * "activate" by itself when the time is up; writing 0 stops it early.
 *
 * Measured on the phone: after "activate" goes to 1 it returns to 0 exactly one
 * duration later, and the motor runs. There is also a "brightness" attribute,
 * with max_brightness 255, which is not needed -- the sequence above vibrates
 * with brightness left at 0.
 *
 * The stock Android 10 vendor drives the same node through
 * /vendor/lib64/hw/vibrator.default.so, behind the HIDL 1.0 service that
 * Android 16 no longer talks to. Loading that library from here is not
 * possible: a system process may not dlopen a vendor one. So this writes the
 * node directly, which is what the library does anyway.
 */
constexpr char kActivatePath[] = "/sys/class/leds/vibrator/activate";
constexpr char kDurationPath[] = "/sys/class/leds/vibrator/duration";

/*
 * Below this the motor is not started at all. An ERM has one strength, so a
 * request can only be played in full or not played; the line sits between
 * the faint textures SystemUI sends while a finger drags a slider or a
 * notification (at most 50/255, about 0.2, see MSDLRepositoryImpl.kt,
 * DRAG_INDICATOR_CONTINUOUS) and everything meant to be felt, which asks for
 * 1.0 or close to it.
 */
constexpr float kAmplitudeThreshold = 0.3f;

bool write(const char* path, int32_t value) {
    const std::string content = std::to_string(value);
    if (!::android::base::WriteStringToFile(content, path)) {
        PLOG(ERROR) << "cannot write " << content << " to " << path;
        return false;
    }
    return true;
}

}  // namespace

ndk::ScopedAStatus Vibrator::getCapabilities(int32_t* _aidl_return) {
    /* No CAP_ON_CALLBACK: this HAL does not tell the caller when the buzz ends,
     * so the framework has to keep its own timer. Claiming the capability and
     * then never calling back would leave it waiting.
     *
     * CAP_AMPLITUDE_CONTROL although the motor has none: without it the
     * framework plays every waveform at full strength whatever amplitude it
     * asks for, and the faint drag textures of Android 16 turn into a motor
     * running almost without pause -- 65 ms out of every 70 while a slider
     * moves. With it, setAmplitude() gets to say which requests are too faint
     * to play.
     */
    *_aidl_return = IVibrator::CAP_AMPLITUDE_CONTROL;
    return ndk::ScopedAStatus::ok();
}

/*
 * With CAP_AMPLITUDE_CONTROL the framework turns the motor on for a window
 * and sets the amplitude right after, then again at every step of the
 * waveform (SetAmplitudeVibratorStep.java, startVibrating()). So on() only
 * opens the window, and the motor starts at the first amplitude strong enough
 * to be meant, for the whole window: these windows are tens of milliseconds,
 * and this motor needs about 40 to be felt at all.
 */
ndk::ScopedAStatus Vibrator::on(int32_t timeoutMs,
                                const std::shared_ptr<IVibratorCallback>& /*callback*/) {
    if (timeoutMs <= 0) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }
    std::lock_guard<std::mutex> lock(mLock);
    mWindowMs = timeoutMs;
    mStarted = false;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::off() {
    std::lock_guard<std::mutex> lock(mLock);
    mWindowMs = 0;
    mStarted = false;
    if (!write(kActivatePath, 0)) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_TRANSACTION_FAILED);
    }
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::setAmplitude(float amplitude) {
    /*
     * Android 17 can pass VibrationEffect.DEFAULT_AMPLITUDE (-1) through
     * unresolved, from SetAmplitudeVibratorStep.startVibrating(). Refusing it
     * failed every such vibration ("Error setting amplitude to -1.0") and the
     * phone did not vibrate at all, so read it as full strength. Zero falls
     * below the threshold and plays nothing.
     */
    if (amplitude < 0.0f) {
        amplitude = 1.0f;
    }
    if (amplitude > 1.0f) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }
    std::lock_guard<std::mutex> lock(mLock);
    if (mStarted || mWindowMs == 0 || amplitude < kAmplitudeThreshold) {
        return ndk::ScopedAStatus::ok();
    }
    if (!write(kDurationPath, mWindowMs) || !write(kActivatePath, 1)) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_TRANSACTION_FAILED);
    }
    mStarted = true;
    return ndk::ScopedAStatus::ok();
}

/*
 * Everything below is what this motor cannot do. A plain ERM with one on/off
 * line has no effects and no waveform composition; saying so makes the
 * framework fall back to timed buzzes built out of on(), setAmplitude() and
 * off(), which is the whole of what the hardware offers.
 */

ndk::ScopedAStatus Vibrator::perform(Effect /*effect*/, EffectStrength /*strength*/,
                                     const std::shared_ptr<IVibratorCallback>& /*callback*/,
                                     int32_t* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getSupportedEffects(std::vector<Effect>* _aidl_return) {
    /* No predefined effects, so perform() refuses them all. An empty list rather than
     * an error: the framework asks every HAL for it and logs a refusal as an error. */
    _aidl_return->clear();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::setExternalControl(bool /*enabled*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getCompositionDelayMax(int32_t* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getCompositionSizeMax(int32_t* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getSupportedPrimitives(
        std::vector<CompositePrimitive>* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getPrimitiveDuration(CompositePrimitive /*primitive*/,
                                                  int32_t* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::compose(const std::vector<CompositeEffect>& /*composite*/,
                                     const std::shared_ptr<IVibratorCallback>& /*callback*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getSupportedAlwaysOnEffects(std::vector<Effect>* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::alwaysOnEnable(int32_t /*id*/, Effect /*effect*/,
                                            EffectStrength /*strength*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::alwaysOnDisable(int32_t /*id*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getResonantFrequency(float* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getQFactor(float* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getFrequencyResolution(float* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getFrequencyMinimum(float* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getBandwidthAmplitudeMap(std::vector<float>* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getPwlePrimitiveDurationMax(int32_t* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getPwleCompositionSizeMax(int32_t* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::getSupportedBraking(std::vector<Braking>* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::composePwle(const std::vector<PrimitivePwle>& /*composite*/,
                                         const std::shared_ptr<IVibratorCallback>& /*callback*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

}  // namespace vibrator
}  // namespace hardware
}  // namespace android
}  // namespace aidl
