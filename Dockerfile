###################################
### part 1: install build tools ###
###################################

#FROM docker.io/library/ubuntu:22.04
FROM docker.io/library/ubuntu@sha256:e6173d4dc55e76b87c4af8db8821b1feae4146dd47341e4d431118c7dd060a74 \
  as build-tools

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt update && apt install -y iproute2 tig htop tmux byobu vim \
  repo python3 git gnupg openssh-server diffutils libfreetype6 fontconfig fonts-dejavu-core libncurses5 libncurses5-dev openssl rsync unzip zip yarn e2fsprogs gperf python3-protobuf gcc-multilib signify \
  ca-certificates curl gnupg \
  xz-utils bzip2 m4 \
  && apt remove -v cmdtest
# (cmdtest has a yarn binary but not the one that we need)

# https://github.com/nodesource/distributions?tab=readme-ov-file#using-ubuntu-2
# https://github.com/nodesource/distributions/wiki/Repository-Manual-Installation
#RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - &&\
#  apt install -y nodejs yarnpkg
RUN --mount=type=bind,source=nodesource-repo.gpg.key,target=/tmp/nodesource-repo.gpg.key \
  gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg </tmp/nodesource-repo.gpg.key \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
  && apt update \
  && apt install -y nodejs

#RUN adduser user --disabled-password </dev/null
# -> might trigger a bug, see https://docs.docker.com/develop/develop-images/instructions/#user
RUN useradd --no-log-init --create-home --shell /bin/bash user

RUN install -d -o user /tools
USER user
RUN mkdir /tools/yarn \
  && cd /tools/yarn \
  && npm install --user yarn

################################################
### part 2: combine build tools with sources ###
################################################

# copy tools into src image because tools are smaller than src
FROM gos-src-latest as src

RUN rm -rf bin  boot  dev  etc  home  lib  lib32  lib64  libx32  media  mnt  nix  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
COPY --from=build-tools / /

################################################
### part 3: build plain upstream variant     ###
################################################

FROM src as build-a1
USER user
WORKDIR /grapheneos

#FIXME rename to match documentation: "$TARGET_PRODUCT-$TARGET_BUILD_VARIANT"
#      https://source.android.com/docs/setup/build/building#choose-a-target
ARG PIXEL_CODENAME=bluejay
# see https://source.android.com/docs/setup/create/new-device#build-variants
ARG BUILD_TARGET=user
#ARG BUILD_TARGET=userdebug
#ARG BUILD_TARGET=eng

#NOTE Here is some documentation on how the mount with type=cache works:
# https://github.com/moby/buildkit/issues/1673#issuecomment-1264502398
# tl;dr: caches with same id will be shared between all DockerFiles,
#        data will be in ~/data2/gos-docker/buildkit in some form,
#        cache can vanish at any time due to GC

RUN rm -rf out done-*

#RUN /tools/yarn/node_modules/.bin/yarn --cwd vendor/adevtool/
RUN --mount=type=bind,source=yarn-adevtool.sh,target=/tmp/yarn-adevtool.sh \
  --mount=type=cache,id=yarn-pkgs,target=/cache/yarn-pkgs,uid=1000,sharing=locked \
  /tmp/yarn-adevtool.sh

# time taken: ~11 min
# (on Framework Laptop with i7-1185G7)
RUN --network=none \
  bash -c "source build/envsetup.sh && m aapt2"

# This needs `eval` because the alias for adevtool is defined by envsetup.
RUN --mount=type=cache,id=adevtool-dl,target=/grapheneos/vendor/adevtool/dl,uid=1000,sharing=locked \
  bash -O expand_aliases -c "source build/envsetup.sh && eval adevtool generate-all -d $PIXEL_CODENAME"

FROM build-a1 as build-a2

# time taken: ~13 min
RUN --network=none bash -O expand_aliases -c "source build/envsetup.sh && eval lunch ${PIXEL_CODENAME}-${BUILD_TARGET} && eval m vendorbootimage" \
  && touch done-vendorbootimage || echo "step failed but don't tell BuildKit, yet"
# If the previous step has failed, BuildKit will see the error here. Restart with `--invoke=on-error`
# and you should immediately fall into a shell for this step (because the previous one was "successfull"
# and has thus been cached). We allow network in here because that can be useful in the debug shell.
FROM build-a2 as build-a3
RUN [ -e done-vendorbootimage ]

# time taken: 17000 sec = 4.7 h
RUN --network=none bash -O expand_aliases -c "source build/envsetup.sh && eval lunch ${PIXEL_CODENAME}-${BUILD_TARGET} && eval m target-files-package" \
  && touch done-target-files-package || echo "step failed but don't tell BuildKit, yet"
FROM build-a3 as build-a4
RUN [ -e done-target-files-package ]

# time taken: ~2 min
RUN --network=none \
  bash -c "source build/envsetup.sh && eval lunch ${PIXEL_CODENAME}-${BUILD_TARGET} && m otatools-package"

FROM build-a4 as build-a



FROM build-a as build-b1

#FIXME fix this in the initial install (but not now to avoid invalidating caches)
USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt update && apt remove -y signify && apt install -y signify-openbsd && ln -s signify-openbsd /usr/bin/signify
USER user

# We cannot skip this depending on the argument and we don't want to copy all of /nix/store into the build
# if the argument is missing/empty. Therefore, we supply a dummy path in that case to abort the build.
ARG robotnixPatchScript
RUN --network=none \
  --mount=type=bind,source=${robotnixPatchScript:-/argument-missing}/nix,target=/nix \
  "/nix/patch-sources"
FROM build-b1 as build-b2

#FIXME don't commit
ARG BUILD_TARGET=userdebug

# time taken: ~7 min ?
RUN --network=none \
  --mount=type=bind,source=${robotnixPatchScript:-/argument-missing}/nix,target=/nix \
  bash /nix/build-env m vendorbootimage \
  && touch done-vendorbootimage-b || echo "step failed but don't tell BuildKit, yet"
# If the previous step has failed, BuildKit will see the error here. Restart with `--invoke=on-error`
# and you should immediately fall into a shell for this step (because the previous one was "successfull"
# and has thus been cached). We allow network in here because that can be useful in the debug shell.
FROM build-b2 as build-b3
RUN [ -e done-vendorbootimage-b ]

# time taken: 17000 sec = 4.7 h ?
RUN --network=none \
  --mount=type=bind,source=${robotnixPatchScript:-/argument-missing}/nix,target=/nix \
  bash /nix/build-env m target-files-package \
  && touch done-target-files-package-b || echo "step failed but don't tell BuildKit, yet"
FROM build-b3 as build-b4
RUN [ -e done-target-files-package-b ]

# time taken: ~2 min ?
RUN --network=none \
  --mount=type=bind,source=${robotnixPatchScript:-/argument-missing}/nix,target=/nix \
  bash /nix/build-env m otatools-package

FROM build-b4 as build-b5

# time taken: TODO
#NOTE Secrets cannot be directories so we use a tar file.
RUN --network=none \
  --mount=type=secret,id=keys,uid=1000,required \
  bash -c "source build/envsetup.sh && eval lunch ${PIXEL_CODENAME}-${BUILD_TARGET} && mkdir -p keys/${PIXEL_CODENAME} && tar -C keys/${PIXEL_CODENAME} -xf /run/secrets/keys && yes \"\" | script/release.sh bluejay && rm -rf keys/${PIXEL_CODENAME}"

FROM build-b5 as build-b

FROM scratch as build-c
COPY --from=build-b /grapheneos/out/release-*/*.zip* /grapheneos/out/release-*/*-stable /

