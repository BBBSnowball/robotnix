{ lib, pkgs, config, ... }:
with lib;
let
  fileExists = name: builtins.readDir ./. ? "${name}";
  private = if fileExists "private.nix" then import ./private.nix else lib.warn "private.nix is missing" {};
  myDomain = private.domain or "groot.example.com";
in
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
  #FIXME put this into the auditor app (in caps) and make a rebranded Auditor app for checking it on other devices
  signing.avb.fingerprint = lib.toUpper "b68c2f54fa312e531a176b6322e16c3580b9043439616944d2e1beb825f9b927";

  #FIXME aborts with an error
  #apps.auditor.enable = true;
  #apps.auditor.domain = "TODO";

  apps.fdroid = {
    enable = true;
    additionalRepos = {
      bromite = {
        #FIXME F-Droid has this disabled by default and says that the signing certificate doesn't match.
        # -> adb root, adb shell, ps -ef|grep fdroid, su u0_a143, cd /data/data/org.fdroid.fdroid, sqlite3 ./databases/fdroid_db, select * from CoreRepository;
        # -> It looks like key must be the full key, not only fingerprint.
        # -> And here is how to get it: https://docs.robotnix.org/modules/f-droid.html
        # nix-shell -p yq curl --run 'curl -sL https://fdroid.bromite.org/fdroid/repo/index.xml | xq -r .fdroid.repo.\"@pubkey\"'
        url = "https://fdroid.bromite.org/fdroid/repo";
        pubkey = "3082036d30820255a00302010202041dcb268e300d06092a864886f70d01010b05003066310b30090603550406130244453110300e06035504081307556e6b6e6f776e310f300d060355040713064265726c696e3110300e060355040a130742726f6d6974653110300e060355040b130742726f6d6974653110300e0603550403130763736167616e353020170d3138303131393037323135375a180f32303638303130373037323135375a3066310b30090603550406130244453110300e06035504081307556e6b6e6f776e310f300d060355040713064265726c696e3110300e060355040a130742726f6d6974653110300e060355040b130742726f6d6974653110300e0603550403130763736167616e3530820122300d06092a864886f70d01010105000382010f003082010a0282010100b5a9231a3d1e4dabdb041daf5978fc2818b15a7e3381700a73ec8616edd22c4185d550796895b070c1f1548e79c87ffc33678d9c93f40644a275f2a03d5726d6c93f1ab344b3dba4e6c5a877d6f23b933941642618fd9111e4dde89d0155555a329d8c667a9e4774aede9c05ceb4b04ea206c9ff1d90f484cfb89f8fbf76f8479136ba2fe284502bb9487ea227cf0738777e30534ebd2ebc3a9bb27b1ccd0a6d16084ac58c8988f4db9420f9d4ebb5d5adee36dd723ee1b56d1e6322682ddf74face374569cea443665a9716bf51153f1503e2609d57d89d630a07448112a52bbd216bea0d9a7556845ce379cb82c35f341c2661d4e421a3e2cf59bb4c172bed0203010001a321301f301d0603551d0e04160414b96a0677b5bbc0cc90d6939d8e232fd746074d1d300d06092a864886f70d01010b050003820101000ee2c3a78acfe4fc1c8a4a0e80dc5f56308e7f49533b8216edb42e7b0bceb78efcfa20d7112b62374b012ecb4d9a247db0278ad06c90ef50855f416240e233442be6fdbf1ec253b716b59b3f72c02708dfa8db94ccae5c58fcb6ec1023dfedf62f85737f9b385055dededd8cfa3da97d5d20ad2567ab3c1dc22168235daa6eb97c7fa75a10bf1fd763a82eaa3adae44e20022847074386bfe5d7d1394d2ad0ce1b4b862e89a0105a08e219b8a4e0bad9f30657d5aa8908bb741ececccd7cb27f471148ed75148395887c3387a593646b9fab62776011573e89ddf242f190a2f72cd7b36e2e724dc79cc6c6ca43a392e3a0a720a732fccf1ab12ade2e9a020efc";
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
  apps.updater.url = "https://${myDomain}/updates";
  # see https://source.android.com/docs/setup/create/new-device#use-resource-overlays
  resources."packages/apps/Updater" = {
    url = config.apps.updater.url;
    channel_default = config.channel;
  };
  environment.buildVars.OFFICIAL_BUILD = "true";  # enables the updater
}
