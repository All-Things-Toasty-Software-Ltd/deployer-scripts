#!/usr/bin/env bash

set -euo pipefail

# Directory where the scripts are located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HELPER_DIR="$BASE_DIR/helper"

# TODO(Austin): Add the scrip to connect to my websites helper server, run
# CMAKE, then restart the muehle bridge service.