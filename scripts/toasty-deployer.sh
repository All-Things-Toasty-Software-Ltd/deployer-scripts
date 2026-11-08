#!/usr/bin/env bash
set -e

DEPLOYER_DIR="/opt/toasty-deployer"

echo "Updating Toasty Deployer..."
cd "$DEPLOYER_DIR"

# Make tracked deployment files exactly match GitHub.
# Ignored/untracked files such as the database, secrets and venv are preserved.
git fetch origin main
git reset --hard origin/main

echo "Restarting Toasty Deployer..."
systemctl restart toasty-deployer.service

echo "Deployer update complete."