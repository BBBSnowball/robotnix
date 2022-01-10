# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkMerge mkOption mkEnableOption mkDefault mkOptionDefault mkRenamedOptionModule types;

  cfg = config.signing;

  # TODO: Find a better way to do this?
  putInStore = path: if (lib.hasPrefix builtins.storeDir path) then path else (/. + path);

  keysToGenerate = lib.unique (lib.flatten (
                    map (key: "${config.device}/${key}") [ "releasekey" "platform" "shared" "media" ]
                    ++ (lib.optional (config.signing.avb.mode == "verity_only") "${config.device}/verity")
                    ++ (lib.optionals (config.androidVersion >= 10) [ "${config.device}/networkstack" ])
                    ++ (lib.optionals (config.androidVersion >= 11) [ "com.android.hotspot2.osulogin" "com.android.wifi.resources" ])
                    ++ (lib.optionals (config.androidVersion >= 12) [ "com.android.connectivity.resources" ])
                    ++ (lib.optional config.signing.apex.enable config.signing.apex.packageNames)
                    ++ (lib.mapAttrsToList
                        (name: prebuilt: prebuilt.certificate)
                        (lib.filterAttrs (name: prebuilt: prebuilt.enable && prebuilt.certificate != "PRESIGNED") config.apps.prebuilt))
                    ));

  # Get a bunch of utilities to generate keys
  keyTools = pkgs.runCommandCC "android-key-tools" { buildInputs = [ (if config.androidVersion >= 12 then pkgs.python3 else pkgs.python2) ]; } ''
    mkdir -p $out/bin

    cp ${config.source.dirs."development".src}/tools/make_key $out/bin/make_key
    substituteInPlace $out/bin/make_key --replace openssl ${lib.getBin pkgs.openssl}/bin/openssl

    cc -o $out/bin/generate_verity_key \
      ${config.source.dirs."system/extras".src}/verity/generate_verity_key.c \
      ${config.source.dirs."system/core".src}/libcrypto_utils/android_pubkey.c${lib.optionalString (config.androidVersion >= 12) "pp"} \
      -I ${config.source.dirs."system/core".src}/libcrypto_utils/include/ \
      -I ${pkgs.boringssl}/include ${pkgs.boringssl}/lib/libssl.a ${pkgs.boringssl}/lib/libcrypto.a -lpthread

    cp ${config.source.dirs."external/avb".src}/avbtool $out/bin/avbtool

    patchShebangs $out/bin
  '';

  generateKeysInfo = pkgs.writeText "robotnix-generate-keys-info.json" (builtins.toJSON {
    keys = keysToGenerate;
    apex_keys = lib.optionals config.signing.apex.enable config.signing.apex.packageNames;
    avb_mode = config.signing.avb.mode;
    device = config.device;
  });
