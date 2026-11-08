#!/usr/bin/env bash
set -e

TMP_DIR="/tmp/deployer-scripts-stage"
TARGET_DIR="/repos"

echo "Updating deployment scripts directory..."

# Fetch latest changes into a temporary staging area
if [ -d "$TMP_DIR/.git" ]; then
    git -C "$TMP_DIR" fetch origin main
    git -C "$TMP_DIR" reset --hard origin/main
else
    rm -rf "$TMP_DIR"
    git clone --depth 1 https://github.com/All-Things-Toasty-Software-Ltd/deployer-scripts.git "$TMP_DIR"
fi

# Sync all directories over to /repos while ignoring docs and git metadata
rsync -av --delete \
  --exclude='*.md' \
  --exclude='.git*' \
  --exclude='.github' \
  --exclude='LICENSE' \
  "$TMP_DIR/" "$TARGET_DIR/"

# Ensure all scripts inside all subfolders are executable
find "$TARGET_DIR" -type f -name "*.sh" -exec chmod +x {} +

# Cleanup temporary staging directory
rm -rf "$TMP_DIR"

echo "All script folders updated cleanly in $TARGET_DIR."