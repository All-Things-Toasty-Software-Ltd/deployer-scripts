#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SECRETS_DIR="/opt/toasty-deployer/secrets"
source "$SECRETS_DIR/odoo.env"

OWNER="$1"
REPOSITORY="$2"
MODULE="$3"
DATABASE="$4"
REF="${5:-19.0}" #19.0 is the default release branch for Odoo modules.

if [[ -z "$OWNER" || -z "$REPOSITORY" || -z "$MODULE" || -z "$DATABASE" ]]; then
    echo "Usage: $0 <owner> <repository> <module> <database> [branch_or_tag]"
    exit 1
fi

REMOTE_REPOS="/opt/addon-repos"

echo "========================================"
echo "Odoo Deployment"
echo "========================================"
echo "Repository: $OWNER/$REPOSITORY"
echo "Module:     $MODULE"
echo "Database:   $DATABASE"
echo "Ref/Branch: $REF"
echo "Server:     $ODOO_HOST"
echo "========================================"

echo "Updating addon repo..."

sshpass -p "$ODOO_PASSWORD" ssh \
    -o StrictHostKeyChecking=accept-new \
    "$ODOO_USER@$ODOO_HOST" \
    bash -s -- "$OWNER" "$REPOSITORY" "$MODULE" "$DATABASE" "$REF" <<'REMOTE'

set -euo pipefail

OWNER="$1"
REPOSITORY="$2"
MODULE="$3"
DATABASE="$4"
REF="$5"

cd /opt/addon-repos

if [[ ! -d "$REPOSITORY" ]]; then
    echo "Repository does not exist, cloning..."
    git clone "https://github.com/$OWNER/$REPOSITORY.git" "$REPOSITORY"
fi

cd "$REPOSITORY"
echo "Fetching latest changes..."
git fetch --all --tags

echo "Checking out reference: $REF"
git checkout "$REF"
git reset --hard "origin/$REF" || git reset --hard "$REF"

echo "Syncing module: $MODULE"
rsync -a --delete "$MODULE/" "/opt/custom-addons/$MODULE/"

echo "Restarting Odoo service: odoo-$DATABASE"
systemctl restart "odoo-$DATABASE"

echo "Deployment complete."

REMOTE