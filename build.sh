#! /usr/bin/env nix-shell
#! nix-shell -i bash -p docker jq
set -eo pipefail

extraArgs=""
if [ "$1" == "--debug" ] ; then
  export BUILDX_EXPERIMENTAL=1
  extraArgs="--invoke on-error"
  shift
fi

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
      ( set -x; docker build --file Dockerfile-initial-clone --tag gos-src-initial . --build-arg TAG_NAME="$tag_long" $extraArgs )
    fi
    newest_src="$(docker images "gos-src-*" --format=json | jq '"\(.CreatedAt):\(.Repository):\(.Tag)"' -r | sort --reverse | head -n 1)"
    ( set -x; docker image tag "$newest_src" gos-src-latest )
  else
    newest_src=gos-src-latest
  fi

  echo "== fetching sources for $tag_long (starting with $newest_src) =="
  ( set -x; docker build --file Dockerfile-clone-tag --tag "gos-src-$tag" . --progress=plain --build-arg TAG_NAME="$tag_long" $extraArgs )
  ( set -x; docker image tag "gos-src-$tag" gos-src-latest )
fi

echo "== build it =="
time ( set -x; docker build --file Dockerfile --tag "gos-build-$tag" . --progress=plain "$@" --target build-a $extraArgs )
(set -x; docker image tag "gos-build-$tag" gos-build-latest )

echo "== build with patches =="
( set -x; nix-build groot-main.nix -A config.build.unpackScript4 -o result-unpackScript4 )
closure="./$(realpath ./result-unpackScript4)"
if [ ! -e "$closure" ] ; then
  echo "Patch script doesn't exist in build context: $closure" >&2
  echo "Is the Nix store mounted to ./nix/store ?" >&2
  exit 1
fi
ln -sfT "$closure" result-patchScript5
#NOTE Passing a pipe for the secret doesn't work, i.e. not `src=<(tar ...)`.
tar -C keys/bluejay -cf keys/bluejay.tar .
time ( set -x; docker build --file Dockerfile --tag "gos-build2-$tag" . --progress=plain "$@" --build-arg robotnixPatchScript="$closure" --secret id=keys,src=./keys/bluejay.tar --output type=local,dest=./out/build2-$tag/ $extraArgs )
(set -x; docker image tag "gos-build2-$tag" gos-build2-latest )

