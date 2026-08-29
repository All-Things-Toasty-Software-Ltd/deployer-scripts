#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_DIR="$1"
FILE="app/androidApp/build.gradle.kts"

cd "$REPOSITORY_DIR"

if [[ ! -f "$FILE" ]]; then
    echo "ERROR: Cannot find $FILE" >&2
    exit 1
fi

CURRENT_VERSION_CODE="$(
    grep -E '^[[:space:]]*versionCode[[:space:]]*=' "$FILE" |
    head -n 1 |
    grep -oE '[0-9]+' |
    head -n 1
)"

CURRENT_VERSION_NAME="$(
    grep -E '^[[:space:]]*versionName[[:space:]]*=' "$FILE" |
    head -n 1 |
    sed -E 's/.*versionName[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/'
)"

if [[ -z "$CURRENT_VERSION_CODE" ]]; then
    echo "ERROR: Could not determine versionCode." >&2
    exit 1
fi

if [[ -z "$CURRENT_VERSION_NAME" ]]; then
    echo "ERROR: Could not determine versionName." >&2
    exit 1
fi

PREVIOUS_COMMIT="$(git rev-parse HEAD^ 2>/dev/null || true)"

if [[ -z "$PREVIOUS_COMMIT" ]]; then
    PREVIOUS_VERSION_CODE=""
else
    if git cat-file -e "$PREVIOUS_COMMIT:$FILE" 2>/dev/null; then
        PREVIOUS_VERSION_CODE="$(
            git show "$PREVIOUS_COMMIT:$FILE" |
            grep -E '^[[:space:]]*versionCode[[:space:]]*=' |
            head -n 1 |
            grep -oE '[0-9]+' |
            head -n 1
        )"
    else
        PREVIOUS_VERSION_CODE=""
    fi
fi

if [[ "$CURRENT_VERSION_CODE" != "$PREVIOUS_VERSION_CODE" ]]; then
    VERSION_CHANGED="true"
else
    VERSION_CHANGED="false"
fi

echo "Previous versionCode: ${PREVIOUS_VERSION_CODE:-<none>}"
echo "Current versionCode:  $CURRENT_VERSION_CODE"
echo "Current versionName:  $CURRENT_VERSION_NAME"
echo "Release required:     $VERSION_CHANGED"

printf 'VERSION_CODE=%s\n' "$CURRENT_VERSION_CODE"
printf 'VERSION_NAME=%s\n' "$CURRENT_VERSION_NAME"
printf 'RELEASE_REQUIRED=%s\n' "$VERSION_CHANGED"