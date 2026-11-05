#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="/opt/toasty-deployer/secrets"

REPOSITORY_DIR="$1"
ARTIFACT_DIR="$2"

if [[ -z "$REPOSITORY_DIR" || -z "$ARTIFACT_DIR" ]]; then
    echo "Usage: $0 <repository_dir> <artifact_dir>" >&2
    exit 1
fi

if [[ ! -d "$REPOSITORY_DIR" ]]; then
    echo "ERROR: Repository directory does not exist:" >&2
    echo "  $REPOSITORY_DIR" >&2
    exit 1
fi

cd "$REPOSITORY_DIR"

if [[ ! -f "pubspec.yaml" ]]; then
    echo "ERROR: $REPOSITORY_DIR is not a Flutter project (missing pubspec.yaml)." >&2
    exit 1
fi

mkdir -p "$ARTIFACT_DIR"

# Load signing configuration. Prefer the Linux-specific file, but retain a
# fallback for the existing deployer secret layout.

ANDROID_ENV="${ANDROID_ENV:-$SECRETS_DIR/android-release.env}"

if [[ -f "$ANDROID_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$ANDROID_ENV"
fi

: "${ANDROID_KEYSTORE_PASSWORD:?ANDROID_KEYSTORE_PASSWORD is not set}"
: "${ANDROID_KEY_ALIAS:?ANDROID_KEY_ALIAS is not set}"
: "${ANDROID_KEY_PASSWORD:?ANDROID_KEY_PASSWORD is not set}"

ANDROID_KEYSTORE_PATH="${ANDROID_KEYSTORE_PATH:-$SECRETS_DIR/android-release.jks}"

if [[ ! -f "$ANDROID_KEYSTORE_PATH" ]]; then
    echo "ERROR: Android release keystore does not exist:" >&2
    echo "  $ANDROID_KEYSTORE_PATH" >&2
    exit 1
fi

# Locate Flutter.

FLUTTER_CANDIDATES=(
    "${FLUTTER_SDK:-}"
    "/opt/flutter/bin/flutter"
    "/usr/local/flutter/bin/flutter"
    "/opt/android-sdk/flutter/bin/flutter"
    "/home/toasty/flutter/bin/flutter"
)

FLUTTER=""

if command -v flutter >/dev/null 2>&1; then
    FLUTTER="$(command -v flutter)"
fi

if [[ -z "$FLUTTER" ]]; then
    for CANDIDATE in "${FLUTTER_CANDIDATES[@]}"; do
        if [[ -x "$CANDIDATE" ]]; then
            FLUTTER="$CANDIDATE"
            break
        fi
    done
fi

if [[ -z "$FLUTTER" ]]; then
    echo "ERROR: Flutter SDK not found. Set FLUTTER_SDK or add flutter to PATH." >&2
    exit 1
fi

FLUTTER_VERSION="$($FLUTTER --version 2>&1 | head -n 1 || true)"
if [[ -z "$FLUTTER_VERSION" ]]; then
    echo "ERROR: Flutter did not report a version." >&2
    exit 1
fi

# Read the version fields from pubspec.yaml.

VERSION_FIELD="$(
    sed -nE 's/^[[:space:]]*version:[[:space:]]*"?([^"#[:space:]]+)"?.*$/\1/p' pubspec.yaml |
    head -n 1
)"

if [[ -z "$VERSION_FIELD" ]]; then
    echo "ERROR: Could not determine version from pubspec.yaml" >&2
    exit 1
fi

if [[ "$VERSION_FIELD" == *+* ]]; then
    VERSION_NAME="${VERSION_FIELD%%+*}"
    VERSION_CODE="${VERSION_FIELD##*+}"
else
    VERSION_NAME="$VERSION_FIELD"
    VERSION_CODE="0"
fi

if [[ ! "$VERSION_CODE" =~ ^[0-9]+$ ]]; then
    echo "ERROR: pubspec.yaml versionCode must be numeric: $VERSION_FIELD" >&2
    exit 1
fi

echo ""
echo "========================================"
echo "Android Build"
echo "========================================"
echo "Repository:  $REPOSITORY_DIR"
echo "Flutter:     $FLUTTER"
echo "Version:     $VERSION_NAME"
echo "VersionCode: $VERSION_CODE"
echo "========================================"

KEY_PROPERTIES="android/key.properties"

cleanup() {
    if [[ -f "$KEY_PROPERTIES" ]]; then
        rm -f "$KEY_PROPERTIES"
    fi
}

trap cleanup EXIT

# Write release signing properties for this build only.

cat > "$KEY_PROPERTIES" <<EOF
storeFile=$ANDROID_KEYSTORE_PATH
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
keyPassword=$ANDROID_KEY_PASSWORD
EOF

echo "Installing dependencies..."

"$FLUTTER" pub get

echo ""
echo "Building APK..."

"$FLUTTER" build apk --release \
    --build-name "$VERSION_NAME" \
    --build-number "$VERSION_CODE"

echo ""
echo "Building AAB..."

"$FLUTTER" build appbundle --release \
    --build-name "$VERSION_NAME" \
    --build-number "$VERSION_CODE"

# Locate the generated APK/AAB.

APK=""
AAB=""

while IFS= read -r -d '' FILE; do
    if [[ "$FILE" == *app-release.apk ]]; then
        APK="$FILE"
        break
    fi
done < <(find build/app/outputs -type f -name '*.apk' -print0)

if [[ -z "$APK" ]]; then
    APK="$(find build/app/outputs -type f -name '*.apk' | head -n 1)"
fi

while IFS= read -r -d '' FILE; do
    if [[ "$FILE" == *app-release.aab ]]; then
        AAB="$FILE"
        break
    fi
done < <(find build/app/outputs -type f -name '*.aab' -print0)

if [[ -z "$AAB" ]]; then
    AAB="$(find build/app/outputs -type f -name '*.aab' | head -n 1)"
fi

if [[ -z "$APK" ]]; then
    echo "ERROR: Could not find the generated APK." >&2
    exit 1
fi

if [[ -z "$AAB" ]]; then
    echo "ERROR: Could not find the generated AAB." >&2
    exit 1
fi

echo ""
echo "APK: $APK"
echo "AAB: $AAB"

# Verify the APK with apksigner when it is available.

APKSIGNER=""

if [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME/build-tools" ]]; then
    APKSIGNER="$(find "$ANDROID_HOME/build-tools" -name apksigner -type f | sort -V | tail -n 1)"
fi

if [[ -z "$APKSIGNER" ]] && [[ -n "${ANDROID_SDK_ROOT:-}" && -d "$ANDROID_SDK_ROOT/build-tools" ]]; then
    APKSIGNER="$(find "$ANDROID_SDK_ROOT/build-tools" -name apksigner -type f | sort -V | tail -n 1)"
fi

if [[ -n "$APKSIGNER" ]]; then
    echo ""
    echo "Verifying APK signature..."
    "$APKSIGNER" verify --verbose "$APK"
else
    echo ""
    echo "WARNING: apksigner not found; skipping APK signature verification."
fi

# Copy artifacts using stable deployer names.

cp "$APK" "$ARTIFACT_DIR/bakers-archive.apk"
cp "$AAB" "$ARTIFACT_DIR/bakers-archive.aab"

echo ""
echo "========================================"
echo "Android build complete"
echo "========================================"
ls -lh "$ARTIFACT_DIR/bakers-archive.apk"
ls -lh "$ARTIFACT_DIR/bakers-archive.aab"
