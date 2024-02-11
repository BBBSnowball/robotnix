#!/bin/bash
set -eo pipefail
rm -f step-done
# envsetup.sh defines aliases (e.g. for adevtool) so we use `expand_aliases`
# and `eval` to make it work like in an interactive shell.
shopt -s expand_aliases
source build/envsetup.sh
lunch ${TARGET_PRODUCT}-${TARGET_BUILD_VARIANT}
if eval "$@" ; then
  touch step-done
else
  # Swallow the error so BuildKit will cache this step. The next build step
  # will check the step-done file and fail but the result of the current step
  # will be cached. The user can create a container from this or restart the
  # build with `--invoke=on-error`.
  # We only do this two-step dance for steps that take more than 10 min.
  echo "step failed but don't tell BuildKit, yet" >&2
fi

