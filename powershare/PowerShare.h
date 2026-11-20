/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <aidl/vendor/lineage/powershare/BnPowerShare.h>

namespace aidl::vendor::lineage::powershare {

/*
 * Reverse charging, for LineageOS's PowerShare tile: the phone powers another
 * device resting on its back.
 *
 * The switch is the MT5725 wireless charging chip's own sysfs node, which
 * reads back as "reverse_charger en : 0" or "... : 1". The vendor's
 * init.mt6771.rc makes it world-writable; it carries a type of its own,
 * sysfs_rvs (sepolicy/system_ext/private/file.te), since as generic sysfs no
 * one could write it.
 *
 * The minimum battery level is not this service's to enforce: the tile checks
 * it, as with LineageOS's own default implementation, which ignores it too.
 */
class PowerShare : public BnPowerShare {
  public:
    ndk::ScopedAStatus getMinBattery(int32_t* _aidl_return) override;
    ndk::ScopedAStatus isEnabled(bool* _aidl_return) override;
    ndk::ScopedAStatus setEnabled(bool enable) override;
    ndk::ScopedAStatus setMinBattery(int32_t minBattery) override;
};

}  // namespace aidl::vendor::lineage::powershare
