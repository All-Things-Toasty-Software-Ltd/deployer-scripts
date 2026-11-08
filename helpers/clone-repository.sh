#!/usr/bin/env bash

set -euo pipefail

OWNER="$1"
REPOSITORY="$2"
DESTINATION="$3"

if [[ -z "$OWNER" || -z "$REPOSITORY" || -z "$DESTINATION" ]]; then
    echo "Usage: $0 <owner> <repository> <destination>"
    exit 1
fi

REPOSITORY_URL="https://github.com/$OWNER/$REPOSITORY.git"

if [[ -e "$DESTINATION" ]]; then
    echo "ERROR: Destination already exists:"
    echo "  $DESTINATION"
    exit 1
fi

echo "========================================"
echo "Cloning Repository"
echo "========================================"
echo "Repository: $OWNER/$REPOSITORY"
echo "Destination: $DESTINATION"
echo "========================================"

mkdir -p "$(dirname "$DESTINATION")"

git clone \
    --no-tags \
    "$REPOSITORY_URL" \
    "$DESTINATION"

echo ""
echo "Repository cloned successfully."