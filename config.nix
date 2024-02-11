{ lib, pkgs, config, ... }:
with lib;
{
  imports = [ ./groot.nix ];

  device = "bluejay";
  #flavor = "grapheneos";
  flavor = "grapheneos-docker";  # -> don't add GrapheneOS source, don't complain

  # robotnix doesn't know about new GrapheneOS so manually set the versions
  # (see https://apilevels.com/)
  androidVersion = 14;
  #apiLevel = lib.mkForce 34;

  # more settings from GrapheneOS flavor
  #apps.seedvault.includedInFlavor = mkDefault true;
  #apps.updater.includedInFlavor = mkDefault true;
  signing.apex.enable = false;
  signing.signTargetFilesArgs = [ "--extra_apks OsuLogin.apk,ServiceWifiResources.apk=$KEYSDIR/${config.device}/releasekey" ];

  # sha256sum keys/bluejay/avb_pkmd.bin
  signing.avb.fingerprint = "ec6dd6633a4a48abac0e24c7d01b108352d1c21708fce877f441d0d318e60bfc";

  #FIXME aborts with an error
  #apps.auditor.enable = true;
  #apps.auditor.domain = "TODO";

  apps.fdroid = {
    enable = false;
    additionalRepos = {
      bromite = {
        url = "https://fdroid.bromite.org/fdroid/repo";
        pubkey = "E1EE5CD076D7B0DC84CB2B45FB78B86DF2EB39A3B6C56BA3DC292A5E0C3B9504";
        pushRequests = "prompt";
      };
    };
  };

  # workaround: tell release script to not try and sign F-Droid
  #FIXME find a more general solution
  source.dirs."script" = lib.mkIf config.apps.fdroid.enable {
    onlyPatches = true;
    patches = [ ./add-fdroid-to-release-script.patch ];
  };

  #apps.bromite.enable = true;  # -> better to install release via F-Droid

  apps.seedvault = {
    enable = false;
    #includedInFlavor = true;
  };

  # robotnix uses an old version that isn't available anymore so let's update it
  # see https://f-droid.org/en/packages/org.fdroid.fdroid/
  apps.prebuilt."F-Droid" = lib.mkIf config.apps.fdroid.enable {
    apk = lib.mkForce (pkgs.fetchurl {
      url = "https://f-droid.org/repo/org.fdroid.fdroid_1019050.apk";
      sha256 = "sha256-OeaJO6i+QOT9IHq8i0KeHL+IFc77yINiA2avmRanz/U=";
    });
  };

  # add some patches that maybe allow us to enable torch by long press on power button
  # (doesn't work, yet)
  source.dirs."frameworks/base" = lib.mkIf false {
    onlyPatches = true;
    gitPatches = [
      ./0001-Revert-Fix-power-long-press-behavior-could-be-change.patch
      ./0002-copy-code-for-torch-on-long-press-on-power-from-Line.patch
      ./0003-adjust-config.xml.patch
    ];
  };

  # patch Updater URL
  #FIXME Make this a proper mkIf for variant grapheneos-docker.
  apps.updater.url = "http://192.168.89.140:8000/groot-releases";
  # see https://source.android.com/docs/setup/create/new-device#use-resource-overlays
  resources."packages/apps/Updater" = {
    url = config.apps.updater.url;
    channel_default = config.channel;
  };
  environment.buildVars.OFFICIAL_BUILD = "true";  # enables the updater
}
