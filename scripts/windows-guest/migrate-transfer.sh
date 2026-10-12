#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: migrate-transfer.sh SOURCE DESTINATION" >&2
  exit 2
fi

source_path=$1
destination_path=$2

if [[ ! -e $source_path && ! -L $source_path ]]; then
  exit 0
fi
if [[ -L $source_path || ! -d $source_path ]]; then
  echo "Windows transfer migration requires a directory: $source_path" >&2
  exit 1
fi
if [[ -e $destination_path || -L $destination_path ]]; then
  echo "Windows transfer migration refused an existing destination: $destination_path" >&2
  exit 1
fi

# Rename keeps open virtiofs handles valid; a cross-filesystem copy cannot.
mv --no-copy --update=none-fail --no-target-directory -- "$source_path" "$destination_path"
