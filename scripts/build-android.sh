#!/usr/bin/env bash
# Build the Android client and export the APK.
#
# 1. Cross-compiles crates/client_gdext to arm64 with cargo-ndk.
# 2. Exports the Godot project, packaging the freshly built .so.
# 3. Verifies the exported APK actually contains a non-empty libclient_gdext.so
#    (Godot will silently package a 0-byte placeholder if the lib is missing).
#
# Run scripts/setup-android.sh once first to provision the SDK/NDK.
#
# Environment overrides:
#   ANDROID_SDK_ROOT   SDK root (default: ~/android)
#   ANDROID_NDK_HOME   NDK dir (default: <sdk>/ndk/<ANDROID_NDK>)
#   ANDROID_NDK        NDK version (default: 28.2.13676358)
#   GODOT_BIN          godot executable (default: godot)
#   APK_OUT            output path (default: godot/export/fraypad-android.apk)
#   RELEASE=1          build/export release instead of debug
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android}"
NDK_VER="${ANDROID_NDK:-28.2.13676358}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$SDK_ROOT/ndk/$NDK_VER}"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
GODOT_BIN="${GODOT_BIN:-godot}"
APK_OUT="${APK_OUT:-$REPO_ROOT/godot/export/fraypad-android.apk}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$ANDROID_NDK_HOME" ]] || die "NDK not found at $ANDROID_NDK_HOME — run scripts/setup-android.sh"
command -v cargo-ndk >/dev/null 2>&1 || [[ -x "$(command -v cargo)" ]] || die "cargo not found"
"$GODOT_BIN" --version >/dev/null 2>&1 || die "godot not found (set GODOT_BIN)"

if [[ "${RELEASE:-0}" == "1" ]]; then
    PROFILE="--release"
    EXPORT_FLAG="--export-release"
else
    PROFILE=""
    EXPORT_FLAG="--export-debug"
fi

log "building client_gdext (aarch64-linux-android) $PROFILE"
(cd "$REPO_ROOT" && cargo ndk -t arm64-v8a build $PROFILE -p client_gdext)

SO_SRC="$REPO_ROOT/target/aarch64-linux-android/release/libclient_gdext.so"
[[ -s "$SO_SRC" ]] || die "built .so missing or empty at $SO_SRC"

mkdir -p "$(dirname "$APK_OUT")"
log "exporting APK -> $APK_OUT"
(cd "$REPO_ROOT/godot" && "$GODOT_BIN" --headless $EXPORT_FLAG "Android" "$APK_OUT")

[[ -s "$APK_OUT" ]] || die "export produced no APK"

# Godot packages a 0-byte placeholder when the native lib is absent. Fail loudly.
log "verifying APK contents"
if command -v unzip >/dev/null; then
    so_size="$(unzip -l "$APK_OUT" 'lib/arm64-v8a/libclient_gdext.so' 2>/dev/null \
        | awk '/libclient_gdext\.so/ {print $1; exit}')"
    [[ -n "$so_size" && "$so_size" -gt 1000000 ]] \
        || die "APK is missing a real libclient_gdext.so (reported size: '${so_size:-none}')"
    log "libclient_gdext.so packaged: $so_size bytes"
fi

log "done: $APK_OUT ($(du -h "$APK_OUT" | cut -f1))"
