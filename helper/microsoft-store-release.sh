#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="$1"
MSIX="$2"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Store environment file does not exist:"
    echo "  $ENV_FILE"
    exit 1
fi

if [[ ! -f "$MSIX" ]]; then
    echo "ERROR: MSIX does not exist:"
    echo "  $MSIX"
    exit 1
fi

source "$ENV_FILE"

: "${STORE_PRODUCT_ID:?STORE_PRODUCT_ID is not set}"

echo ""
echo "========================================"
echo "Microsoft Store Release"
echo "========================================"
echo "Package: $MSIX"
echo "Product: $STORE_PRODUCT_ID"
echo "========================================"

echo ""
echo "Publishing MSIX..."

# The Microsoft Store CLI is already configured on the deployer.
# dbus-run-session gives it the D-Bus session required by the
# credential/keyring infrastructure when running headlessly.

dbus-run-session -- msstore publish \
    "$MSIX" \
    -id "$STORE_PRODUCT_ID"

echo ""
echo "Microsoft Store release submitted successfully."