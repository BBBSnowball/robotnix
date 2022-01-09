#! /usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 <robotnix-generate-keys-info.json> <keysdir> <metadatadir>"
  echo "(expected three arguments but got $#)"
  echo "Required tools: openssl, jq, keytools (nix-build . -A keyTools --arg configuration ...)"
  echo "  or use: nix-shell default.nix -A generateKeysShell --arg configuration ..."
  echo "Build the JSON file like this: nix-build . -A generateKeysInfo"
  exit 1
fi

for tool in openssl jq make_key generate_verity_key avbtool ; do
  if !which $tool &>/dev/null ; then
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

ORIG_DIR="$(pwd)"
mkdir -p "$2"
cd "$2"

mkdir -p "$DEVICE"

for key in "${KEYS[@]}"; do
  mkdir -p "$(dirname "$key.pk8")"
  if [[ ! -e "$key".pk8 ]]; then
    echo "Generating $key key"
    # make_key exits with unsuccessful code 1 instead of 0
    make_key "$key" "/CN=Robotnix ${key/\// }/" && exit 1
  else
    echo "Skipping generating $key key since it is already exists"
  fi
done

for key in "${APEX_KEYS[@]}"; do
  mkdir -p "$(dirname "$key.pem")"
  if [[ ! -e "$key".pem ]]; then
    echo "Generating $key APEX AVB key"
    openssl genrsa -out "$key".pem 4096
    avbtool extract_public_key --key "$key".pem --output "$key".avbpubkey
  else
    echo "Skipping generating $key APEX key since it is already exists"
  fi
done

if [[ "$AVB_MODE" == "verity_only" ]] ; then
  if [[ ! -e "$DEVICE/verity_key.pub" ]]; then
      generate_verity_key -convert "$DEVICE/verity.x509.pem" "$DEVICE/verity_key"
  fi
else
  if [[ ! -e "$DEVICE/avb.pem" ]]; then
    # TODO: Maybe switch to 4096 bit avb key to match apex? Any device-specific problems with doing that?
    echo "Generating Device AVB key"
    openssl genrsa -out $DEVICE/avb.pem 2048
    avbtool extract_public_key --key "$DEVICE/avb.pem" --output "$DEVICE/avb_pkmd.bin"
  else
    echo "Skipping generating device AVB key since it is already exists"
  fi
fi

cd "$ORIG_DIR"
mkdir -p "$3"

out="$3/.metadata.nix.tmp"
echo "{" >"$out"

( cd "$2" && find . -type f -name "*.x509.pem" ) | while read key ; do
  echo "Extracting fingerprint from ${key#./}"
  fingerprint="$(openssl x509 -noout -fingerprint -sha256 -in "$2/$key")"
  fingerprint="${fingerprint#*=}"
  fingerprint="${fingerprint//:/}"
  echo "  keyStore.keys.\"${key#./}\".fingerprint = \"$fingerprint\";" >>"$out"
done

( cd "$2" && find . -type f \( -name "avb_pkmd.bin" -or -name "*.avbpubkey" \) ) | while read key ; do
  echo "Extracting fingerprint from ${key#./}"
  hash="$(sha256sum "$2/$key" | cut -f1 -d" ")"
  cp "$2/$key" "$3/$hash.avbpubkey"
  echo "  keyStore.keys.\"${key#./}\".fingerprint = \"${hash^^}\";" >>"$out"
  echo "  keyStore.keys.\"${key#./}\".file = ./$hash.avbpubkey;" >>"$out"
done

#TODO: what about verity_key?

echo "}" >>"$out"
mv "$out" "$3/metadata.nix"

