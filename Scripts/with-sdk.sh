#!/bin/bash
# Run a command with the SDK chosen by Scripts/select-sdk.sh.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/select-sdk.sh"
select_macos_sdk
exec "$@"
