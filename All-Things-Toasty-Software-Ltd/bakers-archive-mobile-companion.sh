#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HELPER_DIR="$(cd "$SCRIPT_DIR/../helper" && pwd)"

OWNER="All-Things-Toasty-Software-Ltd"
REPOSITORY="bakers-archive-mobile-companion"

echo "Building $OWNER/$REPOSITORY..."

"$HELPER_DIR/windows-build.sh" \
    "$OWNER" \
    "$REPOSITORY"

echo ""
echo "Build completed successfully."