{ system ? builtins.currentSystem
, nixpkgs ? <nixpkgs>
, pkgs ? import nixpkgs { inherit system; } }:
let
  fhsenv = (pkgs.buildFHSUserEnv {
    name = "gos-env";
    targetPkgs = pkgs: with pkgs;
      [ zlib
      ];
    multiPkgs = pkgs: with pkgs;
      [ glibc
      xorg.libX11
      libGL
      expat
      cairo.out
      ];
    runScript = "bash";
  });

  ubuntu = pkgs.fetchzip {
    url = "https://git.launchpad.net/cloud-images/+oci/ubuntu-base/plain/ubuntu-jammy-oci-amd64-root.tar.gz?h=refs/tags/dist-jammy-amd64-20221130&id=5107d90663ceb24789a9fa19136b0753c5651aa0";
    hash = "sha256-kzcVHlWSVFsXevYkqCj6zsUj+rq0HvQXuY125jaUwOg=";
    name = "ubuntu-jammy-oci-amd64-root.tar.gz";
    extension = "tar.gz";
    stripRoot = false;
  };

  init-ubuntu = pkgs.writeShellScript "init-ubuntu" ''
    for i in ${ubuntu}/* /host/*; do
      path="/''${i##*/}"
      [ -e "$path" ] || ${pkgs.coreutils}/bin/ln -s "$i" "$path"
    done
    
    [ -d "$1" ] && [ -r "$1" ] && cd "$1"
    shift
    
    source /etc/profile
    exec bash "$@"
  '';

  chrootenv = pkgs.callPackage "${nixpkgs}/pkgs/build-support/build-fhs-userenv/chrootenv" {};

  with-ubuntu = pkgs.writeShellScriptBin "with-ubuntu" ''
    ${chrootenv}/bin/chrootenv ${init-ubuntu} "$(pwd)" "$@"
  '';
in
  pkgs.mkShell {
    packages = with pkgs; [
      # https://grapheneos.org/build#build-dependencies
      gitRepo git gnupg
      libgcc binutils
      (python3.withPackages (p: with p; [ protobuf ]))
      nodejs
      yarn
      gperf
      pkgsi686Linux.gcc.libc_lib
      pkgsi686Linux.gcc.libc_dev
      pkgsi686Linux.gcc
      signify
      fhsenv
      autoPatchelfHook

      # needed for patching prebuilt binaries
      bzip2
      libffi # too new, even the 3.3 one
      gdbm
      openssl_1_1  # still too new, would need 1.0.0
      sqlite
      readline
      ncurses5
      xorg.libxcb
      libjson
      dbus
      #libglapi
      #libwrap
      libsndfile
      libasyncns
      xorg.libXrender
      #xorg.xst
      xorg.libXi
      freetype

      with-ubuntu
    ];
  }
