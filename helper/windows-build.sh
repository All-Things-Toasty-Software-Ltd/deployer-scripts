#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SECRETS_DIR="/opt/toasty-deployer/secrets"

source "$SECRETS_DIR/windows-builder.env"

WINDOWS_SCRIPT="$SCRIPT_DIR/windows-build.ps1"

OWNER="$1"
REPOSITORY="$2"
ARTIFACT_DIR="$3"

if [[ -z "$OWNER" || -z "$REPOSITORY" ]]; then
    echo "Usage: $0 <owner> <repository>"
    exit 1
fi

if [[ ! -d "$ARTIFACT_DIR" ]]; then
    echo "ERROR: Artifact directory does not exist:"
    echo "  $ARTIFACT_DIR"
    exit 1
fi

REMOTE_ROOT="C:/ToastyBuild/_incoming"
REMOTE_SCRIPT="$REMOTE_ROOT/windows-build.ps1"

mkdir -p "$ARTIFACT_DIR"

echo "Temporary artifact directory: $ARTIFACT_DIR"

echo "========================================"
echo "Windows Build"
echo "========================================"
echo "Repository: $OWNER/$REPOSITORY"
echo "Windows:    $WINDOWS_HOST"
echo "========================================"

# Upload build script

echo "Uploading build script..."

sshpass -p "$WINDOWS_PASSWORD" ssh \
    -o StrictHostKeyChecking=accept-new \
    "$WINDOWS_USER@$WINDOWS_HOST" \
    "powershell.exe -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '$REMOTE_ROOT' | Out-Null\""

sshpass -p "$WINDOWS_PASSWORD" scp \
    -o StrictHostKeyChecking=accept-new \
    "$WINDOWS_SCRIPT" \
    "$WINDOWS_USER@$WINDOWS_HOST:$REMOTE_SCRIPT"

# Upload signing files

echo "Uploading signing files..."

sshpass -p "$WINDOWS_PASSWORD" scp \
    -o StrictHostKeyChecking=accept-new \
    "$SECRETS_DIR/android-release.jks" \
    "$WINDOWS_USER@$WINDOWS_HOST:$REMOTE_ROOT/android-release.jks"

sshpass -p "$WINDOWS_PASSWORD" scp \
    -o StrictHostKeyChecking=accept-new \
    "$SECRETS_DIR/msix-signing.pfx" \
    "$WINDOWS_USER@$WINDOWS_HOST:$REMOTE_ROOT/msix-signing.pfx"

# Prepare remote artifact directory

REMOTE_ARTIFACTS="$REMOTE_ROOT/artifacts"

sshpass -p "$WINDOWS_PASSWORD" ssh \
    -o StrictHostKeyChecking=accept-new \
    "$WINDOWS_USER@$WINDOWS_HOST" \
    "powershell.exe -NoProfile -Command \"Remove-Item -Recurse -Force '$REMOTE_ARTIFACTS' -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path '$REMOTE_ARTIFACTS' | Out-Null\""

# Execute build

echo "Starting Windows build..."

sshpass -p "$WINDOWS_PASSWORD" ssh \
    -o StrictHostKeyChecking=accept-new \
    "$WINDOWS_USER@$WINDOWS_HOST" \
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $REMOTE_SCRIPT \
        -Owner $OWNER \
        -Repository $REPOSITORY \
        -Branch main \
        -GithubToken $GITHUB_TOKEN \
        -KeystorePath $REMOTE_ROOT/android-release.jks \
        -KeystorePassword $ANDROID_KEYSTORE_PASSWORD \
        -KeyAlias $ANDROID_KEY_ALIAS \
        -KeyPassword $ANDROID_KEY_PASSWORD \
        -MsixPfxPath $REMOTE_ROOT/msix-signing.pfx \
        -MsixPfxPassword $MSIX_PFX_PASSWORD \
        -ArtifactDirectory $REMOTE_ARTIFACTS"

# Download artifacts

echo "Downloading artifacts..."

sshpass -p "$WINDOWS_PASSWORD" scp \
    -o StrictHostKeyChecking=accept-new \
    "$WINDOWS_USER@$WINDOWS_HOST:$REMOTE_ARTIFACTS/bakers-archive.apk" \
    "$ARTIFACT_DIR"

sshpass -p "$WINDOWS_PASSWORD" scp \
    -o StrictHostKeyChecking=accept-new \
    "$WINDOWS_USER@$WINDOWS_HOST:$REMOTE_ARTIFACTS/bakers-archive.aab" \
    "$ARTIFACT_DIR"

sshpass -p "$WINDOWS_PASSWORD" scp \
    -o StrictHostKeyChecking=accept-new \
    "$WINDOWS_USER@$WINDOWS_HOST:$REMOTE_ARTIFACTS/bakers-archive.msix" \
    "$ARTIFACT_DIR/"

echo ""
echo "========================================"
echo "Artifacts received"
echo "========================================"
echo "Location: $ARTIFACT_DIR"
ls -lh "$ARTIFACT_DIR"
echo ""

# Cleanup Windows

echo "Cleaning temporary Windows files..."

sshpass -p "$WINDOWS_PASSWORD" ssh \
    -o StrictHostKeyChecking=accept-new \
    "$WINDOWS_USER@$WINDOWS_HOST" \
    "powershell.exe -NoProfile -Command \"Remove-Item -Recurse -Force '$REMOTE_ROOT' -ErrorAction SilentlyContinue\""

echo "Windows build complete."