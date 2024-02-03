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

  signing.avb.fingerprint = "TODO";

  #FIXME aborts with an error
  #apps.auditor.enable = true;
  #apps.auditor.domain = "TODO";

  apps.fdroid = {
    enable = true;
    additionalRepos = {
      bromite = {
        url = "https://fdroid.bromite.org/fdroid/repo";
        pubkey = "E1EE5CD076D7B0DC84CB2B45FB78B86DF2EB39A3B6C56BA3DC292A5E0C3B9504";
        pushRequests = "prompt";
      };
    };
  };

  #apps.bromite.enable = true;  # -> better to install release via F-Droid

  apps.seedvault = {
    enable = true;
    #includedInFlavor = true;
  };

  # robotnix uses an old version that isn't available anymore so let's update it
  # see https://f-droid.org/en/packages/org.fdroid.fdroid/
  apps.prebuilt."F-Droid".apk = lib.mkForce (pkgs.fetchurl {
    url = "https://f-droid.org/repo/org.fdroid.fdroid_1019050.apk";
    sha256 = "sha256-OeaJO6i+QOT9IHq8i0KeHL+IFc77yINiA2avmRanz/U=";
  });
}
