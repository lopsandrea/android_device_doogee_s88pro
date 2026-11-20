/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "powershare-s88pro"

#include "PowerShare.h"

#include <android-base/file.h>
#include <android-base/logging.h>
#include <android-base/strings.h>

namespace aidl::vendor::lineage::powershare {

namespace {

constexpr char kReverseChargerNode[] =
        "/sys/devices/platform/11005000.i2c/i2c-6/6-002b/mt5725group/reverse_charger";

}  // namespace

ndk::ScopedAStatus PowerShare::isEnabled(bool* _aidl_return) {
    std::string value;
    if (!::android::base::ReadFileToString(kReverseChargerNode, &value)) {
        PLOG(ERROR) << "cannot read " << kReverseChargerNode;
        return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
    }
    // "reverse_charger en : 1"
    *_aidl_return = ::android::base::EndsWith(::android::base::Trim(value), "1");
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerShare::setEnabled(bool enable) {
    if (!::android::base::WriteStringToFile(enable ? "1" : "0", kReverseChargerNode)) {
        PLOG(ERROR) << "cannot write " << kReverseChargerNode;
        return ndk::ScopedAStatus::fromExceptionCode(EX_SERVICE_SPECIFIC);
    }
    LOG(INFO) << "reverse charging " << (enable ? "on" : "off");
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerShare::getMinBattery(int32_t* _aidl_return) {
    *_aidl_return = 0;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerShare::setMinBattery(int32_t) {
    return ndk::ScopedAStatus::ok();
}

}  // namespace aidl::vendor::lineage::powershare
