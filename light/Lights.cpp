/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "light-s88pro"

#include "Lights.h"

#include <android-base/file.h>
#include <android-base/logging.h>
#include <android-base/stringprintf.h>
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
 * All the lights here but the rear strip are LED class devices of the
 * leds-mt65xx driver: the panel backlight and the three colours of the LED at
 * the top of the front (which reach the MT6370's RGB channels through the
 * kernel's mode 6, drivers/misc/mediatek/leds/mt6771/mtk_leds.c). The stock
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

/*
 * The rear "eye", the light strip around the cameras: an Awinic AW22127 with
 * nine RGB LEDs, which plays animations from firmware files in
 * /vendor/firmware, picked by number on the effect node and started through
 * cfg; hwen powers the controller (the numbers are the driver's,
 * drivers/misc/mediatek/leds/mt6771/aw22127/leds-aw22xxx.c).
 *
 * It shows the notification light: breathing in its colour while the light
 * is to pulse, steady while it is not, dark otherwise. The breathing is
 * full_charged.bin's animation and the steady light aw22xxx_cfg_led_on.bin's;
 * their own colours are not used.
 * The files write each LED's colour as red, green, blue, while this board's
 * LEDs take green, red, blue (measured: a value in the first of each three
 * registers lights green, in the second red), so the stock "charging" comes
 * out green and "charged" red. Written to cfg as 2 rather than 1, the driver
 * puts the nine colours of its rgb node in place of every colour the file
 * writes (aw22xxx_cfg_loaded()), and those are set here, in the board's order.
 *
 * The stock vendor policy lets only system_server and system_app at hwen,
 * effect and cfg, under types of its own; the same access for this service is
 * in sepolicy/system_ext/private/compat/29.0/29.0.compat.cil. The rgb node,
 * which the vendor neither labels nor hands to anyone, is
 * sysfs_aw22xxx_rgb (sepolicy/system_ext/private/file.te), given to system by
 * this service's init script.
 */
constexpr char kRear[] = "/sys/class/leds/aw22xxx_led/";
constexpr int kRearLeds = 9;
constexpr int kRearSteady = 1;   // aw22xxx_cfg_led_on.bin
constexpr int kRearBreath = 11;  // full_charged.bin
constexpr const char* kColours[] = {
        "/sys/class/leds/red/",
        "/sys/class/leds/green/",
        "/sys/class/leds/blue/",
};

// What each LED shows, most important first: the front one the battery light,
// the rear strip the notification light, after the attention light -- which
// nothing in the framework sets here (config_useAttentionLight is off and no
// one calls setAttentionLight), but which would belong with notifications.
constexpr LightType kFrontLights[] = {
        LightType::BATTERY,
};
constexpr LightType kRearLights[] = {
        LightType::ATTENTION,
        LightType::NOTIFICATIONS,
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

bool isBlinking(const HwLightState& state) {
    return state.flashMode != FlashMode::NONE && state.flashOnMs > 0 && state.flashOffMs > 0;
}

// The first lit of the given lights, or an unlit state if none is.
template <size_t N>
HwLightState firstLit(const std::map<LightType, HwLightState>& states,
                      const LightType (&order)[N]) {
    for (LightType type : order) {
        auto it = states.find(type);
        if (it != states.end() && isLit(it->second)) {
            return it->second;
        }
    }
    return {};
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
    const HwLightState shown = firstLit(mIndicator, kFrontLights);
    const bool blink = isBlinking(shown);
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

    updateRear();
}

void Lights::updateRear() {
    const HwLightState shown = firstLit(mIndicator, kRearLights);
    const int32_t colour = shown.color & 0x00ffffff;
    const int effect = isBlinking(shown) ? kRearBreath : kRearSteady;
    // Starting an animation reloads its firmware: only when something changes.
    if (colour == mRearColour && (colour == 0 || effect == mRearEffect)) {
        return;
    }
    mRearColour = colour;
    mRearEffect = effect;

    const std::string rear = kRear;
    if (colour == 0) {
        write(rear + "hwen", 0);
        return;
    }

    // In the board's order: green, red, blue.
    const int32_t r = (colour >> 16) & 0xff;
    const int32_t g = (colour >> 8) & 0xff;
    const int32_t b = colour & 0xff;
    const int32_t board = (g << 16) | (r << 8) | b;
    for (int i = 0; i < kRearLeds; i++) {
        write(rear + "rgb", ::android::base::StringPrintf("%d %06x", i, board));
    }
    write(rear + "hwen", 1);
    write(rear + "effect", effect);
    write(rear + "cfg", 2);
}

ndk::ScopedAStatus Lights::getLights(std::vector<HwLight>* _aidl_return) {
    int32_t ordinal = 0;
    _aidl_return->push_back({static_cast<int32_t>(LightType::BACKLIGHT), ordinal++,
                             LightType::BACKLIGHT});
    for (LightType type : kRearLights) {
        _aidl_return->push_back({static_cast<int32_t>(type), ordinal++, type});
    }
    for (LightType type : kFrontLights) {
        _aidl_return->push_back({static_cast<int32_t>(type), ordinal++, type});
    }
    return ndk::ScopedAStatus::ok();
}

}  // namespace light
}  // namespace hardware
}  // namespace android
}  // namespace aidl
