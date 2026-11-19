/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "light-s88pro"

#include "Lights.h"

#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

using ::aidl::android::hardware::light::Lights;

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(0);

    std::shared_ptr<Lights> lights = ndk::SharedRefBase::make<Lights>();
    const std::string instance = std::string(Lights::descriptor) + "/default";

    binder_status_t status =
            AServiceManager_addService(lights->asBinder().get(), instance.c_str());
    if (status != STATUS_OK) {
        // Same reasoning as the vibrator: stay down with the reason in the
        // log rather than crash-loop under init.
        LOG(ERROR) << "cannot register " << instance << ": status " << status;
        return EXIT_FAILURE;
    }
    LOG(INFO) << "registered " << instance;

    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;  // not reached
}
