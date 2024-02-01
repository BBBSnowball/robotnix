#!/bin/bash
set -eo pipefail

dir=vendor/adevtool
rm -rf "$dir/node_modules"
hash=$(sha1sum "$dir/yarn.lock" | cut -d" " -f1)

if [ -e "/cache/yarn-pkgs/$hash" ] ; then
  echo "cache hit ($hash)"
  cp -a --reflink=auto "/cache/yarn-pkgs/$hash" "$dir/node_modules"
else
  echo "cache miss ($hash), cache has $(ls -1 /cache/yarn-pkgs|wc -l) entries"

  /tools/yarn/node_modules/.bin/yarn --cwd vendor/adevtool/

  rm -rf "/cache/yarn-pkgs/$hash.tmp"
  cp -a --reflink=auto "$dir/node_modules" "/cache/yarn-pkgs/$hash.tmp"
  mv -Tn "/cache/yarn-pkgs/$hash.tmp" "/cache/yarn-pkgs/$hash"
fi

