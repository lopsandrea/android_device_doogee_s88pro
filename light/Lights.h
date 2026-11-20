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
    void updateRear();

    std::mutex mLock;
    // The last state asked for each of the three indicator lights. The front
    // LED shows the battery light (updateIndicator()), the rear strip the
    // notification light (updateRear()).
    std::map<LightType, HwLightState> mIndicator;
    // What the rear strip shows: its colour, 0 when dark and -1 before the
    // first update, and the effect playing it.
    int32_t mRearColour = -1;
    int mRearEffect = -1;
};

}  // namespace light
}  // namespace hardware
}  // namespace android
}  // namespace aidl
