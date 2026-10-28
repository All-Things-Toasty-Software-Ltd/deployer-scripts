#!/usr/bin/env bash

# Part of Toasty Deployer. See LICENSE file for full copyright and licensing details.

set -euo pipefail

# Directory where the scripts are located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HELPER_DIR="$BASE_DIR/helper"

OWNER="AustinATTS"
REPOSITORY="the-toasty-book-of-bread"
DEFAULT_BRANCH="main"

REF="${1:-$DEFAULT_BRANCH}"

DEPLOY_ROOT="/opt/deployments"
TARGET_DIR="$DEPLOY_ROOT/$REPOSITORY"

# Ensure the root deployment directory exists
mkdir -p "$DEPLOY_ROOT"

echo "========================================"
echo "Starting Excerpt Deployment"
echo "========================================"
echo "Repository: $OWNER/$REPOSITORY"
echo "Ref/Branch: $REF"
echo "Target Dir: $TARGET_DIR"
echo "========================================"

# Clone or Update Repository
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Directory does not exist. Calling clone helper..."
    "$HELPER_DIR/clone.sh" "$OWNER" "$REPOSITORY" "$TARGET_DIR"

    cd "$TARGET_DIR"
    git checkout "$REF"
else
    echo "Directory exists. Updating repository..."
    cd "$TARGET_DIR"
    git fetch --no-tags origin
    git checkout "$REF"
    git pull origin "$REF"
fi

# Run LaTeX compilation
echo ""
echo "Building LaTeX excerpt..."

if make excerpt; then
    echo ""
    echo "========================================"
    echo "SUCCESS: Excerpt build completed!"
    echo "PDF location: $TARGET_DIR/build/excerpt/connections-excerpt.pdf"
    echo "========================================"
    exit 0
else
    echo ""
    echo "========================================"
    echo "FAILURE: LaTeX build failed during 'make excerpt'."
    echo "========================================"
    exit 1
fi