#!/usr/bin/env bash
# Reproduce the "tap anything -> crash" report and capture the exact reason.
#
# Usage: ./scripts/repro-crash.sh
#
# Assumes a device is connected via adb and (optionally) the Fraypad server is
# running on the LAN. Taps several real control positions in the landscape
# viewport and reports the crash trace if the app dies.
set -u

PKG=com.fraypad.app
LOG=/tmp/opencode/crash.log

echo "== device =="
adb devices -l | tail -n +2

# Landscape viewport: wm size reports portrait; the game runs landscape.
RAW=$(adb shell wm size | sed -E 's/.*: //')
PH=$(echo "$RAW" | cut -dx -f1)
PW=$(echo "$RAW" | cut -dx -f2)
echo "reported size: ${PH}x${PW} (portrait) -> landscape ${PW}x${PH}"

adb shell am force-stop "$PKG"
sleep 1
adb logcat -c
adb logcat > "$LOG" 2>&1 &
LOGPID=$!
sleep 1

adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5

if [ -z "$(adb shell pidof "$PKG")" ]; then
  echo "!! app is not running after launch"
fi

# Landscape coordinates. The pad is 1.8-ish ratio fitted to the width, so in
# landscape the canvas is PW wide and (PW/1.8..) tall, centred vertically.
# Probe the middle of the left stick, right stick, A button and D-pad.
PADH=$(( PW * 100 / 180 ))
TOP=$(( (PH - PADH) / 2 ))
probe() { # name x y
  local name=$1 x=$2 y=$3
  adb shell input tap "$x" "$(( y + TOP ))"
  sleep 1
  local p
  p=$(adb shell pidof "$PKG")
  if [ -z "$p" ]; then
    echo "CRASH on $name (tap $x,$y)"
    return 1
  fi
  echo "ok $name (tap $x,$y) pid=$p"
  return 0
}

probe "left-stick"  $(( PW * 10 / 100 )) $(( PADH * 88 / 100 )) || true
probe "dpad-up"     $(( PADH *  44 / 100 )) $(( PADH * 38 / 100 )) || true
probe "btn-A"       $(( PW - PADH * 46 / 100 )) $(( PADH * 60 / 100 )) || true
probe "right-stick" $(( PW - PADH * 10 / 100 )) $(( PADH * 88 / 100 )) || true
probe "mode-button" $(( PW / 2 )) $(( PADH * 92 / 100 )) || true

sleep 2
kill $LOGPID 2>/dev/null
wait $LOGPID 2>/dev/null

echo "== godot / crash output =="
grep -iE "godot|FATAL|AndroidRuntime|SIGSEGV|SIGABRT|signal [0-9]|backtrace|libclient|gdext" "$LOG" \
  | grep -vE "V-Sync|mali_platform|BufferQueue|granted|loaded" | tail -50
echo "== end =="
