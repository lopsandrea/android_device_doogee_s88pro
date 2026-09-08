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
 * Lettura e scrittura dei nodi sysfs del device.
 *
 * Nota importante sulla scrittura: i driver di questo telefono analizzano il
 * valore con sscanf e il "\n" finale li fa ricadere sul valore zero. Scrivendo
 * "1\n" nel nodo cfg del LED, per esempio, il driver carica comunque
 * aw22xxx_cfg_led_off.bin. Il framework di fabbrica scrive infatti senza
 * andare a capo, e qui si fa lo stesso.
 */
public final class FileUtils {

    private static final String TAG = "S88ProParts";

    private FileUtils() {
    }

    /** Scrive il valore senza newline. Ritorna false se il nodo non è scrivibile. */
    public static boolean writeLine(String path, String value) {
        try (FileOutputStream out = new FileOutputStream(path)) {
            out.write(value.getBytes());
            return true;
        } catch (IOException e) {
            Log.e(TAG, "Scrittura fallita su " + path, e);
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
