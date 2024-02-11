#!/bin/bash
set -eo pipefail
# envsetup.sh defines aliases (e.g. for adevtool) so we use `expand_aliases`
# and `eval` to make it work like in an interactive shell.
shopt -s expand_aliases
source build/envsetup.sh
lunch ${TARGET_PRODUCT}-${TARGET_BUILD_VARIANT}
eval "$@"

