# Usage:
#   mkdir -p x/releases
#   ln -s result/index.html x/
#   ln -s result/static x/
#   echo abc >x/releases/bluejay-stable
#   cp /path/to/release.zip x/releases/bluejay-factory-abc.zip
#   nix-build webInstaller.nix -o x/result
#   nix run nixpkgs#python3 -- -m http.server -d x
#   open http://localhost:8000/
{ pkgs ? import <nixpkgs> {} }:
with pkgs;
stdenv.mkDerivation rec {
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

  nativeBuildInputs = [
    openssl
    (python3.withPackages (p: with p; [ gixy lxml cssselect jinja2 ]))
  ];

  header = ''
    <header>
      <h1>
        Fork of the web installer.
        Most links won't work or point you to upstream info, which probably
        doesn't apply - especially any contact info or where to report bugs!
      </h1>
      Release images will be downloaded from: <pre>${RELEASES_URL}</pre>
    </header>
  '';
  passAsFile = [ "header" ];

  patchPhase = ''
    substituteInPlace static/js/web-install.js \
      --replace https://releases.grapheneos.org "$RELEASES_URL" \
      --replace '"/js/' '"/static/js/'

    substituteInPlace static/main.css \
      --replace '"/fonts/' '"/static/fonts/'

    # replace header and footer because the links won't work
    # and the contact info doesn't apply for our fork
    cp $headerPath templates/header.html
    echo "" >templates/footer.html
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
    sed -i "$replace" static/**/*.html

    substituteInPlace static/install/web.html \
      --replace 'href="/' 'href="static/' \
      --replace 'src="/' 'src="static/'
  '';

  installPhase = ''
    mkdir $out $out/static
    cp -r static/install/web.html $out/index.html
    cp -r static/{js,fonts,apple-touch-icon.png,favicon.svg,favicon.ico,*.css} $out/static/
  '';
}
