#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="/opt/toasty-deployer/secrets"

if [[ -f "$SECRETS_DIR/gitlab.env" ]]; then
    # shellcheck disable=SC1090
    source "$SECRETS_DIR/gitlab.env"
fi

GITLAB_HOST="${GITLAB_HOST:-git.toastysoftware.co.uk}"
GITLAB_HOST="${GITLAB_HOST#https://}"
GITLAB_HOST="${GITLAB_HOST#http://}"
GITLAB_HOST="${GITLAB_HOST%/}"

: "${GITLAB_TOKEN:?GITLAB_TOKEN is not set}"

PROJECT="$1"
VERSION="$2"
ARTIFACT_DIR="$3"
RELEASE_NOTES="$4"

shift 4

if [[ $# -lt 1 ]]; then
    echo "Usage:"
    echo "  $0 <gitlab_project> <version> <artifact_dir> <release_notes> <artifact...>"
    exit 1
fi

if [[ -z "$PROJECT" || -z "$VERSION" ]]; then
    echo "Usage:"
    echo "  $0 <gitlab_project> <version> <artifact_dir> <release_notes> <artifact...>"
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
        echo "ERROR: GitLab release artifact does not exist:"
        echo "  $ARTIFACT_DIR/$ARTIFACT"
        exit 1
    fi
done

# Percent-encode the namespace/project path for the GitLab REST API, or use the
# project ID unchanged when a numeric ID is supplied.

if [[ "$PROJECT" =~ ^[0-9]+$ ]]; then
    PROJECT_ENCODED="$PROJECT"
else
    PROJECT_ENCODED="$(
        python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PROJECT"
    )"
fi

API_BASE="https://$GITLAB_HOST/api/v4/projects/$PROJECT_ENCODED"
TAG="v$VERSION"
GITLAB_REF="${GITLAB_REF:-main}"
PACKAGE_NAME="bakers-archive-mobile-companion"

echo ""
echo "========================================"
echo "GitLab Release"
echo "========================================"
echo "Host:       $GITLAB_HOST"
echo "Project:    $PROJECT"
echo "Version:    $VERSION"
echo "Tag:        $TAG"
echo "Artifacts:  $*"
echo "========================================"

# Create the tag if it does not already exist.

TAG_STATUS="$(
    curl -sS \
        -o /dev/null \
        -w '%{http_code}' \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$API_BASE/repository/tags/$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TAG")"
)"

if [[ "$TAG_STATUS" == "404" ]]; then
    echo "Creating tag $TAG from $GITLAB_REF..."

    TAG_RESPONSE="$(
        curl -fsSL \
            -X POST \
            -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            --data-urlencode "tag_name=$TAG" \
            --data-urlencode "ref=$GITLAB_REF" \
            "$API_BASE/repository/tags"
    )"

    if [[ -z "$TAG_RESPONSE" ]]; then
        echo "ERROR: Failed to create tag $TAG." >&2
        exit 1
    fi
elif [[ "$TAG_STATUS" != "200" ]]; then
    echo "ERROR: Unexpected tag response: HTTP $TAG_STATUS" >&2
    exit 1
fi

# Handle an existing release without deleting or overwriting it.

RELEASE_STATUS="$(
    curl -sS \
        -o /dev/null \
        -w '%{http_code}' \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$API_BASE/releases/$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TAG")"
)"

RELEASE_EXISTS=false

if [[ "$RELEASE_STATUS" == "200" ]]; then
    echo "GitLab release $TAG already exists; checking assets..."

    ASSET_LINKS="$(
        curl -fsSL \
            -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$API_BASE/releases/$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TAG")/assets/links"
    )"

    MISSING_ARTIFACTS="$(
        python3 - "$ASSET_LINKS" "$@" <<'PY'
import json
import sys

links = json.loads(sys.argv[1])
available = {link.get('name') for link in links}
for artifact in sys.argv[2:]:
    if artifact not in available:
        print(artifact)
PY
    )"

    if [[ -z "$MISSING_ARTIFACTS" ]]; then
        echo "All requested artifacts are already attached; skipping GitLab release."
        exit 0
    fi

    readarray -t REQUESTED_ARTIFACTS <<< "$MISSING_ARTIFACTS"
    set -- "${REQUESTED_ARTIFACTS[@]}"

    echo "Uploading missing GitLab artifacts: $*"
    RELEASE_EXISTS=true
elif [[ "$RELEASE_STATUS" != "404" ]]; then
    echo "ERROR: Unexpected release response: HTTP $RELEASE_STATUS" >&2
    exit 1
fi

if [[ "$RELEASE_EXISTS" != "true" ]]; then

# Create the release.

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
    "description": body,
    "released_at": None,
}))
PY
)"

echo "Creating release $TAG..."

RELEASE_RESPONSE="$(
    curl -fsSL \
        -X POST \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        "$API_BASE/releases" \
        -d "$RELEASE_JSON"
)"

if [[ -z "$RELEASE_RESPONSE" ]]; then
    echo "ERROR: Failed to create GitLab release." >&2
    exit 1
fi

fi

# Upload artifacts as generic package files, then attach them to the release.

for ARTIFACT in "$@"; do
    FILE="$ARTIFACT_DIR/$ARTIFACT"
    ASSET_NAME="$ARTIFACT"

    echo "Uploading $ASSET_NAME to the GitLab package registry..."

    curl -fsSL \
        -X PUT \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$FILE" \
        "$API_BASE/packages/generic/$PACKAGE_NAME/$VERSION/$ASSET_NAME" \
        > /dev/null

    ASSET_URL="https://$GITLAB_HOST/api/v4/projects/$PROJECT_ENCODED/packages/generic/$PACKAGE_NAME/$VERSION/$ASSET_NAME"

    LINK_JSON="$(
        python3 - "$ASSET_NAME" "$ASSET_URL" <<'PY'
import json
import sys

name = sys.argv[1]
url = sys.argv[2]

print(json.dumps({
    "name": name,
    "url": url,
    "direct_asset_path": f"/{name}",
    "link_type": "package",
}))
PY
    )"

    echo "Attaching $ASSET_NAME to release $TAG..."

    curl -fsSL \
        -X POST \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        "$API_BASE/releases/$TAG/assets/links" \
        -d "$LINK_JSON" \
        > /dev/null

done

echo ""
echo "========================================"
echo "GitLab release complete"
echo "========================================"
