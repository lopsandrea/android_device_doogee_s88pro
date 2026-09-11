/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee.utils;

import android.util.Log;

import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;

/**
 * Reading and writing the device's sysfs nodes.
 *
 * An important note about writing: this phone's drivers parse the value with
 * sscanf and a trailing "\n" makes them fall back to zero. Writing "1\n" into
 * the LED's cfg node, for instance, still makes the driver load
 * aw22xxx_cfg_led_off.bin. The stock framework indeed writes without a
 * newline, and we do the same here.
 */
public final class FileUtils {

    private static final String TAG = "S88ProParts";

    private FileUtils() {
    }

    /** Writes the value without a newline. Returns false if the node is not writable. */
    public static boolean writeLine(String path, String value) {
        try (FileOutputStream out = new FileOutputStream(path)) {
            out.write(value.getBytes());
            return true;
        } catch (IOException e) {
            Log.e(TAG, "Write failed on " + path, e);
            return false;
        }
    }

    public static boolean writeLine(String path, int value) {
        return writeLine(path, Integer.toString(value));
    }

    public static String readLine(String path) {
        try (RandomAccessFile file = new RandomAccessFile(path, "r")) {
            return file.readLine();
        } catch (IOException e) {
            return null;
        }
    }

    public static boolean isAccessible(String path) {
        return new java.io.File(path).exists();
    }
}
