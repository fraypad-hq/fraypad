#!/usr/bin/env bash
# Provision the Android toolchain that Fraypad's Godot export needs.
#
# This sets up, under the SDK root:
#   cmdline-tools/   sdkmanager + avdmanager
#   build-tools/     aapt2, zipalign, apksigner   <- the usual missing piece
#   platforms/       android-XX framework jar
#   platform-tools/  adb, fastboot
#   ndk/             for cargo-ndk cross-compiling the Rust client
# and, in ~/.android, a debug keystore, plus the Godot export templates.
#
# Safe to re-run: every step checks whether its target already exists.
#
# Environment overrides:
#   ANDROID_SDK_ROOT   where to install (default: ~/android)
#   ANDROID_API        platform + build-tools API level (default: 36)
#   ANDROID_BUILD_TOOLS  build-tools revision (default: 36.0.0)
#   ANDROID_NDK        NDK version (default: 28.2.13676358)
#   GODOT_BIN          godot executable (default: godot)
#   SKIP_TEMPLATES=1   skip the ~1.2 GB export-template download
set -euo pipefail

SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android}"
API="${ANDROID_API:-36}"
BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-36.0.0}"
NDK="${ANDROID_NDK:-28.2.13676358}"
GODOT_BIN="${GODOT_BIN:-godot}"
# Pin to the official cmdline-tools build this script was tested against.
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# sdkmanager needs a JDK, so check for one before invoking it at all.
command -v keytool >/dev/null || die "keytool not found; install a JDK (e.g. openjdk-21-jdk or temurin)"

# ── cmdline-tools ────────────────────────────────────────────────────────────
SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [[ -x "$SDKMANAGER" ]]; then
    log "cmdline-tools already present"
else
    log "installing cmdline-tools into $SDK_ROOT"
    command -v curl >/dev/null || die "curl is required"
    command -v unzip >/dev/null || die "unzip is required"
    mkdir -p "$SDK_ROOT"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fL -o "$tmp/tools.zip" "$CMDLINE_TOOLS_URL"
    unzip -q "$tmp/tools.zip" -d "$tmp"
    # sdkmanager expects to live at <root>/cmdline-tools/latest/bin.
    mkdir -p "$SDK_ROOT/cmdline-tools"
    rm -rf "$SDK_ROOT/cmdline-tools/latest"
    mv "$tmp/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"
    # Info-ZIP may not restore exec bits; without this every rerun would
    # re-download because the -x test above keeps failing.
    find "$SDK_ROOT/cmdline-tools/latest/bin" -type f -exec chmod +x {} +
    "$SDKMANAGER" --version >/dev/null 2>&1 \
        || die "cmdline-tools installed but sdkmanager does not run"
fi

export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"

# ── licenses ─────────────────────────────────────────────────────────────────
log "accepting SDK licenses"
# sdkmanager exits non-zero on EOF before every license is accepted, so feed it
# "yes" and retry until the local repository reports them all accepted. Probe
# to a file so `grep -q` closing the pipe can't SIGPIPE sdkmanager into a false
# negative under pipefail.
licenses_ok=0
for _ in 1 2 3 4 5; do
    yes | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >/dev/null 2>&1 || true
    "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >"$SDK_ROOT/.licenses.log" 2>&1 || true
    if grep -q "All SDK package licenses accepted" "$SDK_ROOT/.licenses.log"; then
        licenses_ok=1
        break
    fi
done
rm -f "$SDK_ROOT/.licenses.log"
[[ "$licenses_ok" == "1" ]] || die "could not accept all SDK licenses"

# ── packages ─────────────────────────────────────────────────────────────────
log "installing platform-tools, platforms;android-$API, build-tools;$BUILD_TOOLS"
"$SDKMANAGER" --sdk_root="$SDK_ROOT" \
    "platform-tools" \
    "platforms;android-$API" \
    "build-tools;$BUILD_TOOLS" >/dev/null

if [[ -d "$SDK_ROOT/ndk/$NDK" ]]; then
    log "NDK $NDK already present"
else
    log "installing NDK $NDK"
    "$SDKMANAGER" --sdk_root="$SDK_ROOT" "ndk;$NDK" >/dev/null
fi

# ── debug keystore ───────────────────────────────────────────────────────────
KEYSTORE="$HOME/.android/debug.keystore"
if [[ -f "$KEYSTORE" ]]; then
    log "debug keystore already present"
else
    log "generating debug keystore at $KEYSTORE"
    mkdir -p "$HOME/.android"
    keytool -genkeypair \
        -keystore "$KEYSTORE" -storepass android -keypass android \
        -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10990 \
        -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

# ── Godot export templates ───────────────────────────────────────────────────
if [[ "${SKIP_TEMPLATES:-0}" == "1" ]]; then
    log "skipping export templates (SKIP_TEMPLATES=1)"
elif ! command -v "$GODOT_BIN" >/dev/null; then
    warn "godot not on PATH; skipping export templates"
else
    # e.g. "4.7.2.stable.arch_linux" -> "4.7.2.stable"
    version="$("$GODOT_BIN" --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.stable' || true)"
    if [[ -z "$version" ]]; then
        warn "could not parse godot version; skipping export templates"
    else
        TPL_DIR="$HOME/.local/share/godot/export_templates/$version"
        if [[ -f "$TPL_DIR/android_debug.apk" && -f "$TPL_DIR/android_release.apk" ]]; then
            log "export templates for $version already present"
        else
            log "downloading export templates for $version (~1.2 GB)"
            command -v curl >/dev/null || die "curl is required"
            mkdir -p "$TPL_DIR"
            tmp="$(mktemp -d)"
            trap 'rm -rf "$tmp"' EXIT
            # Godot tags releases with a dash ("4.7.2-stable"), while the
            # version string the binary prints uses a dot ("4.7.2.stable").
            tag="${version/.stable/-stable}"
            curl -fL -o "$tmp/templates.tpz" \
                "https://github.com/godotengine/godot/releases/download/${tag}/Godot_v${tag}_export_templates.tpz"
            # The tpz is a zip; we only need the two Android APKs.
            unzip -q -o -j "$tmp/templates.tpz" \
                "templates/android_debug.apk" \
                "templates/android_release.apk" \
                "templates/version.txt" -d "$TPL_DIR"
            rm -rf "$tmp"
            trap - EXIT
            log "export templates installed to $TPL_DIR"
        fi
    fi
fi

# ── summary ──────────────────────────────────────────────────────────────────
log "done. Android SDK root: $SDK_ROOT"
JAVA_HOME_GUESS="$(dirname "$(dirname "$(command -v keytool)")")"
cat <<EOF

Point Godot at the SDK (Editor Settings -> Export -> Android):
  Android SDK Path : $SDK_ROOT
  Java SDK Path    : $JAVA_HOME_GUESS

Then build with:  ./scripts/build-android.sh
EOF
