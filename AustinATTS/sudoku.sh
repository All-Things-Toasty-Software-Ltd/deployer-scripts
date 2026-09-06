#!/usr/bin/env bash

set -euo pipefail

# Directory where the scripts are located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HELPER_DIR="$BASE_DIR/helper"

OWNER="AustinATTS"
REPOSITORY="sudoku"
MODULE="sudoku"
DATABASE="austinatts"
DEFAULT_BRANCH="19.0"

REF="${1:-$DEFAULT_BRANCH}"

echo "Starting deployment wrapper for $MODULE ($REF)..."

"$HELPER_DIR/odoo-deployment.sh" \
  "$OWNER" \
  "$REPOSITORY" \
  "$MODULE" \
  "$DATABASE" \
  "$REF"