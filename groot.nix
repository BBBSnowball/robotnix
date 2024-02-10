{ lib, pkgs, config, ... }:
with lib;
let
  dirModule = types.submodule ({ name, config, ... }: {
    options = {
      onlyPatches = mkOption {
        default = false;
        type = types.bool;
        description = "Whether to ignore the source and only apply patches. The sources should already exist.";
      };
    };
  });
in
{
  options = {
    source.dirs = mkOption {
      type = types.attrsOf dirModule;
    };
    environment.buildVars = mkOption {
      type = types.attrsOf types.str;
    };
  };

  config.source.dirs."build/make".onlyPatches = mkDefault true;

  config.build.unpackScript2 = let
    makeNormalUnpackScript = config: ''
      mkdir -p ${dirOf config.relpath}
      cp -T --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${config.src} ${config.relpath}
      chmod -R u+w ${config.relpath}
    '';

    makePatchScript = config: ''
      ${lib.concatMapStringsSep "\n" (p: "echo Applying ${p} && patch -p1 --no-backup-if-mismatch -d ${lib.escapeShellArg config.relpath} < ${p}") config.patches}
      ${lib.concatMapStringsSep "\n" (p: "echo Applying ${p} && ${pkgs.git}/bin/git apply --directory=${lib.escapeShellArg config.relpath} --unsafe-paths ${p}") config.gitPatches}
      ( cd ${config.relpath}
        ${config.postPatch}
      )
    '';

    makeUnpackScript = config:
    (if config.onlyPatches
    then makePatchScript config
    else makeNormalUnpackScript config)
    + (lib.concatMapStringsSep "\n" (c: ''
      mkdir -p $(dirname ${c.dest})
      cp -T --reflink=auto -f ${config.relpath}/${c.src} ${c.dest}
    '') config.copyfiles)
    + (lib.concatMapStringsSep "\n" (c: ''
      mkdir -p $(dirname ${c.dest})
      ln -sfT --relative ${config.relpath}/${c.src} ${c.dest}
    '') config.linkfiles);
  in
  "set -eo pipefail\n"
  + (lib.concatMapStringsSep "\n" makeUnpackScript (lib.filter (d: d.enable) (lib.attrValues config.source.dirs)));

  config.build.unpackScript3 = pkgs.writeShellScript "patch-sources" config.build.unpackScript2;

  config.build.buildEnvScript2 = let
  in ''
    set -eo pipefail
    shopt -s expand_aliases
    source build/envsetup.sh
    lunch ''${PIXEL_CODENAME}-''${BUILD_TARGET}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") config.environment.buildVars)}
    eval "$@"
  '';

  config.build.buildEnvScript3 = pkgs.writeShellScript "build-env" config.build.buildEnvScript2;

  # Docker wants to hash the input so we use a closure of the script instead of bind-mounting the whole Nix store.
  config.build.unpackScript4 = pkgs.runCommand "patch-sources-closure" {
    exportReferencesGraph = [ "closure" config.build.unpackScript3 "closure2" config.build.buildEnvScript3 ];
  } ''
    mkdir -p $out/nix/store
    cp ${config.build.unpackScript3} $out/${config.build.unpackScript3}
    ln -s ${config.build.unpackScript3} $out/nix/patch-sources
    ln -s ${config.build.buildEnvScript3} $out/nix/build-env
    cat closure closure2 | while read line ; do
      # should be a store path, a number or empty
      if [[ "$line" == /nix/store/* ]] ; then
        cp -rTu --reflink=auto "$line" $out/"$line"
      fi
    done
  '';
}
