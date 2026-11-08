#!/usr/bin/env bash
# Example deployment script repository update: PUBLIC source repository.
#
# This example demonstrates how a deployment script repository maintains itself.
#
# IMPORTANT: Toasty Deployer is ONLY responsible for receiving webhooks, identifying
# the repository and executing the appropriate deployment script. It is NOT
# responsible for managing, updating, cloning or synchronising deployment script
# repositories. The deployment scripts themselves are responsible for maintaining
# their own repositories and pushing updated scripts out to the deployment
# directories.
#
# This script shows how an operator (or a scheduled job) can:
#   1. Update or clone the relevant Git repository.
#   2. Read the repository's scripts/ and helpers/ directories.
#   3. Copy scripts/ into the appropriate configured public/private destination.
#   4. Copy helpers/ into the shared deployment helpers directory.
#   5. Preserve file permissions where possible.
#   6. Handle missing directories and failed Git operations appropriately.

set -euo pipefail

SOURCE_REPO="${SOURCE_REPO:-https://github.com/All-Things-Toasty-Software-Ltd/deployer-scripts.git}"
SOURCE_ACCOUNT="${SOURCE_ACCOUNT:-All-Things-Toasty-Software-Ltd}"

DEST_ACCOUNT="${DEST_ACCOUNT:-toasty-software}"
DEST_VISIBILITY="public"
DEPLOY_ROOT="${DEPLOY_ROOT:-/repos}"

SOURCE_DIR="$(mktemp -d)"
trap 'rm -rf "${SOURCE_DIR}"' EXIT

if ! git clone "${SOURCE_REPO}" "${SOURCE_DIR}/source" >/dev/null 2>&1; then
    echo "ERROR: Failed to clone deployment script repository: ${SOURCE_REPO}" >&2
    exit 1
fi

SOURCE_SCRIPTS_DIR="${SOURCE_DIR}/source/scripts"
SOURCE_HELPERS_DIR="${SOURCE_DIR}/source/helpers"

if [ ! -d "${SOURCE_SCRIPTS_DIR}" ]; then
    echo "ERROR: Deployment script repository ${SOURCE_REPO} has no scripts/ directory." >&2
    exit 1
fi

TARGET_ROOT="${DEPLOY_ROOT}/${DEST_ACCOUNT}/${DEST_VISIBILITY}"
mkdir -p "${TARGET_ROOT}"

# Copy the contents of scripts/ directly into the deployment directory,
# without creating another scripts/ directory, preserving nested directories
# and file permissions.
cp -a "${SOURCE_SCRIPTS_DIR}/." "${TARGET_ROOT}/"

TARGET_HELPERS_DIR="${DEPLOY_ROOT}/helpers"
mkdir -p "${TARGET_HELPERS_DIR}"

if [ -d "${SOURCE_HELPERS_DIR}" ]; then
    cp -a "${SOURCE_HELPERS_DIR}/." "${TARGET_HELPERS_DIR}/"
fi

echo "Deployment scripts updated from ${SOURCE_REPO}"