#!/bin/sh
# Test suite for toolbar-menu.nvim. Run it from anywhere:
#
#     test/run.sh
#
# Exits nonzero if any assertion failed. See driver.lua for how it works.

set -eu

TM_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export TM_ROOT

command -v nvim >/dev/null || { echo "no nvim in PATH" >&2; exit 1; }

exec env -u NVIM timeout 120 nvim --clean -l "$TM_ROOT/test/driver.lua"
