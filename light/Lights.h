/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <aidl/android/hardware/light/BnLights.h>

#include <map>
#include <mutex>

using ::aidl::android::hardware::light::HwLight;
using ::aidl::android::hardware::light::HwLightState;
using ::aidl::android::hardware::light::LightType;

namespace aidl {
namespace android {
namespace hardware {
namespace light {

class Lights : public BnLights {
  public:
    ndk::ScopedAStatus setLightState(int32_t id, const HwLightState& state) override;
    ndk::ScopedAStatus getLights(std::vector<HwLight>* _aidl_return) override;

  private:
    void setBacklight(const HwLightState& state);
    void updateIndicator();

    std::mutex mLock;
    // The last state asked for each of the three lights that share the one
    // RGB indicator. Which of them shows is decided in updateIndicator().
    std::map<LightType, HwLightState> mIndicator;
};

}  // namespace light
}  // namespace hardware
}  // namespace android
}  // namespace aidl
