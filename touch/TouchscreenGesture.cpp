/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "touch-s88pro"

#include "TouchscreenGesture.h"

#include <android-base/file.h>
#include <android-base/logging.h>
#include <android-base/stringprintf.h>

namespace aidl::vendor::lineage::touch {

namespace {

constexpr char kGestureMaskNode[] = "/sys/class/tp_gesture/gesmask";

// The driver's numbering: gesture code 0x60 + n is bit n of the mask and
// comes back as scan code 0x2e8 + n.
constexpr int kFirstCode = 0x60;
constexpr int kFirstKey = 0x2e8;

struct GestureInfo {
    // The name LineageParts looks its title up by.
    const char* name;
    // The controller's code for it.
    int code;
};

// The gestures the controller recognised reliably when tried; S, Z and E,
// which it has codes for, came back unrecognised or as something else.
constexpr GestureInfo kGestures[] = {
        {"one_finger_up_swipe", 0x60},
        {"one_finger_down_swipe", 0x61},
        {"one_finger_left_swipe", 0x62},
        {"one_finger_right_swipe", 0x63},
        {"letter_m", 0x64},
        {"letter_w", 0x65},
        {"letter_c", 0x66},
        {"letter_v", 0x68},
        {"letter_o", 0x69},
};

constexpr int kGestureCount = sizeof(kGestures) / sizeof(kGestures[0]);

}  // namespace

ndk::ScopedAStatus TouchscreenGesture::getSupportedGestures(std::vector<Gesture>* _aidl_return) {
    _aidl_return->clear();
    for (int i = 0; i < kGestureCount; i++) {
        _aidl_return->push_back({
                .id = i,
                .name = kGestures[i].name,
                .keycode = kFirstKey + (kGestures[i].code - kFirstCode),
        });
    }
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus TouchscreenGesture::setGestureEnabled(const Gesture& gesture, bool enabled) {
    if (gesture.id < 0 || gesture.id >= kGestureCount) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }

    std::lock_guard<std::mutex> lock(mLock);
    const uint32_t bit = 1u << (kGestures[gesture.id].code - kFirstCode);
    const uint32_t mask = enabled ? (mMask | bit) : (mMask & ~bit);
    if (!::android::base::WriteStringToFile(::android::base::StringPrintf("%x", mask),
                                            kGestureMaskNode)) {
        PLOG(ERROR) << "cannot write " << kGestureMaskNode;
        return ndk::ScopedAStatus::fromExceptionCode(EX_SERVICE_SPECIFIC);
    }
    mMask = mask;
    LOG(INFO) << kGestures[gesture.id].name << (enabled ? " on" : " off");
    return ndk::ScopedAStatus::ok();
}

}  // namespace aidl::vendor::lineage::touch
