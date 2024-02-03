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
  };

  config.source.dirs."build/make".onlyPatches = mkDefault true;

  config.build.unpackScript2 = let
    makeNormalUnpackScript = config: ''
      mkdir -p ${dirOf config.relpath}
      cp -T --reflink=auto --no-preserve=ownership --no-dereference --preserve=links -r ${config.src} ${config.relpath}
      chmod -R u+w ${config.relpath}
    '';

    makePatchScript = config: ''
      ${lib.concatMapStringsSep "\n" (p: "echo Applying ${p} && patch -p1 --no-backup-if-mismatch -d $out < ${p}") config.patches}
      ${lib.concatMapStringsSep "\n" (p: "echo Applying ${p} && ${pkgs.git}/bin/git apply --directory=$out --unsafe-paths ${p}") config.gitPatches}
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
}
