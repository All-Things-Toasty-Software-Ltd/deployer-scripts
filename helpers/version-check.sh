#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_DIR="$1"

if [[ -z "$REPOSITORY_DIR" ]]; then
    echo "Usage: $0 <repository_dir>" >&2
    exit 1
fi

cd "$REPOSITORY_DIR"

# Read the version from a Flutter pubspec when present; otherwise fall back to the
# Kotlin Multiplatform Android module so older pipelines keep working.
if [[ -f "pubspec.yaml" ]]; then
    FILE="pubspec.yaml"

    read_flutter_version() {
        sed -nE 's/^[[:space:]]*version:[[:space:]]*"?([^"#[:space:]]+)"?.*$/\1/p' "$1" |
            head -n 1
    }

    parse_pubspec() {
        local file="$1" version_field name code

        version_field="$(read_flutter_version "$file")"

        if [[ -z "$version_field" ]]; then
            return 1
        fi

        if [[ "$version_field" == *+* ]]; then
            name="${version_field%%+*}"
            code="${version_field##*+}"
        else
            name="$version_field"
            code="0"
        fi

        if [[ ! "$code" =~ ^[0-9]+$ ]]; then
            return 1
        fi

        printf '%s\n%s\n' "$code" "$name"
    }

    CURRENT_PARSE="$(parse_pubspec "$FILE")" || {
        echo "ERROR: Could not determine version from $FILE" >&2
        exit 1
    }

    CURRENT_VERSION_CODE="$(printf '%s\n' "$CURRENT_PARSE" | sed -n '1p')"
    CURRENT_VERSION_NAME="$(printf '%s\n' "$CURRENT_PARSE" | sed -n '2p')"

    PREVIOUS_COMMIT="$(git rev-parse HEAD^ 2>/dev/null || true)"

    if [[ -z "$PREVIOUS_COMMIT" ]]; then
        PREVIOUS_VERSION_CODE=""
    elif git cat-file -e "$PREVIOUS_COMMIT:$FILE" 2>/dev/null; then
        PREVIOUS_FILE="$(mktemp)"
        git show "$PREVIOUS_COMMIT:$FILE" > "$PREVIOUS_FILE"
        if PREVIOUS_PARSE="$(parse_pubspec "$PREVIOUS_FILE")"; then
            PREVIOUS_VERSION_CODE="$(printf '%s\n' "$PREVIOUS_PARSE" | sed -n '1p')"
        else
            PREVIOUS_VERSION_CODE=""
        fi
        rm -f "$PREVIOUS_FILE"
    else
        PREVIOUS_VERSION_CODE=""
    fi
else
    FILE="app/androidApp/build.gradle.kts"

    if [[ ! -f "$FILE" ]]; then
        echo "ERROR: Cannot find pubspec.yaml or $FILE" >&2
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
fi

if [[ "$CURRENT_VERSION_CODE" != "$PREVIOUS_VERSION_CODE" ]]; then
    VERSION_CHANGED="true"
else
    VERSION_CHANGED="false"
fi

echo ""
echo "Version source:       $FILE"
echo "Previous versionCode: ${PREVIOUS_VERSION_CODE:-<none>}"
echo "Current versionCode:  $CURRENT_VERSION_CODE"
echo "Current versionName:  $CURRENT_VERSION_NAME"
echo "Release required:     $VERSION_CHANGED"

printf 'VERSION_CODE=%s\n' "$CURRENT_VERSION_CODE"
printf 'VERSION_NAME=%s\n' "$CURRENT_VERSION_NAME"
printf 'RELEASE_REQUIRED=%s\n' "$VERSION_CHANGED"
