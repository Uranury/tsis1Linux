#!/bin/bash

set -u

[[ "$#" -eq 2 ]] || { echo "Usage: $0 <path-to-bin> <dest>" >&2; exit 1; }

binary="$1"
dest="app-deploy:$2"

if ! error=$(scp "$binary" "$dest" 2>&1); then
	echo "Failed to copy the binary, error: $error" >&2
	exit 1
fi
echo "Success"
