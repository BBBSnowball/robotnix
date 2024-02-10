# Usage:
#   nix-build webInstaller.nix
#   mkdir /tmp/groot-releases && echo abc >/tmp/groot-releases/bluejay-stable
#   cp /path/to/release.zip /tmp/groot-releases/bluejay-factory-abc.zip
#   nix run nixpkgs#python3 -- -m http.server -d result
#   open http://localhost:8000/install/web.html
{ pkgs ? import <nixpkgs> {} }:
with pkgs;
stdenv.mkDerivation {
  pname = "groot-web-install";
  version = "0.1~git-8f4a95";

  src = fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "grapheneos.org";
    rev = "8f4a9554ca0b0f7bcfe07af809a2f8111b9d47a6";
    hash = "sha256-cTgAfngu2ojkjI1KCEOFkrTHJ52KWtUnBIYXJ5xngxU=";
  };

  #RELEASES_URL = "https://groot.example.com";
  RELEASES_URL = "/releases";
  SYMLINK_RELEASES = "/tmp/groot-releases";

  nativeBuildInputs = [
    openssl
    (python3.withPackages (p: with p; [ gixy lxml cssselect jinja2 ]))
  ];

  patchPhase = ''
    substituteInPlace static/js/web-install.js \
      --replace https://releases.grapheneos.org "$RELEASES_URL"
  '';

  buildPhase = ''
    python3 process-templates static

    # just the relevant parts of process-static
    replace=
    shopt -s dotglob extglob globstar
    for file in static/**/*.css static/js/*.js static/**/!(bimi|favicon).svg; do
        hash=$(sha256sum "$file" | head -c 8)
        sri_hash=sha256-$(openssl dgst -sha256 -binary "$file" | openssl base64 -A)
        dest="$(dirname $file)/$hash.$(basename $file)"
    
        if [[ $file == *.css ]]; then
            replace+=";s@\[\[css|/''${file#*/}\]\]@<link rel=\"stylesheet\" href=\"/''${dest#*/}\" integrity=\"$sri_hash\"/>@g"
        elif [[ $file == *.js ]]; then
            replace+=";s@\[\[js|/''${file#*/}\]\]@<script type=\"module\" src=\"/''${dest#*/}\" integrity=\"$sri_hash\"></script>@g"
        fi
    
        mv "$file" "$dest"
        replace+=";s@\[\[integrity|/''${file#*/}\]\]@''${sri_hash}@g"
        replace+=";s@\[\[path|/''${file#*/}\]\]@/''${dest#*/}@g"
    done
    ( set -x; sed -i "$replace" static/**/*.html )
  '';

  installPhase = ''
    cp -r static $out

    if [ -n "$SYMLINK_RELEASES" ] ; then
      ln -s "$SYMLINK_RELEASES" $out/releases
    fi
  '';
}
