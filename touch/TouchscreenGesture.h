/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <aidl/vendor/lineage/touch/BnTouchscreenGesture.h>

#include <mutex>

namespace aidl::vendor::lineage::touch {

/*
 * LineageOS's touchscreen gestures (Settings > System > Gestures in
 * LineageParts), drawn on the dark screen.
 *
 * The Ilitek controller recognises them in the gesture mode it also uses for
 * double tap to wake; the touch driver reports each one it is told to as a
 * key of its own, and LineageParts acts on that key. This service lists the
 * gestures and tells the driver which ones are wanted, through
 * /sys/class/tp_gesture/gesmask (drivers/input/touchscreen/mediatek/
 * ilitek_e977/ilitek_tp_gesture.c in the kernel).
 */
class TouchscreenGesture : public BnTouchscreenGesture {
  public:
    ndk::ScopedAStatus getSupportedGestures(std::vector<Gesture>* _aidl_return) override;
    ndk::ScopedAStatus setGestureEnabled(const Gesture& gesture, bool enabled) override;

  private:
    std::mutex mLock;
    uint32_t mMask = 0;
};

}  // namespace aidl::vendor::lineage::touch
