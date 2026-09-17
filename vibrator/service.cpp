/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "vibrator-s88pro"

#include "Vibrator.h"

#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

using ::aidl::android::hardware::vibrator::Vibrator;

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(0);

    std::shared_ptr<Vibrator> vibrator = ndk::SharedRefBase::make<Vibrator>();
    const std::string instance = std::string(Vibrator::descriptor) + "/default";

    binder_status_t status =
            AServiceManager_addService(vibrator->asBinder().get(), instance.c_str());
    if (status != STATUS_OK) {
        /* Do not abort. init would restart us and the crash loop would bury
         * whatever the real complaint was; this way the reason stays in the
         * log and the process sticks around to be inspected.
         */
        LOG(ERROR) << "cannot register " << instance << ": status " << status;
        return EXIT_FAILURE;
    }
    LOG(INFO) << "registered " << instance;

    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;  // not reached
}
