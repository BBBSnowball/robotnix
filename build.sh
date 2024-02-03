#! /usr/bin/env nix-shell
#! nix-shell -i bash -p docker jq
set -eo pipefail

if [ -z "$1" ] ; then
  echo "Usage: $0 tagname" >&2
  exit 1
elif [[ $1 == */* ]] ; then
  tag_long="$1"
  tag="${tag_long##*/}"
elif [[ $1 == ?? ]] ; then
  # We guess that this is a branch rather than a tag.
  tag="$1"
  tag_long="refs/heads/$tag"
else
  tag="$1"
  tag_long="refs/tags/$tag"
fi
shift

if [ -n "$(docker images "gos-src-$tag" --format=json)" ] ; then
  echo "gos-src-$tag already exists"
else
  if [ -z "$(docker images "gos-src-latest" --format=json)" ] ; then
    if [ -z "$(docker images "gos-src-*" --format=json)" ] ; then
      echo "== initial source download =="
      ( set -x; docker build --file Dockerfile-initial-clone --tag gos-src-initial . --build-arg TAG_NAME="$tag_long" )
    fi
    newest_src="$(docker images "gos-src-*" --format=json | jq '"\(.CreatedAt):\(.Repository):\(.Tag)"' -r | sort --reverse | head -n 1)"
    ( set -x; docker image tag "$newest_src" gos-src-latest )
  else
    newest_src=gos-src-latest
  fi

  echo "== fetching sources for $tag_long (starting with $newest_src) =="
  ( set -x; docker build --file Dockerfile-clone-tag --tag gos-src-$tag . --progres=plain --build-arg TAG_NAME="$tag_long" )
  ( set -x; docker image tag gos-src-$tag gos-src-latest )
fi

echo "== build it =="
time ( set -x; docker build --file Dockerfile --tag "gos-build-$tag" . --progress=plain "$@" )

