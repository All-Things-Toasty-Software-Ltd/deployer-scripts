#!/usr/bin/env bash

set -euo pipefail

# Configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HELPER_DIR="$BASE_DIR/helper"
SECRETS_DIR="/opt/toasty-deployer/secrets"

OWNER="All-Things-Toasty-Software-Ltd"
REPOSITORY="bakers-archive-mobile-companion"

ANDROID_ENV="$SECRETS_DIR/$REPOSITORY.env"
MSSTORE_ENV="$SECRETS_DIR/msstore/msstore.env"

FORCE_RELEASE=false

# Arguments

if [[ "${1:-}" == "--release" ]]; then
    FORCE_RELEASE=true
elif [[ $# -gt 0 ]]; then
    echo "Usage: $0 [--release]"
    exit 1
fi

# Temporary directories

TEMP_DIR="$(mktemp -d /tmp/toasty-build.XXXXXX)"

REPOSITORY_DIR="$TEMP_DIR/repository/$OWNER/$REPOSITORY"
ARTIFACT_DIR="$TEMP_DIR/artifacts"

cleanup() {
    echo ""
    echo "Cleaning temporary build files..."
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

mkdir -p "$ARTIFACT_DIR"

# Header

echo ""
echo "========================================"
echo "Toasty Build"
echo "========================================"
echo "Repository: $OWNER/$REPOSITORY"
echo "========================================"

# Clone repository

echo ""
echo "Cloning repository..."

"$HELPER_DIR/clone-repository.sh" \
    "$OWNER" \
    "$REPOSITORY" \
    "$REPOSITORY_DIR"

# Build

echo ""
echo "Building application..."

"$HELPER_DIR/windows-build.sh" \
    "$OWNER" \
    "$REPOSITORY" \
    "$ARTIFACT_DIR"

# Verify artifacts

echo ""
echo "========================================"
echo "Build Artifacts"
echo "========================================"

for FILE in \
    "bakers-archive.apk" \
    "bakers-archive.aab" \
    "bakers-archive.msix"
do
    if [[ ! -f "$ARTIFACT_DIR/$FILE" ]]; then
        echo "ERROR: Missing artifact:"
        echo "  $ARTIFACT_DIR/$FILE"
        exit 1
    fi

    ls -lh "$ARTIFACT_DIR/$FILE"
done

# Version check

echo ""
echo "========================================"
echo "Checking Release Version"
echo "========================================"

VERSION_OUTPUT="$(
    "$HELPER_DIR/version-check.sh" \
        "$REPOSITORY_DIR"
)"

echo "$VERSION_OUTPUT"

eval "$(
    printf '%s\n' "$VERSION_OUTPUT" |
    grep -E '^(VERSION_CODE|VERSION_NAME|RELEASE_REQUIRED)='
)"

# Decide whether to release

if [[ "$FORCE_RELEASE" == "true" ]]; then
    RELEASE_REQUIRED=true

    echo ""
    echo "Manual release requested."
fi

if [[ "$RELEASE_REQUIRED" != "true" ]]; then
    echo ""
    echo "========================================"
    echo "BUILD COMPLETE"
    echo "========================================"
    echo "Version:     $VERSION_NAME"
    echo "VersionCode: $VERSION_CODE"
    echo ""
    echo "VersionCode has not changed."
    echo "Build completed, but no release will be created."
    echo "========================================"

    exit 0
fi

# Release notes

RELEASE_NOTES="$REPOSITORY_DIR/releaseNotes.md"

if [[ ! -f "$RELEASE_NOTES" ]]; then
    echo "ERROR: releaseNotes.md does not exist:"
    echo "  $RELEASE_NOTES"
    exit 1
fi

if [[ ! -s "$RELEASE_NOTES" ]]; then
    echo "ERROR: releaseNotes.md is empty:"
    echo "  $RELEASE_NOTES"
    exit 1
fi

echo ""
echo "========================================"
echo "Preparing Release"
echo "========================================"
echo "Version:     $VERSION_NAME"
echo "VersionCode: $VERSION_CODE"
echo "========================================"

# Load application configuration

if [[ ! -f "$ANDROID_ENV" ]]; then
    echo "ERROR: Application environment file does not exist:"
    echo "  $ANDROID_ENV"
    exit 1
fi

source "$ANDROID_ENV"

: "${PLAY_SERVICE_ACCOUNT:?PLAY_SERVICE_ACCOUNT is not set}"
: "${PLAY_PACKAGE_NAME:?PLAY_PACKAGE_NAME is not set}"
: "${PLAY_TRACK:?PLAY_TRACK is not set}"

# GitHub Release

echo ""
echo "Creating GitHub release..."

"$HELPER_DIR/github-release.sh" \
    "$OWNER" \
    "$REPOSITORY" \
    "$VERSION_NAME" \
    "$ARTIFACT_DIR" \
    "$RELEASE_NOTES" \
    "bakers-archive.apk" \
    "bakers-archive.msix"

# Google Play

echo ""
echo "Publishing to Google Play..."

"$HELPER_DIR/google-play-release.py" \
    --service-account "$PLAY_SERVICE_ACCOUNT" \
    --package "$PLAY_PACKAGE_NAME" \
    --aab "$ARTIFACT_DIR/bakers-archive.aab" \
    --track "$PLAY_TRACK" \
    --version-name "$VERSION_NAME" \
    --release-notes "$RELEASE_NOTES"

# Microsoft Store

echo ""
echo "Publishing to Microsoft Store..."

"$HELPER_DIR/microsoft-store-release.sh" \
    "$MSSTORE_ENV" \
    "$ARTIFACT_DIR/bakers-archive.msix"

# Complete

echo ""
echo "========================================"
echo "RELEASE COMPLETE"
echo "========================================"
echo "Repository:  $OWNER/$REPOSITORY"
echo "Version:     $VERSION_NAME"
echo "VersionCode: $VERSION_CODE"
echo "========================================"