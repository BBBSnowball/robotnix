Build it
========

1. Prepare:
    a. Mount a btrfs filesystem to `~/.local/share/docker` and configure Docker to use the btrfs storage driver.
        - We assume that reflink copies will be fast (fast-ish - the source tree has tons of files) and take up
          almost no space. You may have a bad time if that doesn't hold on your system (or Docker's layer system
          *might* save you - we have never tried to be honest).
        - This can give some indication of whether this is configured correctly:
          `docker build --file Dockerfile-test-reflink . --progress=plain`
        - (It says 2.66 MB for "Set shared" of "/test" for me, which is two times the file size. We have never
           tested whether this truly says something else for another storage driver.)
        - It can be useful to use the same btrfs for your working directory (i.e. where this git is). That way,
          you can copy out result files and still have them reflinked. In other words, mount the btrfs at a
          location of your choice and bind mount a directory on it to `~/.local/share/docker`.
    b. Increase log limit for BuildKit.
        - Set `BUILDKIT_STEP_LOG_MAX_SIZE` and `BUILDKIT_STEP_LOG_MAX_SPEED` for the Docker daemon
          (or create a new builder with these settings and use it for all the Docker commands here).
        - Test with: `docker build --file Dockerfile-test-log-limit . --progress=plain --no-cache`
2. Run build:
    a. Choose tag: `tag=2024011600` or `tag=$(./get-latest-release.sh)`
    b. `./build.sh $tag`. This will run these steps for you:
        a. Initial clone of sources - takes much longer than update to a new tag (only the first time):
           `docker build --file Dockerfile-initial-clone --tag gos-src-initial . && docker image tag gos-src-latest`
        b. Update sources and checkout worktree:
           `docker build --file Dockerfile-clone-tag --tag gos-src-$tag . --progres=plain --build-arg TAG_NAME=refs/tags/$tag`
        c. Tag image with `gos-src-latest`, which will be used for builds and the next updates:
           `docker image tag gos-src-$tag gos-src-latest`
        d. Build it:
           `docker build --file Dockerfile --tag gos-build-$tag . --progress=plain`
3. Optional steps:
    a. If the build fails for some reason:
        - Build again and drop to shell on error:
          `BUILDX_EXPERIMENTAL=1 docker build --file Dockerfile --tag gos-build-$tag . --progress=plain --invoke on-error`
        - This should never take more than 10 min because we have some special handling to cache the long build steps even when they fail.
        - See [here](https://github.com/docker/buildx/blob/v0.11.2/docs/guides/debugging.md) for more info.
        - You can build only part of it with `--target` (see [documentation](https://docs.docker.com/build/building/multi-stage/#stop-at-a-specific-build-stage)),
          e.g. this will start a shell with build tools and the source tree (in `/grapheneos`) without building anything
          (using sources from `gos-src-latest`):
          `docker build --file Dockerfile . --target src --tag x && docker run --rm -it x`
        - You can run a container with a bind mount for `/nix`:
          `docker run -it --mount type=bind,source=/nix,target=/nix ubuntu:22.04`
    b. Save contents of caches in an image:
       `docker build --file Dockerfile-save-caches --tag gos-caches . --build-arg cache_buster=$num && docker run --rm -it gos-caches find /cache -maxdepth 2`

TODO (maybe)
============

- sign release
- copy factory and ota zips out of the final image
- generate differential updates
- apply some things from robotnix:
    - idea: build the config attrset and then implement some of the low-level things
      (and extract the relevant parts so we can change some setting and see whether this changes anything that we support)
    - set URL of update server in packages/apps/Updater/res/values/config.xml
    - install Bromite in addition to Vanadium (adblock, user scripts) but keep Vanadium for webview
    - fdroid
    - signature spoofing ?
    - remote attestation
- add to robotnix?
    - pre-approve adb keys
    - root (see below)
    - wifi credentials
    - backup url for new device wizard
    - patch seedvault to lie and say that it wants to move data to a new device, which allows making a backup of more apps
- allow root for adb (which is enough, for now)
    - userdebug build might already allow this
    - su looks at some property that we can change
        - some "ro.xx" properties are mentioned in the GrapheneOS build instructions - they might be in the same place
    - robotnix: description for `variant` says: "`userdebug` is like user but with root access and debug capability."
- remote attestation for access to backups
- somehow backup/sync browser bookmarks
    - ideally to some sort of Zettelkasten
- also build the parts that we don't change (just because we can):
    - build kernel, see https://grapheneos.org/build#kernel-6th-generation-pixels
    - build Vanadium, see https://grapheneos.org/build#browser-and-webview

Some random notes
=================

#FIXME We want to mount /nix into the container for later build steps. Can we do that or only when running a container..?

This is what we would use to build with robotnix:
`nix-build ./robotnix/ --arg configuration ./config.nix -A img`

Inspect config in nix repl:
`x = import ./robotnix { configuration = ./config.nix; }`, look into `x.config`

Interesting ones:
- system.additionalProductPackages, and similar  -> added to extraConfig
- system.extraConfig, and similar  -> added to source.dirs."robotnix/config" -> applied via build/make
- source.dirs
    - special case for build/make: only apply patch/postPatch
    - source.unpackScript is just all the `source.dirs.*.unpackScript`
- //actually, most of the ones in modules/base.nix
- envPackages ?
- envVars ?
- //source.manifest: set to some fake value
- source.unpackScript -> yes!
- apps.prebuilt
- `resources."frameworks/base/packages/SettingsProvider".def_backup_enabled`
- FIXME: most is handled via unpackScript but some parts are not:
    - Bromite build pulls in lots of dependencies that we could get from the source tree
      (but we will rather use upstream Bromite releases via F-Droid, so no need to fix it for Bromite)
    - scripts/release.sh has a fixed list of things to sign in the package - we have to adjust that!

nix eval --expr '(import ./robotnix { configuration = ./config.nix; }).config.build.unpackScript2' --impure --raw
nix-build --expr '(import ./robotnix { configuration = ./config.nix; }).config.build.unpackScript3'

