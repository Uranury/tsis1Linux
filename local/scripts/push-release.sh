#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: $0 <path-to-bin> <version>" >&2; exit 1; }

binary="$1"
version="$2"
rel="/opt/tsis1linux/releases/$version"

ssh app-deploy "mkdir -p '$rel'"
scp "$binary" "app-deploy:$rel/tsis1linux" || { echo "Failed to copy the binary" >&2; exit 1; }
ssh app-deploy "chmod 755 '$rel/tsis1linux'"
echo "uploaded $version"