in
{
  options = {
    signing = {
      enable = mkOption {
        default = false;
        type = types.bool;
        description = "Whether to sign build using user-provided keys. Otherwise, build will be signed using insecure test-keys.";
      };

      signTargetFilesArgs = mkOption {
        default = [];
        type = types.listOf types.str;
        internal = true;
      };

      prebuiltImages = mkOption {
        default = [];
        type = types.listOf types.str;
        internal = true;
        description = ''
          A list of prebuilt images to be added to target-files.
        '';
      };

      avb = {
        enable = mkEnableOption "AVB signing";

        # TODO: Refactor
        mode = mkOption {
          type = types.enum [ "verity_only" "vbmeta_simple" "vbmeta_chained" "vbmeta_chained_v2" ];
          default  = "vbmeta_chained";
          description = "Mode of AVB signing to use.";
        };

        fingerprint = mkOption {
          type = types.strMatching "[0-9A-F]{64}";
          apply = lib.toUpper;
          description = "SHA256 hash of `avb_pkmd.bin`. Should be set automatically based on file under `keyStorePath` if `signing.enable = true`";
        };

        verityCert = mkOption {
          type = types.path;
          description = "Verity certificate for AVB. e.g. in x509 DER format.x509.pem. Only needed if signing.avb.mode = \"verity_only\"";
        };
      };

      apex = {
        enable = mkEnableOption "signing APEX packages";

        packageNames = mkOption {
          default = [];
          type = types.listOf types.str;
          description = "APEX packages which need to be signed";
        };
      };

      keyStorePath = mkOption {
        type = types.str;
        description = ''
          String containing absolute path to generated keys for signing.
          This must be a _string_ and not a "nix path" to ensure that your secret keys are not imported into the public `/nix/store`.
        '';
        example = "/var/secrets/android-keys";
      };

      buildTimeKeyStorePath = mkOption {
        type = with types; either str path;
        description = ''
          Path to generated keys for signing to use at build-time, as opposed to keyStorePath, which is used at evaluation-time.
        '';
      };

      keyStoreMetadata = mkOption {
        type = types.attrsOf types.anything;
        default = {};
        description = ''
          Information about the keys that will be used for signing.
          This can be used in case the key store won't be available for the build. Import the file metadata.nix that is generated by
          the script that generates the keys rather than trying to provide this information yourself.
        '';
        example = "/var/secrets/android-keys";
      };

      keyStoreUseDummy = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Don't try to use the key store.
          The build won't work but this can be used to test whether the configuration is ok (apart from the keys). Furthermore, this
          may be required for generating the script that will generate the keys.
        '';
        #TODO Why is that? Simple derivations should work without the keys (especially everything that we need to generate the keys).
        #     Is this (only) due to skipIfApkMissing in modules/apps/prebuilt ? If so, get rid of it.
      };
    };
  };

  config = let
    testKeysStorePath = config.source.dirs."build/make".src + /target/product/security;
  in {
    assertions = [
      {
        assertion = (builtins.length cfg.prebuiltImages) != 0 -> config.androidVersion == 12;
        message = "The --prebuilt-image patch is only applied to Android 12";
      }
    ];

    signing.keyStorePath = mkIf (!config.signing.enable) (mkDefault testKeysStorePath);
    signing.buildTimeKeyStorePath = mkMerge [
      (mkIf config.signing.enable (mkDefault "/keys"))
      (mkIf (!config.signing.enable) (mkDefault testKeysStorePath))
    ];
    signing.avb.fingerprint = mkIf config.signing.enable (mkOptionDefault (
      let relativePathOfKey = "${config.device}/avb_pkmd.bin"; in
      if lib.attrsets.hasAttrByPath ["signing" "keyStoreMetadata" relativePathOfKey "fingerprint"] config
        then config.signing.keyStoreMetadata."${relativePathOfKey}".fingerprint
      else if config.signing.keyStoreUseDummy
        then "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      else if (builtins.tryEval config.signing.keyStorePath).success
        then pkgs.robotnix.sha256Fingerprint (putInStore "${config.signing.keyStorePath}/${relativePathOfKey}")
      else throw ("The option `signing.keyStorePath' is used but not defined while evaluating default value for `signing.avb.fingerprint'."
        + " You can set one of these options or generate metadata.nix from your key store and add it to your config (which is the preferred method). If you have have already added"
        + " metadata.nix, the key `${relativePathOfKey}' may be missing from your key store and/ or the metadata file.")
      ));
    signing.avb.verityCert = mkIf config.signing.enable (mkOptionDefault (
      let relativePathOfKey = "${config.device}/verity.x509.pem"; in
      if lib.attrsets.hasAttrByPath ["signing" "keyStoreMetadata" relativePathOfKey "file"] config
        then config.signing.keyStoreMetadata."${relativePathOfKey}".file
      else if config.signing.keyStoreUseDummy
        then pkgs.writeText "dummy.txt" "not the actual cert, dummy generated because of config.signing.keyStoreUseDummy"
      else if (builtins.tryEval config.signing.keyStorePath).success
        then putInStore "${config.signing.keyStorePath}/${config.device}/${relativePathOfKey}"
      else throw ("The option `signing.keyStorePath' is used but not defined while evaluating default value for `signing.avb.verityCert'."
        + " You can set one of these options or generate metadata.nix from your key store and add it to your config (which is the preferred method). If you have have already added"
        + " metadata.nix, the key `${relativePathOfKey}' may be missing from your key store and/ or the metadata file.")
      ));

    signing.apex.enable = mkIf (config.androidVersion >= 10) (mkDefault true);
    # TODO: Some of these apex packages share the same underlying keys. We should try to match that. See META/apexkeys.txt from  target-files
    signing.apex.packageNames = map (s: "com.android.${s}") (
      lib.optionals (config.androidVersion == 10) [
        "runtime.release"
      ] ++ lib.optionals (config.androidVersion >= 10) [
        "conscrypt" "media" "media.swcodec" "resolv" "tzdata"
      ] ++ lib.optionals (config.androidVersion == 11) [
        "art.release" "vndk.v27"
      ] ++ lib.optionals (config.androidVersion >= 11) [
        "adbd" "cellbroadcast" "extservices" "i18n" "ipsec" "mediaprovider"
        "neuralnetworks" "os.statsd" "permission" "runtime" "sdkext"
        "telephony" "tethering" "wifi" "vndk.current" "vndk.v28" "vndk.v29"
      ] ++ lib.optionals (config.androidVersion >= 12) [
        "appsearch" "art" "art.debug" "art.host" "art.testing" "compos" "geotz"
        "scheduling" "support.apexer" "tethering.inprocess" "virt"
        "vndk.current.on_vendor" "vndk.v30"
      ]
    );

    signing.signTargetFilesArgs = let
      avbFlags = {
        verity_only = [
          "--replace_verity_public_key $KEYSDIR/${config.device}/verity_key.pub"
          "--replace_verity_private_key $KEYSDIR/${config.device}/verity"
          "--replace_verity_keyid $KEYSDIR/${config.device}/verity.x509.pem"
        ];
        vbmeta_simple = [
          "--avb_vbmeta_key $KEYSDIR/${config.device}/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
        ];
        vbmeta_chained = [
          "--avb_vbmeta_key $KEYSDIR/${config.device}/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
          "--avb_system_key $KEYSDIR/${config.device}/avb.pem" "--avb_system_algorithm SHA256_RSA2048"
        ];
        vbmeta_chained_v2 = [
          "--avb_vbmeta_key $KEYSDIR/${config.device}/avb.pem" "--avb_vbmeta_algorithm SHA256_RSA2048"
          "--avb_system_key $KEYSDIR/${config.device}/avb.pem" "--avb_system_algorithm SHA256_RSA2048"
          "--avb_vbmeta_system_key $KEYSDIR/${config.device}/avb.pem" "--avb_vbmeta_system_algorithm SHA256_RSA2048"
        ];
      }.${cfg.avb.mode}
      ++ lib.optionals ((config.androidVersion >= 10) && (cfg.avb.mode != "verity_only")) [
        "--avb_system_other_key $KEYSDIR/${config.device}/avb.pem"
        "--avb_system_other_algorithm SHA256_RSA2048"
      ];
      keyMappings = {
         # Default key mappings from sign_target_files_apks.py
        "build/make/target/product/security/devkey" = "${config.device}/releasekey";
        "build/make/target/product/security/testkey" = "${config.device}/releasekey";
        "build/make/target/product/security/media" = "${config.device}/media";
        "build/make/target/product/security/shared" = "${config.device}/shared";
        "build/make/target/product/security/platform" = "${config.device}/platform";
      }
      // lib.optionalAttrs (config.androidVersion >= 10) {
        "build/make/target/product/security/networkstack" = "${config.device}/networkstack";
      }
      // lib.optionalAttrs (config.androidVersion == 11) {
        "frameworks/base/packages/OsuLogin/certs/com.android.hotspot2.osulogin" = "com.android.hotspot2.osulogin";
        "frameworks/opt/net/wifi/service/resources-certs/com.android.wifi.resources" = "com.android.wifi.resources";
      }
      // lib.optionalAttrs (config.androidVersion >= 12) {
        # Paths to OsuLogin and com.android.wifi have changed
        "packages/modules/Wifi/OsuLogin/certs/com.android.hotspot2.osulogin" = "com.android.hotspot2.osulogin";
        "packages/modules/Wifi/service/ServiceWifiResources/resources-certs/com.android.wifi.resources" = "com.android.wifi.resources";
        "packages/modules/Connectivity/service/ServiceConnectivityResources/resources-certs/com.android.connectivity.resources" = "com.android.connectivity.resources";
      }
      # App-specific keys
      // lib.mapAttrs'
        (name: prebuilt: lib.nameValuePair "robotnix/prebuilt/${prebuilt.name}/${prebuilt.certificate}" prebuilt.certificate)
        config.apps.prebuilt;
    in
      lib.mapAttrsToList (from: to: "--key_mapping ${from}=$KEYSDIR/${to}") keyMappings
      ++ lib.optionals cfg.avb.enable avbFlags
      ++ lib.optionals cfg.apex.enable (map (k: "--extra_apks ${k}.apex=$KEYSDIR/${k} --extra_apex_payload_key ${k}.apex=$KEYSDIR/${k}.pem") cfg.apex.packageNames)
      ++ lib.optionals (builtins.length cfg.prebuiltImages != 0) (map (image: "--prebuilt_image ${image}") cfg.prebuiltImages);

    otaArgs =
      if config.signing.enable
      then [ "-k $KEYSDIR/${config.device}/releasekey" ]
      else [ "-k ${config.source.dirs."build/make".src}/target/product/security/testkey" ];

    # TODO: avbkey is not encrypted. Can it be? Need to get passphrase into avbtool
    # Generate either verity or avb--not recommended to use same keys across devices. e.g. attestation relies on device-specific keys
    build.generateKeysScript = pkgs.writeShellScript "generate_keys.sh" ''
      set -euo pipefail

      if [[ "$#" -eq 1 ]] ; then
        echo "You should pass two arguments to extract metadata from the generated keys."
      elif [[ "$#" -ne 2 ]]; then
        echo "Usage: $0 <keysdir> [<metadatadir>]"
        echo "$#"
        exit 1
      fi

      export PATH=${lib.getBin pkgs.openssl}/bin:${keyTools}/bin:${pkgs.jq}/bin:$PATH

      exec ${../scripts/generate_keys.sh} "${generateKeysInfo}" "$1" "''${2-}"
    '';

    build.keyTools = keyTools;
    build.generateKeysInfo = generateKeysInfo;
    build.generateKeysShell = pkgs.mkShell {
      name = "robotnix-generate-keys-shell";
      packages = with pkgs; [ openssl keyTools jq ];
    };

    # Check that all needed keys are available.
    build.verifyKeysScript = pkgs.writeShellScript "verify_keys.sh" ''
      set -euo pipefail

      if [[ "$#" -ne 1 ]]; then
        echo "Usage: $0 <keysdir>"
        exit 1
      fi

      export PATH=${pkgs.jq}/bin:$PATH

      exec ${../scripts/verify_keys.sh} "${generateKeysInfo}" "$1"
    '';
  };

  imports = [
    (mkRenamedOptionModule [ "keyStorePath" ] [ "signing" "keyStorePath" ])
  ];
}
