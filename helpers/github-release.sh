#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="/opt/toasty-deployer/secrets"

source "$SECRETS_DIR/github-app.env"

OWNER="$1"
REPOSITORY="$2"
VERSION="$3"
ARTIFACT_DIR="$4"
RELEASE_NOTES="$5"

shift 5

if [[ $# -lt 1 ]]; then
    echo "Usage:"
    echo "  $0 <owner> <repository> <version> <artifact_dir> <release_notes> <artifact...>"
    exit 1
fi

if [[ ! -f "$RELEASE_NOTES" ]]; then
    echo "ERROR: Release notes do not exist:"
    echo "  $RELEASE_NOTES"
    exit 1
fi

if [[ ! -s "$RELEASE_NOTES" ]]; then
    echo "ERROR: Release notes are empty."
    exit 1
fi

for ARTIFACT in "$@"; do
    if [[ ! -f "$ARTIFACT_DIR/$ARTIFACT" ]]; then
        echo "ERROR: GitHub release artifact does not exist:"
        echo "  $ARTIFACT_DIR/$ARTIFACT"
        exit 1
    fi
done

echo ""
echo "========================================"
echo "GitHub Release"
echo "========================================"
echo "Repository: $OWNER/$REPOSITORY"
echo "Version:    $VERSION"
echo "========================================"

# Create GitHub App JWT

b64url() {
    openssl base64 -A |
        tr '+/' '-_' |
        tr -d '='
}

NOW="$(date +%s)"
ISSUED_AT="$((NOW - 60))"
EXPIRATION="$((NOW + 540))"

HEADER='{"alg":"RS256","typ":"JWT"}'
PAYLOAD="{\"iat\":$ISSUED_AT,\"exp\":$EXPIRATION,\"iss\":$GITHUB_APP_ID}"

HEADER_B64="$(printf '%s' "$HEADER" | b64url)"
PAYLOAD_B64="$(printf '%s' "$PAYLOAD" | b64url)"

SIGNATURE="$(
    printf '%s.%s' "$HEADER_B64" "$PAYLOAD_B64" |
    openssl dgst -sha256 \
        -sign "$GITHUB_PRIVATE_KEY" |
    b64url
)"

JWT="$HEADER_B64.$PAYLOAD_B64.$SIGNATURE"

# Get installation token

INSTALLATION_RESPONSE="$(
    curl -fsSL \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $JWT" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/app/installations/$GITHUB_INSTALLATION_ID/access_tokens"
)"

GITHUB_TOKEN="$(
    printf '%s' "$INSTALLATION_RESPONSE" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'
)"

if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "ERROR: Failed to obtain GitHub installation token."
    exit 1
fi

# Check whether release already exists

TAG="v$VERSION"
RELEASE_RESPONSE_FILE="$(mktemp)"

HTTP_STATUS="$(
    curl -sS \
        -o "$RELEASE_RESPONSE_FILE" \
        -w '%{http_code}' \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$OWNER/$REPOSITORY/releases/tags/$TAG"
)"

if [[ "$HTTP_STATUS" == "200" ]]; then
    echo "GitHub release $TAG already exists; checking assets..."

    RELEASE_ID="$(
        python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$RELEASE_RESPONSE_FILE"
    )"

    UPLOAD_URL="$(
        python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["upload_url"].split("{")[0])' "$RELEASE_RESPONSE_FILE"
    )"

    ASSETS_RESPONSE="$(
        curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/$OWNER/$REPOSITORY/releases/$RELEASE_ID/assets"
    )"

    MISSING_ARTIFACTS="$(
        python3 - "$ASSETS_RESPONSE" "$@" <<'PY'
import json
import sys

assets = json.loads(sys.argv[1])
available = {asset.get('name') for asset in assets}
for artifact in sys.argv[2:]:
    if artifact not in available:
        print(artifact)
PY
    )"

    if [[ -z "$MISSING_ARTIFACTS" ]]; then
        rm -f "$RELEASE_RESPONSE_FILE"
        echo "All requested artifacts are already attached; skipping GitHub release."
        exit 0
    fi

    readarray -t REQUESTED_ARTIFACTS <<< "$MISSING_ARTIFACTS"
    set -- "${REQUESTED_ARTIFACTS[@]}"

    echo "Uploading missing GitHub artifacts: $*"
    rm -f "$RELEASE_RESPONSE_FILE"
elif [[ "$HTTP_STATUS" == "404" ]]; then
    RELEASE_BODY="$(cat "$RELEASE_NOTES")"

    RELEASE_JSON="$(
        python3 - "$TAG" "$VERSION" "$RELEASE_BODY" <<'PY'
import json
import sys

tag = sys.argv[1]
version = sys.argv[2]
body = sys.argv[3]

print(json.dumps({
    "tag_name": tag,
    "name": f"The Baker's Archive - {version}",
    "body": body,
    "draft": False,
    "prerelease": False,
    "generate_release_notes": False
}))
PY
    )"

    RELEASE_RESPONSE="$(
        curl -fsSL \
            -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -H "Content-Type: application/json" \
            "https://api.github.com/repos/$OWNER/$REPOSITORY/releases" \
            -d "$RELEASE_JSON"
    )"

    RELEASE_ID="$(
        printf '%s' "$RELEASE_RESPONSE" |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
    )"

    UPLOAD_URL="$(
        printf '%s' "$RELEASE_RESPONSE" |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["upload_url"].split("{")[0])'
    )"

    echo "Created release $TAG"
    echo "Release ID: $RELEASE_ID"
    rm -f "$RELEASE_RESPONSE_FILE"
else
    rm -f "$RELEASE_RESPONSE_FILE"
    echo "ERROR: Unexpected GitHub response: HTTP $HTTP_STATUS" >&2
    exit 1
fi

# Upload artifacts

for ARTIFACT in "$@"; do

    FILE="$ARTIFACT_DIR/$ARTIFACT"

    case "$ARTIFACT" in
        *.apk)
            CONTENT_TYPE="application/vnd.android.package-archive"
            ;;
        *.aab)
            CONTENT_TYPE="application/octet-stream"
            ;;
        *.msix)
            CONTENT_TYPE="application/msix"
            ;;
        *)
            CONTENT_TYPE="application/octet-stream"
            ;;
    esac

    echo "Uploading $ARTIFACT..."

    curl -fsSL \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: $CONTENT_TYPE" \
        --data-binary "@$FILE" \
        "$UPLOAD_URL?name=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$ARTIFACT")" \
        > /dev/null

    echo "Uploaded $ARTIFACT"

done

echo ""
echo "GitHub release complete."