set -xe
nix-shell -p python3Packages.virtualenv --run "virtualenv venv"
source venv/bin/activate
python3 -m pip install git+https://github.com/systemd/mkosi.git@v14
mkosi shell ./build.sh
