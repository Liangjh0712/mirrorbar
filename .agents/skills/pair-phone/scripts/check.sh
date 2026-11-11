#!/bin/bash
# Read-only pairing check for Mirrorbar. Prints key=value lines; changes nothing
# except starting the adb server if it is not running.
# Usage: check.sh [serial]

say() { printf '%s=%s\n' "$1" "$2"; }

# --- adb: the same one Mirrorbar uses, so the two never fight over the server.
pick_adb() {
  local pref
  pref=$(defaults read io.github.liangjh0712.mirrorbar adbPath 2>/dev/null)
  for c in "$ADB" "$pref" "$HOME/Library/Android/sdk/platform-tools/adb" \
           "/opt/homebrew/bin/adb" "/usr/local/bin/adb" "$(command -v adb 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return; }
  done
}
ADB_BIN=$(pick_adb)
say adb "${ADB_BIN:-missing}"
[ -z "$ADB_BIN" ] && { say next "install_adb"; exit 0; }
ver() { "$1" version 2>/dev/null | sed -n 's/^Version \([^ -]*\).*/\1/p'; }
say adb_version "$(ver "$ADB_BIN")"

# Every adb on PATH with its version: two different versions restart each other's server.
others=""
for c in /opt/homebrew/bin/adb /usr/local/bin/adb "$HOME/Library/Android/sdk/platform-tools/adb"; do
  [ -x "$c" ] && [ "$c" != "$ADB_BIN" ] && others="$others $c($(ver "$c"))"
done
say other_adbs "${others# }"

say scrcpy "$(command -v scrcpy 2>/dev/null || echo missing)"
[ -d "$HOME/Applications/Mirrorbar.app" ] || [ -d "/Applications/Mirrorbar.app" ] \
  && say mirrorbar_installed yes || say mirrorbar_installed no
pgrep -x Mirrorbar >/dev/null && say mirrorbar_running yes || say mirrorbar_running no
say known_ips "$(defaults read io.github.liangjh0712.mirrorbar knownIPs 2>/dev/null | tr -d ' \n' )"

# --- devices
"$ADB_BIN" start-server >/dev/null 2>&1
list=$("$ADB_BIN" devices -l 2>/dev/null | tail -n +2 | grep -v '^\s*$')
if [ -z "$list" ]; then
  say devices none
  # Is anything Android-like on USB at all? (cable / USB mode problems vs. debugging off)
  usb=$(system_profiler SPUSBHostDataType SPUSBDataType 2>/dev/null \
        | grep -iE 'xiaomi|redmi|samsung|huawei|honor|oppo|vivo|oneplus|realme|google|pixel|android|motorola|sony|meizu|nothing' \
        | head -3 | sed 's/^ *//' | tr '\n' ';')
  say usb_android_seen "${usb:-none}"
  say next "enable_usb_debugging"
  exit 0
fi
i=0
echo "$list" | while read -r serial state rest; do
  i=$((i+1))
  model=$(echo "$rest" | tr ' ' '\n' | grep '^model:' | cut -d: -f2)
  say "device_$i" "$serial state=$state model=${model:-?}"
done

serial="$1"
[ -z "$serial" ] && serial=$(echo "$list" | awk '$2=="device" && $1 !~ /:/ {print $1; exit}')
[ -z "$serial" ] && serial=$(echo "$list" | awk '$2=="device" {print $1; exit}')
if [ -z "$serial" ]; then
  state=$(echo "$list" | awk 'NR==1 {print $2}')
  say next "$([ "$state" = unauthorized ] && echo authorize_on_phone || echo reconnect)"
  exit 0
fi
say serial "$serial"

sh() { "$ADB_BIN" -s "$serial" shell "$@" 2>&1 | tr -d '\r'; }
say manufacturer "$(sh getprop ro.product.manufacturer)"
say model "$(sh getprop ro.product.model)"
say android "$(sh getprop ro.build.version.release)"
say rom "$(sh getprop ro.build.version.incremental)"
say screen "$(sh wm size | tail -1 | awk '{print $NF}')"

# Can we send touches / keys? KEYCODE_UNKNOWN (0) does nothing on the phone.
inject=$(sh input keyevent 0)
if echo "$inject" | grep -qi 'securityexception\|INJECT_EVENTS'; then
  say control blocked
else
  say control ok
fi

say wifi_ip "$(sh ip -f inet addr show wlan0 | awk '/inet /{print $2}' | cut -d/ -f1)"
say tcp_port "$(sh getprop service.adb.tcp.port)"
say tls_port "$(sh getprop service.adb.tls.port)"
say locked "$(sh dumpsys window | grep -m1 -oE 'mDreamingLockscreen=(true|false)|isKeyguardShowing=(true|false)' )"

if echo "$inject" | grep -qi 'securityexception\|INJECT_EVENTS'; then
  say next "enable_control_permission"
else
  say next "ready"
fi
