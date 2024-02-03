# Some steps are specific for bluejay / Pixel 6a, e.g. kernel build,
# i.e. this won't just work by changing the device.
# see https://grapheneos.org/build
DEVICE=bluejay
REPO_KEY_FINGERPRINT=65EEFE022108E2B708CBFCF7F9E712E59AF5F22A
# https://grapheneos.org/releases#bluejay-stable
TAG=TQ1A.221205.011.2022122000
# https://developers.google.com/android/ota#bluejay
#BUILD_ID_VENDORFILES=latest
BUILD_ID_VENDORFILES=tq1a.221205.011-7a7b0700

set -xeo pipefail

step_index=0
step() {
  step_index=$[$step_index+1]
  echo -ne "\033]0;${step_index}: $*\007"
}

step "init repo"

  mkdir -p grapheneos-$TAG
  cd grapheneos-$TAG
  repo init -u https://github.com/GrapheneOS/platform_manifest.git -b refs/tags/$TAG </dev/null

step "check signature of git tag"

  gpg --list-keys $REPO_KEY_FINGERPRINT &>/dev/null \
    || gpg --recv-keys $REPO_KEY_FINGERPRINT
  ( cd .repo/manifests && git verify-tag $(git describe) )

step "download sources"

  if [ -e ".repo/sync_done_token" ] && [ "$(cat .repo/sync_done_token)" == "$TAG" ] ; then
    echo "Skipping fetch because we have already done it."
  else
    repo sync -j16
    echo "$TAG" >.repo/sync_done_token
  fi

step "download kernel sources"

  mkdir -p android/kernel/bluejay
  cd android/kernel/bluejay
  if [ ! -e .repo ] ; then
    # This would replace the repo in the parent dir if we did it here so we don't.
    T=$(mktemp -td repo-kernel.XXXXXXXX)
    ( cd "$T" && repo init -u https://github.com/GrapheneOS/kernel_manifest-bluejay.git -b refs/tags/$TAG </dev/null )
    mv "$T/.repo" .repo
  fi
  ( cd .repo/manifests && git verify-tag $(git describe) )
  if [ "$(repo --show-toplevel)" != "$PWD" ] ; then
    echo "ERROR: Repo toplevel is '$(repo --show-toplevel)' but must be '$PWD'." >&2
    exit 1
  fi

  if [ -e ".repo/sync_done_token" ] && [ "$(cat .repo/sync_done_token)" == "$TAG" ] ; then
    echo "Skipping fetch because we have already done it."
  else
    repo sync -j16
    echo "$TAG" >.repo/sync_done_token
  fi

step "patch prebuilt toolchain"

  IGNORE_MISSING_LIBS="libffi.so.6 libgdbm_compat.so.3 libgdbm.so.3 libcrypto.so.1.0.0 libssl.so.1.0.0 libcrypto.so.1.0.0 libjson.so.0 libglapi.so.0 libwrap.so.0 libXtst.so.6"

  if true ; then
    echo "autoPatchelf doesn't work here."
  elif [ -e ".repo/patch1_done_token" ] && [ "$(cat .repo/patch1_done_token)" == "$TAG:$IGNORE_MISSING_LIBS" ] ; then
    echo "Skipping autoPatchelf because we have already done it."
  else
    # We don't have autoPatchelf in the current shell because it is a function,
    # i.e. it is only available in the parent shell.
    nix-shell ../../../../shell.nix \
      --run "autoPatchelf prebuilts --ignore-missing=\"$IGNORE_MISSING_LIBS\"" \
      || true  # will always fail because autoPatchelf doesn't seem to pass --ignore-missing to patchelf
    echo "$TAG:$IGNORE_MISSING_LIBS" >.repo/patch1_done_token
  fi

step "build kernel"

  LTO=full BUILD_KERNEL=1 with-ubuntu ./build_bluejay.sh
  cd ../../..

step "install adevtool"

  yarn install --cwd vendor/adevtool/
  source script/envsetup.sh
  m aapt2

step "extract vendor files"

  vendor/adevtool/bin/run download vendor/adevtool/dl/ -d $DEVICE -b $BUILD_ID_VENDORFILES -t factory ota
  sudo vendor/adevtool/bin/run generate-all vendor/adevtool/config/$DEVICE.yml -c vendor/state/$DEVICE.json -s vendor/adevtool/dl/${DEVICE}-${BUILD_ID_VENDORFILES}-*.zip
  sudo chown -R $(logname):$(logname) vendor/{google_devices,adevtool}
  vendor/adevtool/bin/run ota-firmware vendor/adevtool/config/${DEVICE}.yml -f vendor/adevtool/dl/${DEVICE}-ota-${BUILD_ID_VENDORFILES}-*.zip

step "choose configuration"

  choosecombo release $DEVICE user

  #FIXME change URL in packages/apps/Updater/res/values/config.xml and then enable this
  #export OFFICIAL_BUILD=true

step "build"

  rm -r out
  #m target-files-package
  m vendorbootimage target-files-package -j8

step "generate keys"

  if [ ! -e keys/$DEVICE/avb_pkmd.bin ] ; then
    mkdir -p keys/$DEVICE
    cd keys/$DEVICE
    CN=GrapheneOS
    ../../development/tools/make_key releasekey "/CN=$CN/"
    ../../development/tools/make_key platform "/CN=$CN/"
    ../../development/tools/make_key shared "/CN=$CN/"
    ../../development/tools/make_key media "/CN=$CN/"
    ../../development/tools/make_key networkstack "/CN=$CN/"
    ../../development/tools/make_key sdk_sandbox "/CN=$CN/"
    ../../development/tools/make_key bluetooth "/CN=$CN/"
    openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out avb.pem
    ../../external/avb/avbtool extract_public_key --key avb.pem --output avb_pkmd.bin
    cd ../..
  fi

  if [ ! -e keys/$DEVICE/factory.pub ] ; then
    signify -G -n -p keys/$DEVICE/factory.pub -s keys/$DEVICE/factory.sec
  fi

step "build OTA tools"

  m otatools-package

step "create signed package"

  script/release.sh $DEVICE

