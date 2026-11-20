/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package com.mediatek.ims.config.internal;

/** Compile-time stand-in for the APK's class: only what S88ViLteGate calls. */
public class ImsConfigImpl {
    public void setFeatureValue(int feature, int network, int value,
            com.android.ims.ImsConfigListener listener) throws android.os.RemoteException {}
}
