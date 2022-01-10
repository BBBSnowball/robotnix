#! /usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <robotnix-generate-keys-info.json> <keysdir>"
  echo "(expected two arguments but got $#)"
  echo "Required tools: jq"
  echo "  or use: nix-shell default.nix -A generateKeysShell --arg configuration ..."
  echo "Build the JSON file like this: nix-build . -A generateKeysInfo"
  exit 1
fi

for tool in jq ; do
  if ! which $tool &>/dev/null ; then
    echo "Missing tool: $tool" >&2
    echo "Required tools: openssl, jq, keytools (nix-build . -A keyTools)"
    exit 1
  fi
done

IFS=$'\n'
KEYS=( $(jq --raw-output '.keys | .[]' "$1" | tr -d "'\"\$\{\}") )
APEX_KEYS=( $(jq --raw-output '.apex_keys | .[]' "$1" | tr -d "'\"\$\{\}") )
AVB_MODE="$(jq --raw-output '.avb_mode' "$1" | tr -d "'\"\$\{\}")"
DEVICE="$(jq --raw-output '.device' "$1" | tr -d "'\"\$\{\}")"
unset IFS

cd "$2"

RETVAL=0

for key in "${KEYS[@]}"; do
  if [[ ! -e "$key".pk8 ]]; then
    echo "Missing $key key"
    RETVAL=1
  fi
done

for key in "${APEX_KEYS[@]}"; do
  if [[ ! -e "$key".pem ]]; then
    echo "Missing $key APEX AVB key"
    RETVAL=1
  fi
done


if [[ "$AVB_MODE" == "verity_only" ]] ; then
  if [[ ! -e "$DEVICE/verity_key.pub" ]]; then
    echo "Missing verity_key.pub"
    RETVAL=1
  fi
else
  if [[ ! -e "$DEVICE/avb.pem" ]]; then
    echo "Missing Device AVB key"
    RETVAL=1
  fi
fi

if [[ "$RETVAL" -ne 0 ]]; then
  echo Certain keys were missing from KEYSDIR. Have you run generateKeysScript?
  echo Additionally, some robotnix configuration options require that you re-run
  echo generateKeysScript to create additional new keys.  This should not overwrite
  echo existing keys.
fi
exit $RETVAL

