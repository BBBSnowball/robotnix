#!/bin/bash
set -eo pipefail
# envsetup.sh defines aliases (e.g. for adevtool) so we use `expand_aliases`
# and `eval` to make it work like in an interactive shell.
shopt -s expand_aliases
unset TARGET_PRODUCT
unset TARGET_BUILD_VARIANT
source build/envsetup.sh
eval "$@"

