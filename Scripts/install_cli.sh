#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"

cd "$ROOT_DIR"
swift build -c release --product crawlbar
mkdir -p "$PREFIX"
install -m 0755 ".build/release/crawlbar" "$PREFIX/crawlbar"
echo "$PREFIX/crawlbar"
