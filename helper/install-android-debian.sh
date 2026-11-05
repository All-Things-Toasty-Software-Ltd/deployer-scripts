#!/usr/bin/env bash

set -euo pipefail

# Install the Linux toolchain required by the Baker's Archive Mobile Companion build.
#
# Run this once as root on the Debian LXC/container that runs Toasty Deployer.
#
# Environment overrides:
#   FLUTTER_ROOT   Flutter installation directory (default: /opt/flutter)
#   ANDROID_HOME   Android SDK installation directory (default: /opt/android-sdk)
#   DEPLOY_USER    User that owns the SDK directories if chown should be changed
#   ANDROID_PACKAGES Additional sdkmanager packages, space separated
#
# Example:
#   sudo DEPLOY_USER=toasty-deployer ./install-android-debian.sh

FLUTTER_ROOT="${FLUTTER_ROOT:-/opt/flutter}"
ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
DEPLOY_USER="${DEPLOY_USER:-root}"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root (for example with sudo)." >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: This helper currently supports Debian/Ubuntu systems only." >&2
    exit 1
fi

echo ""
echo "========================================"
echo "Installing build dependencies"
echo "========================================"

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    ca-certificates \
    curl \
    wget \
    openssl \
    git \
    unzip \
    xz-utils \
    zip \
    openjdk-21-jdk-headless \
    python3 \
    python3-pip \
    python3-venv \
    python3-google-api-python-client \
    python3-google-auth \
    libglu1-mesa

apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "========================================"
echo "Installing Flutter"
echo "========================================"

if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
    mkdir -p "$FLUTTER_ROOT"

    FLUTTER_URL="$(
        curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json |
            python3 -c 'import json,sys; d=json.load(sys.stdin); stable=d["current_release"]["stable"]; release=next(r for r in d["releases"] if r["hash"] == stable); print(d["base_url"] + "/" + release["archive"])'
    )"

    echo "Flutter URL: $FLUTTER_URL"

    FLUTTER_TARBALL="$(mktemp /tmp/flutter.XXXXXX.tar.xz)"

    curl -fL "$FLUTTER_URL" -o "$FLUTTER_TARBALL"
    tar -xJf "$FLUTTER_TARBALL" -C "$(dirname "$FLUTTER_ROOT")"
    rm -f "$FLUTTER_TARBALL"

    # The tarball extracts to ./flutter; move it onto FLUTTER_ROOT if needed.
    if [[ -d "$(dirname "$FLUTTER_ROOT")/flutter" && "$FLUTTER_ROOT" != "$(dirname "$FLUTTER_ROOT")/flutter" ]]; then
        rm -rf "$FLUTTER_ROOT"
        mv "$(dirname "$FLUTTER_ROOT")/flutter" "$FLUTTER_ROOT"
    fi
fi

if [[ "$DEPLOY_USER" != "root" ]]; then
    chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$FLUTTER_ROOT"
fi

FLUTTER_BIN="$FLUTTER_ROOT/bin/flutter"

echo ""
echo "Flutter: $FLUTTER_BIN"
"$FLUTTER_BIN" --version

echo ""
echo "========================================"
echo "Installing Android SDK command-line tools"
echo "========================================"

if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
    mkdir -p "$ANDROID_HOME/cmdline-tools"

    CMDLINE_TOOLS_FILE="$(
        curl -fsSL https://dl.google.com/android/repository/repository2-1.xml |
            grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' |
            sort -V |
            tail -n 1
    )"

    if [[ -z "$CMDLINE_TOOLS_FILE" ]]; then
        CMDLINE_TOOLS_FILE="commandlinetools-linux-11076708_latest.zip"
    fi

    CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/$CMDLINE_TOOLS_FILE"

    echo "Android command-line tools: $CMDLINE_TOOLS_URL"

    CMDLINE_TMP="$(mktemp -d /tmp/android-cmdline.XXXXXX)"

    curl -fL "$CMDLINE_TOOLS_URL" -o "$CMDLINE_TMP/cmdline-tools.zip"
    unzip -q "$CMDLINE_TMP/cmdline-tools.zip" -d "$CMDLINE_TMP"

    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$CMDLINE_TMP/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -rf "$CMDLINE_TMP"
