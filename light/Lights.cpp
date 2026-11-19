/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "light-s88pro"

#include "Lights.h"

#include <android-base/file.h>
#include <android-base/logging.h>
#include <android-base/strings.h>

#include <cstdlib>
#include <iterator>
#include <string>

namespace aidl {
namespace android {
namespace hardware {
namespace light {

namespace {

/*
 * All the lights here are LED class devices of the leds-mt65xx driver: the
 * panel backlight and the three colours of the notification LED. The stock
 * Android 10 vendor drives them through /vendor/lib64/hw/lights.mt6771.so,
 * behind the HIDL light 2.0 service that Android 17 no longer talks to
 * (hardware/interfaces/light/2.0 is gone). A system process may not dlopen
 * that library, so this writes the same nodes the library writes -- its
 * strings list exactly these paths and no others.
 *
 * Blinking uses the kernel's "timer" trigger: once it is selected the driver
 * creates delay_on and delay_off next to brightness, already owned by system
 * and labelled sysfs_leds like the rest. Measured on the phone.
 */
constexpr char kBacklight[] = "/sys/class/leds/lcd-backlight/";
constexpr const char* kColours[] = {
        "/sys/class/leds/red/",
        "/sys/class/leds/green/",
        "/sys/class/leds/blue/",
};

// The three logical lights folded onto the one RGB LED, most important first.
constexpr LightType kIndicatorOrder[] = {
        LightType::ATTENTION,
        LightType::NOTIFICATIONS,
        LightType::BATTERY,
};

bool write(const std::string& path, const std::string& value) {
    if (!::android::base::WriteStringToFile(value, path)) {
        PLOG(ERROR) << "cannot write " << value << " to " << path;
        return false;
    }
    return true;
}

bool write(const std::string& path, int32_t value) {
    return write(path, std::to_string(value));
}

int32_t readMax(const std::string& led) {
    std::string content;
    if (!::android::base::ReadFileToString(led + "max_brightness", &content)) {
        return 255;
    }
    const int32_t max = std::atoi(::android::base::Trim(content).c_str());
    return max > 0 ? max : 255;
}

// The framework hands over an ARGB colour even for the backlight. This is the
// weighting AOSP's own lights HALs use to turn it into a single level.
int32_t luminance(int32_t color) {
    const int32_t r = (color >> 16) & 0xff;
    const int32_t g = (color >> 8) & 0xff;
    const int32_t b = color & 0xff;
    return (77 * r + 150 * g + 29 * b) >> 8;
}

bool isLit(const HwLightState& state) {
    return (state.color & 0x00ffffff) != 0;
}

}  // namespace

ndk::ScopedAStatus Lights::setLightState(int32_t id, const HwLightState& state) {
    const LightType type = static_cast<LightType>(id);
    std::lock_guard<std::mutex> lock(mLock);

    switch (type) {
        case LightType::BACKLIGHT:
            setBacklight(state);
            return ndk::ScopedAStatus::ok();
        case LightType::ATTENTION:
        case LightType::NOTIFICATIONS:
        case LightType::BATTERY:
            mIndicator[type] = state;
            updateIndicator();
            return ndk::ScopedAStatus::ok();
        default:
            return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
    }
}

void Lights::setBacklight(const HwLightState& state) {
    static const int32_t max = readMax(kBacklight);
    write(std::string(kBacklight) + "brightness", luminance(state.color) * max / 255);
}

void Lights::updateIndicator() {
    HwLightState shown{};
    for (LightType type : kIndicatorOrder) {
        auto it = mIndicator.find(type);
        if (it != mIndicator.end() && isLit(it->second)) {
            shown = it->second;
            break;
        }
    }

    const bool blink = shown.flashMode != FlashMode::NONE && shown.flashOnMs > 0 &&
                       shown.flashOffMs > 0;
    const int32_t channels[] = {
            (shown.color >> 16) & 0xff,
            (shown.color >> 8) & 0xff,
            shown.color & 0xff,
    };

    for (size_t i = 0; i < std::size(kColours); i++) {
        const std::string led = kColours[i];
        const int32_t level = channels[i] * readMax(led) / 255;

        // Always go through "none" first: it stops a running timer and puts
        // the LED back in a known state before the new one is applied.
        write(led + "trigger", "none");
        if (level == 0) {
            write(led + "brightness", 0);
            continue;
        }
        write(led + "brightness", level);
        if (blink) {
            write(led + "trigger", "timer");
            write(led + "delay_on", shown.flashOnMs);
            write(led + "delay_off", shown.flashOffMs);
        }
    }
}

ndk::ScopedAStatus Lights::getLights(std::vector<HwLight>* _aidl_return) {
    int32_t ordinal = 0;
    _aidl_return->push_back({static_cast<int32_t>(LightType::BACKLIGHT), ordinal++,
                             LightType::BACKLIGHT});
    for (LightType type : kIndicatorOrder) {
        _aidl_return->push_back({static_cast<int32_t>(type), ordinal++, type});
    }
    return ndk::ScopedAStatus::ok();
}

}  // namespace light
}  // namespace hardware
}  // namespace android
}  // namespace aidl
