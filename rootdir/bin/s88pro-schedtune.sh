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
# How much later depends on the version, and there is no window that always
# works. Two attempts at guessing one both failed on 23.2: five seconds, then
# "hold for three consecutive checks over five minutes". Each time the boost was
# found back at zero on a booted phone, with the service already stopped and
# prefer_idle still set -- the signature of a write undone after the loop ended.
#
# Measured with root: set by hand at any point after boot, the value stays put
# indefinitely. So whatever resets it acts in a window near the end of boot
# whose length is not predictable, and a loop that exits can always exit too
# early.
#
# So it does not exit. It reapplies every thirty seconds for as long as the
# phone is up, which costs a shell waking twice a minute and removes the guess
# entirely. The loop must stay in the foreground: the service is not oneshot, so
# if this script returned init would restart it and stack one more loop on every
# round.

sleep 5

# The rest of the foreground: no boost, but idle cores all the same. Raising
# this one too is pointless, SystemUI is already in top-app.
echo 0 > /dev/stune/foreground/schedtune.boost
echo 1 > /dev/stune/foreground/schedtune.prefer_idle

echo 0 > /dev/stune/rt/schedtune.boost
echo 1 > /dev/stune/rt/schedtune.prefer_idle

while true; do
    if [ "$(cat /dev/stune/top-app/schedtune.boost)" != "10" ]; then
        echo 10 > /dev/stune/top-app/schedtune.boost
        echo 1  > /dev/stune/top-app/schedtune.prefer_idle
        log -t s88pro-schedtune "reapplied top-app boost=10 prefer_idle=1"
    fi
    sleep 30
done
