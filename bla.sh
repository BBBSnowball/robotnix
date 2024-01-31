#docker run -it --network=host --mount type=bind,source=/nix,target=/nix ubuntu:22.04
docker run -it --mount type=bind,source=/nix,target=/nix ubuntu:22.04

docker build --file Dockerfile1 --tag x1 .

docker run -it --mount type=bind,source=/nix,target=/nix x1

#docker build --file Dockerfile2 --tag x2 .
docker build --file Dockerfile3 --tag x3 .

