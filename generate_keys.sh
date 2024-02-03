#! /usr/bin/env nix-shell
#! nix-shell -i bash -p openssl signify python3 jre_minimal
set -eo pipefail
set -x

DEVICE=bluejay
CN=groot

if [ ! -e keys/$DEVICE/avb_pkmd.bin ] ; then
  mkdir -p keys/$DEVICE
  cd keys/$DEVICE
  CN=GrapheneOS
  # The trap handler in make_key calls "exit 1" on normal EXIT. Hmpf.
  set +e
  bash ../../files/make_key releasekey "/CN=$CN/"
  bash ../../files/make_key platform "/CN=$CN/"
  bash ../../files/make_key shared "/CN=$CN/"
  bash ../../files/make_key media "/CN=$CN/"
  bash ../../files/make_key networkstack "/CN=$CN/"
  bash ../../files/make_key sdk_sandbox "/CN=$CN/"
  bash ../../files/make_key bluetooth "/CN=$CN/"
  set -e
  openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out avb.pem
  python3 ../../files/avbtool.py extract_public_key --key avb.pem --output avb_pkmd.bin
  cd ../..
fi

if [ ! -e keys/$DEVICE/factory.pub ] ; then
  signify -G -n -p keys/$DEVICE/factory.pub -s keys/$DEVICE/factory.sec
fi

if [ ! -e keys/$DEVICE/apps/vanadium.keystore ] ; then
  mkdir -p keys/$DEVICE/apps
  keytool -genkey -v -keystore keys/$DEVICE/apps/vanadium.keystore -storetype pkcs12 -alias vanadium \
    -keyalg RSA -keysize 4096 -sigalg SHA512withRSA -validity 10000 -dname "cn=$CN"
  keytool -export-cert -alias vanadium -keystore vanadium.keystore | sha256sum >keys/$DEVICE/apps/vanadium.trichrome_certdigest.txt
fi

