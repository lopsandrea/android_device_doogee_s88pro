/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <aidl/android/hardware/power/BnPower.h>
#include <android/hardware/power/1.3/IPower.h>

#include <mutex>

namespace aidl::android::hardware::power::impl::s88pro {

/*
 * The AIDL power HAL, over MediaTek's HIDL one.
 *
 * The stock vendor image has a HIDL power HAL (android.hardware.power@1.3)
 * that boosts the CPU on the framework's hints, and ignores the one feature
 * it is asked to turn on or off: double tap to wake, which it only logs. So
 * this service answers the framework in its place. It turns double tap to
 * wake on and off itself, through the touch driver, and passes every other
 * hint to MediaTek's HAL, translated exactly as the framework would have
 * translated it (frameworks/native/services/powermanager/PowerHalWrapper.cpp,
 * HidlHalWrapperV1_0 to V1_3): to the CPU, nothing changes.
 *
 * Hint sessions (ADPF) are not supported, as they were not with the HIDL HAL.
 */
class Power : public BnPower {
  public:
    ndk::ScopedAStatus setMode(Mode type, bool enabled) override;
    ndk::ScopedAStatus isModeSupported(Mode type, bool* _aidl_return) override;
    ndk::ScopedAStatus setBoost(Boost type, int32_t durationMs) override;
    ndk::ScopedAStatus isBoostSupported(Boost type, bool* _aidl_return) override;
    ndk::ScopedAStatus createHintSession(int32_t tgid, int32_t uid,
                                         const std::vector<int32_t>& threadIds,
                                         int64_t durationNanos,
                                         std::shared_ptr<IPowerHintSession>* _aidl_return) override;
    ndk::ScopedAStatus getHintSessionPreferredRate(int64_t* outNanoseconds) override;
    ndk::ScopedAStatus createHintSessionWithConfig(
            int32_t tgid, int32_t uid, const std::vector<int32_t>& threadIds,
            int64_t durationNanos, SessionTag tag, SessionConfig* config,
            std::shared_ptr<IPowerHintSession>* _aidl_return) override;
    ndk::ScopedAStatus getSessionChannel(int32_t tgid, int32_t uid,
                                         ChannelConfig* _aidl_return) override;
    ndk::ScopedAStatus closeSessionChannel(int32_t tgid, int32_t uid) override;

  private:
    using MtkPower = ::android::hardware::power::V1_3::IPower;

    // Runs call on MediaTek's HAL, fetching it first if need be. A failed
    // call drops it, so that a restarted HAL is fetched again next time.
    template <typename Call>
    void callMtkPower(const char* what, Call&& call);

    std::mutex mLock;
    ::android::sp<MtkPower> mMtkPower;
};

}  // namespace aidl::android::hardware::power::impl::s88pro
