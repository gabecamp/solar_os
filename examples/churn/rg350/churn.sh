#!/bin/sh
# Starts The Churn and keeps a log of what happened (churn_log.txt, on the SD
# card and in the home folder), so a game that won't open says why.
cd "$(dirname "$0")" || exit 1
LOG=/tmp/churn_log.txt
{
    echo "== The Churn, $(date) =="
    uname -a
    echo "-- libc:"
    ls -l /lib/ld-uClibc* /lib/libc.so* /lib/ld-musl* /usr/lib/libSDL* 2>&1
    echo "-- program:"
    ls -l ./churn_sdl
    echo "-- run:"
    ./churn_sdl "$@"
    rc=$?
    echo "exit code $rc"
    if [ $rc -ge 126 ] && [ $rc -le 127 ] && [ -e /lib/ld-uClibc.so.1 ]; then
        echo "-- again, through /lib/ld-uClibc.so.1:"
        /lib/ld-uClibc.so.1 ./churn_sdl "$@"
        echo "exit code $?"
    fi
} > "$LOG" 2>&1
for d in /media/sdcard /media/data /media/home "$HOME" /mnt; do
    [ -d "$d" ] && [ -w "$d" ] && cp "$LOG" "$d/churn_log.txt" 2>/dev/null
done
