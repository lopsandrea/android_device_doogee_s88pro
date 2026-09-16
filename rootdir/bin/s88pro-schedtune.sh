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
# holds.
#
# "Holds" used to mean "survived one five second wait", and on 23.2 that is not
# enough: the boost was found back at zero on a booted phone, with the service
# already stopped and prefer_idle still set -- the signature of a write that
# stuck just long enough to end the loop and was undone afterwards. Measured
# with root on a running phone: set by hand at any point after boot the value
# stays put indefinitely, so whatever resets it acts only in a window near the
# end of boot, and the loop simply has to outlive that window.
#
# So: reapply every ten seconds for up to five minutes, and only stop once the
# value has held three checks in a row. The cost is a shell asleep for a few
# minutes on a phone that has finished booting.

sleep 5

# The apps the user is looking at: higher frequency and a preference for idle
# cores. These are the values AOSP used up to Android 11.
tenuto=0
for _ in $(seq 1 30); do
    if [ "$(cat /dev/stune/top-app/schedtune.boost)" = "10" ]; then
        tenuto=$((tenuto + 1))
        [ "$tenuto" -ge 3 ] && break
    else
        tenuto=0
        echo 10 > /dev/stune/top-app/schedtune.boost
        echo 1  > /dev/stune/top-app/schedtune.prefer_idle
    fi
    sleep 10
done

# The rest of the foreground: no boost, but idle cores all the same. Raising
# this one too is pointless, SystemUI is already in top-app.
echo 0 > /dev/stune/foreground/schedtune.boost
echo 1 > /dev/stune/foreground/schedtune.prefer_idle

echo 0 > /dev/stune/rt/schedtune.boost
echo 1 > /dev/stune/rt/schedtune.prefer_idle

log -t s88pro-schedtune "top-app boost=$(cat /dev/stune/top-app/schedtune.boost) prefer_idle=$(cat /dev/stune/top-app/schedtune.prefer_idle)"
