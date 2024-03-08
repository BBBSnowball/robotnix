**This branch is not part of normal/upstream robotnix.**

If you want robotnix, see [upstream](https://github.com/nix-community/robotnix).

So, what is in this branch?

1. We use Docker to build Android for Pixel 6a (bluejay).
   That's not as nice as a real Nix build but it makes it easier to track upstream changes.
2. We apply config options from robotnix to the Docker build.
3. We use it to build an image with the F-Droid privileged extension and root access, which weakens
   the security model of GrapheneOS (which we use as the base) and is frowned upon by upstream devs
   (for good reason! don't blame them!), so we call the result GRoot. These changes are applied via
   robotnix, so you can choose which of these you want.


Build it
========

1. Prepare:
    1. Mount a btrfs filesystem to `~/.local/share/docker` and configure Docker to use the btrfs storage driver.
        - We assume that reflink copies will be fast (fast-ish - the source tree has tons of files) and take up
          almost no space. You may have a bad time if that doesn't hold true on your system (or Docker's layer system
          *might* save you - we have never tried to be honest).
        - This can give some indication of whether this is configured correctly:
          `docker build --file Dockerfile-test-reflink . --progress=plain`
        - (It says 2.66 MB for "Set shared" of "/test" for me, which is two times the file size. We have never
           tested whether this truly says something else for another storage driver.)
        - It can be useful to use the same btrfs for your working directory (i.e. where this git is). That way,
          you can copy out result files and still have them reflinked. In other words, mount the btrfs at a
          location of your choice and bind mount a directory on it to `~/.local/share/docker`.
    2. Increase log limit for BuildKit.
        - Set `BUILDKIT_STEP_LOG_MAX_SIZE=1073741824` and `BUILDKIT_STEP_LOG_MAX_SPEED=10485760` for the Docker daemon
          (or create a new builder with these settings and use it for all the Docker commands here).
        - Test with: `docker build --file Dockerfile-test-log-limit . --progress=plain --no-cache`
    3. Mount Nix store into build context:
        `mkdir nix/store && sudo mount --bind /nix/store ./nix/store`
    4. You can find our config [here](https://github.com/BBBSnowball/nixcfg/blob/main/hosts/framework/gos.nix)
       (well, you will be - not pushed, yet, at the time of writing). This includes all of the previous steps.
    5. Generate signing keys.
        - FIXME: Describe how to do this.
        - Fingerprint is the SHA256 hash of `keys/bluejay/avb_pkmd.bin`. This should match the fingerprint that is
          displayed by the bootloader (in part for some older devices but bluejay displays the full fingerprint).
          If the bootloader is not locked, it will display "ID: 9ac41741" instead of the fingerprint.
        - For more info see [here](https://source.android.com/docs/security/features/verifiedboot/boot-flow#unlocked-devices)
          and [here](https://github.com/nix-community/robotnix/blob/f941a20537384418c22000f6e6487c92441e0a7f/docs/src/modules/attestation.md?plain=1#L52C7-L52C42).
2. Run build:
    1. Choose tag: `tag=2024011600` or `tag=$(./get-latest-release.sh)`
    2. `./build.sh $tag`. This will run these steps for you:
        1. Initial clone of sources - takes much longer than update to a new tag (only the first time):
           `docker build --file Dockerfile-initial-clone --tag gos-src-initial . && docker image tag gos-src-latest`
        2. Update sources and checkout worktree:
           `docker build --file Dockerfile-clone-tag --tag gos-src-$tag . --progress=plain --build-arg TAG_NAME=refs/tags/$tag`
        3. Tag image with `gos-src-latest`, which will be used for builds and the next updates:
           `docker image tag gos-src-$tag gos-src-latest`
        4. Build it:
           `docker build --file Dockerfile --tag gos-build-$tag . --progress=plain`
3. Optional steps:
    1. If the build fails for some reason:
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
    2. Save contents of caches in an image:
       `docker build --file Dockerfile-save-caches --tag gos-caches . --build-arg cache_buster=$num && docker run --rm -it gos-caches find /cache -maxdepth 2`

TODO (maybe)
============

- sign release
    - FIXME add `--extra_apks RobotnixF-Droid.apk=PRESIGNED` in scripts/release.sh or maybe `LOCAL_CERTIFICATE := PRESIGNED` in its Android.mk
- generate differential updates
- apply some things from robotnix:
    - idea: build the config attrset and then implement some of the low-level things
      (and extract the relevant parts so we can change some setting and see whether this changes anything that we support)
    - set URL of update server in packages/apps/Updater/res/values/config.xml
    - DONE install Bromite in addition to Vanadium (adblock, user scripts) but keep Vanadium for webview -> better to add the F-Droid repo so it will be updated
    - DONE fdroid
    - signature spoofing ?
    - remote attestation
- add to robotnix?
    - pre-approve adb keys
    - root (see below)
    - WONTFIX wifi credentials -> sharing by QR code is easy enough and it's better to not put any secrets into the image because OTA server is usually public
    - backup url for setup wizard
    - DONE (not by us) patch seedvault to lie and say that it wants to move data to a new device, which allows making a backup of more apps
        - NOTE: SeedVault doesn't appear as an app. Search for backup in settings.
        - There is an experimental setting for "device-to-device" backups. Nice!
- allow root for adb (which is enough, for now)
    - userdebug build might already allow this -> it does.
    - su looks at some property that we can change
        - some "ro.xx" properties are mentioned in the GrapheneOS build instructions - they might be in the same place
    - robotnix: description for `variant` says: "`userdebug` is like user but with root access and debug capability."
    - So... can we only allow it for ADB and maybe only for pre-approved keys?
- remote attestation for access to backups
- somehow backup/sync browser bookmarks
    - ideally to some sort of Zettelkasten
- also build the parts that we don't change (just because we can):
    - build kernel, see https://grapheneos.org/build#kernel-6th-generation-pixels
    - build Vanadium, see https://grapheneos.org/build#browser-and-webview
- activate torch by long-press on power button
    - e.g. see https://review.lineageos.org/c/LineageOS/android_frameworks_base/+/320847/20/services/core/java/com/android/server/policy/PhoneWindowManager.java
    - /grapheneos/frameworks/base/core/res/res/values/config.xml
        - `config_longPressOnPowerBehavior = 6`
        - `config_longPressOnPowerDurationMs = 300`
        - `config_longPressOnPowerForAssistantSettingAvailable = true`
        - `config_veryLongPressOnPowerBehavior = 1`
    - /grapheneos/frameworks/base/services/core/java/com/android/server/policy/PhoneWindowManager.java
        - [in LineageOS](https://github.com/LineageOS/android_frameworks_base/blob/lineage-20.0/services/core/java/com/android/server/policy/PhoneWindowManager.java)
        - mDeviceKeyHandlers loaded via PathClassLoader - could be useful to add key handlers in external code
    - `config_supportLongPressPowerWhenNonInteractive`
- make variant of Auditor
    - from my older attempt:
        - `find . -exec sed -i 's/app.attestation.auditor/app.attestation.auditorGroot/g' {} \+`
        - `git checkout app/src/main/res/raw/deflate_dictionary_2.bin`  (dictionary for compression - keep this as is)
        - other changes in: app/src/main/java/app/attestation/auditor/AttestationProtocol.java (e.g. fingerprints)
        - other changes in: app/src/main/res/raw/deflate_dictionary_2.bin (unmodified official release -> unmodified release)

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

https://source.android.com/docs/setup/build/building
-> use `mma` to build a subdir

very helpful when editing diffs: patchutils: rediff and recountdiff
(https://stackoverflow.com/a/34431351)

Recovery mode: Power off, power on with "volume down" pressed. Select recovery and boot that. Error "no command" appears. Hold power and short press "volume up".
see https://www.edeka-smart.de/news/android_recovery_mode_funktioniert_nicht-194
Then, select loading update from ADB and do `adb sideload bluejay-ota_update-2024020900.zip`.

other settings:
config_allowAllRotations=true
config_useCurrentRotationOnRotationLockChange=true
config_reverseDefaultRotation ?
config_doublePressOnPowerBehavior and config_doublePressOnPowerTargetActivity ?
config_triplePressOnPowerBehavior = 2  // brightness boost
config_screenBrightnessSettingMinimum ?
config_dozePickupGestureEnabled=false
config_safe_media_volume_index is 10 by default
config_safe_media_volume_enabled=false

config_cameraDoubleTapPowerGestureEnabled ?
config_emergencyGestureEnabled ?  -> power button, multiple times -> settings says five times
config_defaultEmergencyGestureEnabled=false ?
config_packagedKeyboardName -> auto-pair to bluetooth keyboard
config_multiuserMaximumUsers ?
config_multiuserMaxRunningUsers ?
config_enableMultiUserUI ?
config_recentsComponentName ?
config_globalActionsList !
config_veryLongPressTimeout: default is 3500 but that takes *ages*
config_displayColorFadeDisabled = false?
config_allowPriorityVibrationsInLowPowerMode ?

https://source.android.com/docs/setup/create/new-device#ANDROID_VENDOR_KEYS
-> pre-authenticate ADB (and then maybe disable manual auth?)
-> manual might be disabled via config_customAdbPublicKeyConfirmationComponent, I think; and config_customAdbWifiNetworkConfirmationComponent

*gesture*


./out/target/product/bluejay/recovery/root/default.prop
persist.security.deny_new_usb
ro.debuggable=0

