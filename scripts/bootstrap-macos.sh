#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This bootstrap script supports macOS only." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required: https://brew.sh/" >&2
  exit 1
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

brew bundle --file "$project_dir/Brewfile"
mise trust
mise install
mise run setup

echo
echo "かめすら development tools are ready."
echo "Review any remaining platform requirements shown by flutter doctor."
