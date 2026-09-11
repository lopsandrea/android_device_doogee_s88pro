#!/system/bin/sh
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# EAS boost for foreground apps. The why and the numbers are in the init file
# that starts this script: rootdir/etc/init/s88pro-schedtune.rc
#
# The wait is not a flourish: applied right after sys.boot_completed the values
# do not stick -- prefer_idle stays, boost goes back to zero -- while later on
# they do. Something in the last phase of boot resets them; once that is past,
# nobody touches them again.
#
# How much later depends on the version, though: on Android 12 five seconds was
# enough, on Android 13 it is not (the service wrote 10 and something put it
# back to zero). Rather than guessing a longer wait, we reapply until the value
# holds: we exit on the first round where it stayed.

sleep 5

# The apps the user is looking at: higher frequency and a preference for idle
# cores. These are the values AOSP used up to Android 11.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    echo 10 > /dev/stune/top-app/schedtune.boost
    echo 1  > /dev/stune/top-app/schedtune.prefer_idle
    sleep 5
    [ "$(cat /dev/stune/top-app/schedtune.boost)" = "10" ] && break
done

# The rest of the foreground: no boost, but idle cores all the same. Raising
# this one too is pointless, SystemUI is already in top-app.
echo 0 > /dev/stune/foreground/schedtune.boost
echo 1 > /dev/stune/foreground/schedtune.prefer_idle

echo 0 > /dev/stune/rt/schedtune.boost
echo 1 > /dev/stune/rt/schedtune.prefer_idle

log -t s88pro-schedtune "top-app boost=$(cat /dev/stune/top-app/schedtune.boost) prefer_idle=$(cat /dev/stune/top-app/schedtune.prefer_idle)"
