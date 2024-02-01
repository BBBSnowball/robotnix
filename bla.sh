#docker run -it --network=host --mount type=bind,source=/nix,target=/nix ubuntu:22.04
docker run -it --mount type=bind,source=/nix,target=/nix ubuntu:22.04

docker build --file Dockerfile-build-tools --tag x1 .

docker run -it --mount type=bind,source=/nix,target=/nix x1

#docker build --file Dockerfile2 --tag x2 .
docker build --file Dockerfile-initial-clone --tag x5 .
docker build --file Dockerfile-clone-tag --tag x6 .
# rename x6b to x6: docker image tag x6b x6
docker build --file Dockerfile-shell-start2 --tag x7 .
docker build --file Dockerfile-build --tag x8 . --progress=plain
docker build --file Dockerfile-save-caches --tag x9 . --build-arg cache_buster=4 && docker run -it x9 find /cache -maxdepth 2

#FIXME combine many of these files and use "--target" to stop early for development
#  https://docs.docker.com/build/building/multi-stage/#stop-at-a-specific-build-stage
#  -> Vermutlich eins mit dem "will ich immmer neu machen" und x5 und x6 separat.

