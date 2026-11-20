/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package com.mediatek.ims.config.internal;

import android.util.Log;

/**
 * Holds video over LTE back until a slot's IMS has registered.
 *
 * The modem decides whether to start IMS from the configuration it holds at
 * that moment, and with ViLTE in it (AT+EIMSCFG=1,1,...) it never asks for the
 * IMS PDN: the slot stays unregistered, voice included. Adding ViLTE to a
 * registration that already exists is fine, the modem re-registers with
 * video. So the framework's request for ViLTE is held back, and replayed once
 * the slot has registered; it is withdrawn again when registration goes, so
 * that the next one starts from voice alone.
 *
 * filter() runs first thing in ImsConfigImpl.setFeatureValue(), and
 * onRegistrationState() first thing in ImsService.updateImsRegstration().
 */
public final class S88ViLteGate {
    private static final String TAG = "S88ViLteGate";

    private static final int FEATURE_VILTE = 1;

    // ImsService's registration states
    private static final int REGISTERING = 1;
    private static final int REGISTERED = 2;
    private static final int DEREGISTERED = 3;

    private static final int MAX_PHONES = 4;

    private static final ImsConfigImpl[] sConfig = new ImsConfigImpl[MAX_PHONES];
    private static final int[] sNetwork = new int[MAX_PHONES];
    private static final boolean[] sWanted = new boolean[MAX_PHONES];
    private static final boolean[] sRegistered = new boolean[MAX_PHONES];

    // Set while this class itself calls setFeatureValue(), so that filter()
    // lets the call through untouched.
    private static final ThreadLocal<Boolean> sReplaying = new ThreadLocal<>();

    private S88ViLteGate() {}

    /** The value setFeatureValue() should apply. */
    static int filter(ImsConfigImpl config, int phoneId, int feature, int network, int value) {
        if (feature != FEATURE_VILTE || phoneId < 0 || phoneId >= MAX_PHONES
                || sReplaying.get() != null) {
            return value;
        }
        synchronized (S88ViLteGate.class) {
            sConfig[phoneId] = config;
            sNetwork[phoneId] = network;
            sWanted[phoneId] = value == 1;
            if (value == 1 && !sRegistered[phoneId]) {
                Log.d(TAG, "slot " + phoneId + ": ViLTE held back until IMS registers");
                return 0;
            }
            return value;
        }
    }

    public static void onRegistrationState(int phoneId, int state) {
        if (phoneId < 0 || phoneId >= MAX_PHONES) {
            return;
        }
        final boolean registered;
        if (state == REGISTERING || state == REGISTERED) {
            registered = true;
        } else if (state == DEREGISTERED) {
            registered = false;
        } else {
            return;
        }
        final ImsConfigImpl config;
        final int network;
        synchronized (S88ViLteGate.class) {
            if (sRegistered[phoneId] == registered) {
                return;
            }
            sRegistered[phoneId] = registered;
            if (!sWanted[phoneId] || sConfig[phoneId] == null) {
                return;
            }
            config = sConfig[phoneId];
            network = sNetwork[phoneId];
        }
        final int value = registered ? 1 : 0;
        Log.d(TAG, "slot " + phoneId + ": ViLTE " + (registered ? "on, IMS registered"
                : "held back, IMS deregistered"));
        sReplaying.set(Boolean.TRUE);
        try {
            config.setFeatureValue(FEATURE_VILTE, network, value, null);
        } catch (Exception e) {
            Log.e(TAG, "slot " + phoneId + ": setting ViLTE to " + value + " failed", e);
        } finally {
            sReplaying.remove();
        }
    }
}
