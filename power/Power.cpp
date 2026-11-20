/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "power-s88pro"

#include "Power.h"

#include <android-base/file.h>
#include <android-base/logging.h>
#include <unistd.h>

#include <optional>

namespace aidl::android::hardware::power::impl::s88pro {

using ::android::hardware::power::V1_3::PowerHint;

namespace {

// Created by the touch driver: drivers/input/touchscreen/mediatek/ilitek_e977/
// ilitek_tp_gesture.c in the kernel. The vendor's init.mt6771.rc gives it to
// the system user.
constexpr char kTapToWakeNode[] = "/sys/class/tp_gesture/gesenable";

// The hint libpowermanager sends a HIDL power HAL for each mode and boost.
std::optional<PowerHint> hintFor(Mode mode) {
    switch (mode) {
        case Mode::LAUNCH:
            return PowerHint::LAUNCH;
        case Mode::LOW_POWER:
            return PowerHint::LOW_POWER;
        case Mode::SUSTAINED_PERFORMANCE:
            return PowerHint::SUSTAINED_PERFORMANCE;
        case Mode::VR:
            return PowerHint::VR_MODE;
        case Mode::CAMERA_STREAMING_SECURE:
        case Mode::CAMERA_STREAMING_LOW:
        case Mode::CAMERA_STREAMING_MID:
        case Mode::CAMERA_STREAMING_HIGH:
            return PowerHint::CAMERA_STREAMING;
        case Mode::AUDIO_STREAMING_LOW_LATENCY:
            return PowerHint::AUDIO_LOW_LATENCY;
        case Mode::EXPENSIVE_RENDERING:
            return PowerHint::EXPENSIVE_RENDERING;
        default:
            return std::nullopt;
    }
}

std::optional<PowerHint> hintFor(Boost boost) {
    switch (boost) {
        case Boost::INTERACTION:
            return PowerHint::INTERACTION;
        case Boost::CAMERA_SHOT:
            return PowerHint::CAMERA_SHOT;
        case Boost::CAMERA_LAUNCH:
            return PowerHint::CAMERA_LAUNCH;
        default:
            return std::nullopt;
    }
}

ndk::ScopedAStatus unsupported() {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

}  // namespace

template <typename Call>
void Power::callMtkPower(const char* what, Call&& call) {
    ::android::sp<MtkPower> power;
    {
        std::lock_guard<std::mutex> lock(mLock);
        if (mMtkPower == nullptr) {
            // Declared in the vendor manifest, so this waits for it to start.
            mMtkPower = MtkPower::getService();
            if (mMtkPower == nullptr) {
                LOG(ERROR) << "MediaTek's power HAL is not available";
                return;
            }
        }
        power = mMtkPower;
    }
    auto ret = call(power);
    if (!ret.isOk()) {
        LOG(ERROR) << what << ": " << ret.description();
        std::lock_guard<std::mutex> lock(mLock);
        if (mMtkPower == power) mMtkPower = nullptr;
    }
}

ndk::ScopedAStatus Power::setMode(Mode type, bool enabled) {
    if (type == Mode::DOUBLE_TAP_TO_WAKE) {
        if (::android::base::WriteStringToFile(enabled ? "1" : "0", kTapToWakeNode)) {
            LOG(INFO) << "double tap to wake " << (enabled ? "on" : "off");
        } else {
            PLOG(ERROR) << "cannot write " << kTapToWakeNode;
        }
        return ndk::ScopedAStatus::ok();
    }
    if (type == Mode::INTERACTIVE) {
        callMtkPower("setInteractive",
                     [enabled](const auto& power) { return power->setInteractive(enabled); });
        return ndk::ScopedAStatus::ok();
    }
    if (std::optional<PowerHint> hint = hintFor(type)) {
        callMtkPower("powerHintAsync_1_3", [hint, enabled](const auto& power) {
            return power->powerHintAsync_1_3(*hint, enabled ? 1 : 0);
        });
        return ndk::ScopedAStatus::ok();
    }
    return unsupported();
}

ndk::ScopedAStatus Power::isModeSupported(Mode type, bool* _aidl_return) {
    if (type == Mode::DOUBLE_TAP_TO_WAKE) {
        *_aidl_return = access(kTapToWakeNode, F_OK) == 0;
    } else {
        *_aidl_return = type == Mode::INTERACTIVE || hintFor(type).has_value();
    }
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::setBoost(Boost type, int32_t durationMs) {
    if (std::optional<PowerHint> hint = hintFor(type)) {
        callMtkPower("powerHintAsync_1_3", [hint, durationMs](const auto& power) {
            return power->powerHintAsync_1_3(*hint, durationMs);
        });
        return ndk::ScopedAStatus::ok();
    }
    return unsupported();
}

ndk::ScopedAStatus Power::isBoostSupported(Boost type, bool* _aidl_return) {
    *_aidl_return = hintFor(type).has_value();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::createHintSession(int32_t, int32_t, const std::vector<int32_t>&,
                                            int64_t,
                                            std::shared_ptr<IPowerHintSession>* _aidl_return) {
    *_aidl_return = nullptr;
    return unsupported();
}

ndk::ScopedAStatus Power::getHintSessionPreferredRate(int64_t* outNanoseconds) {
    *outNanoseconds = -1;
    return unsupported();
}

ndk::ScopedAStatus Power::createHintSessionWithConfig(
        int32_t, int32_t, const std::vector<int32_t>&, int64_t, SessionTag, SessionConfig*,
        std::shared_ptr<IPowerHintSession>* _aidl_return) {
    *_aidl_return = nullptr;
    return unsupported();
}

ndk::ScopedAStatus Power::getSessionChannel(int32_t, int32_t, ChannelConfig*) {
    return unsupported();
}

ndk::ScopedAStatus Power::closeSessionChannel(int32_t, int32_t) {
    return unsupported();
}

}  // namespace aidl::android::hardware::power::impl::s88pro