fi

if [[ "$DEPLOY_USER" != "root" ]]; then
    chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$ANDROID_HOME"
fi

SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"

echo ""
echo "Installing Android SDK packages"

ANDROID_PACKAGES="${ANDROID_PACKAGES:-platform-tools platforms;android-37 build-tools;37.0.0}"

for PACKAGE in $ANDROID_PACKAGES; do
    "$SDKMANAGER" --install "$PACKAGE"
done

echo ""
echo "Accepting Android SDK licenses"
yes | "$SDKMANAGER" --licenses

SDKMANAGER_CACHE="$ANDROID_HOME/.temp"

if [[ -d "$SDKMANAGER_CACHE" ]]; then
    rm -rf "$SDKMANAGER_CACHE"
fi

echo ""
echo "========================================"
echo "Configuring shell/service defaults"
echo "========================================"

PROFILE_FILE="/etc/profile.d/toasty-android.sh"

cat > "$PROFILE_FILE" <<PROFILE
# Toasty Deployer Android/Flutter environment
export ANDROID_HOME=$ANDROID_HOME
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$FLUTTER_ROOT/bin:$FLUTTER_ROOT/bin/cache/dart-sdk/bin:\$PATH
PROFILE

chmod 0644 "$PROFILE_FILE"

mkdir -p /opt/toasty-deployer/secrets
chmod 0700 /opt/toasty-deployer/secrets

echo ""
echo "========================================"
echo "Flutter doctor"
echo "========================================"

"$FLUTTER_BIN" config --no-analytics
"$FLUTTER_BIN" doctor -v

echo ""
echo "========================================"
echo "System check"
echo "========================================"

python3 <<'PY'
import re
import shutil
import subprocess

meminfo = open("/proc/meminfo").read()
mem_mb = int(re.search(r"MemTotal:\s+(\d+)", meminfo).group(1)) // 1024
swap_mb = int(re.search(r"SwapTotal:\s+(\d+)", meminfo).group(1)) // 1024

print(f"Memory: {mem_mb} MiB")
print(f"Swap:   {swap_mb} MiB")

if mem_mb < 1800:
    print("WARNING: 1 GiB RAM is very tight for Flutter/Gradle; prefer at least 2 GiB RAM and 2 GiB swap.")

if swap_mb < 1000:
    print("WARNING: only ~512 MiB swap is configured; expect out-of-memory or very long builds without more swap.")

print(f"Disk free: {shutil.disk_usage('/').free // (1024 * 1024 * 1024)} GiB")

if shutil.disk_usage('/').free < 5 * 1024 * 1024 * 1024:
    print("WARNING: less than 5 GiB free; Flutter/Android SDK may fail to download or build.")
PY

echo ""
echo "========================================"
echo "Required secret files"
echo "========================================"
cat <<'SECRETS'
/opt/toasty-deployer/secrets/android-release.env
  ANDROID_KEYSTORE_PASSWORD=...
  ANDROID_KEY_ALIAS=...
  ANDROID_KEY_PASSWORD=...
  ANDROID_KEYSTORE_PATH=/opt/toasty-deployer/secrets/android-release.jks # optional
  PLAY_SERVICE_ACCOUNT=/opt/toasty-deployer/secrets/play-service-account.json
  PLAY_PACKAGE_NAME=uk.co.toastysoftware.bakers_archive
  PLAY_TRACK=production

/opt/toasty-deployer/secrets/gitlab.env
  GITLAB_HOST=git.toastysoftware.co.uk
  GITLAB_TOKEN=<token with api scope>
  GITLAB_PROJECT=toasty-software/bakers-archive-mobile-companion
  GITLAB_REF=main

/opt/toasty-deployer/secrets/github-app.env
  GITHUB_APP_ID=...
  GITHUB_PRIVATE_KEY=/opt/toasty-deployer/secrets/github-app.pem
  GITHUB_INSTALLATION_ID=...
SECRETS

echo ""
echo "Installation complete."
echo "If the deployer runs as a systemd service, restart it or reload its environment."
