Build it
========

1. Do once:
    a. Mount a btrfs filesystem to `~/.local/share/docker` and configure Docker to use the btrfs storage driver.
        - We assume that reflink copies will be fast (fast-ish - the source tree has tons of files) and take up
          almost no space. You may have a bad time if that doesn't hold on your system (or Docker's layer system
          *might* save you - we have never tried to be honest).
        - This can give some indication of whether this is configured correctly:
          `docker build --file Dockerfile-test-reflink . --progress=plain`
        - (It says 2.66 MB for "Set shared" of "/test" for me, which is two times the file size. We have never
           tested whether this truly says something else for another storage driver.)
    b. Increase log limit for BuildKit.
        - Set `BUILDKIT_STEP_LOG_MAX_SIZE` and `BUILDKIT_STEP_LOG_MAX_SPEED` for the Docker daemon
          (or create a new builder with these settings and use it for all the Docker commands here).
        - Test with: `docker build --file Dockerfile-test-log-limit . --progress=plain --no-cache`
    c. Initial clone - takes much longer than update to a new tag:
       `docker build --file Dockerfile-initial-clone --tag gos-src-initial . && docker image tag gos-src-latest`
2. Update sources:
    a. Choose tag: `tag=2024011600`
    b. Fetch sources: `docker build --file Dockerfile-clone-tag --tag gos-src-$tag . --progres=plain --build-arg TAG_NAME=refs/tags/$tag`
    c. Tag image with `gos-src-latest`, which will be used for builds and the next updates:
       `docker image tag gos-src-$tag gos-src-latest`
3. Build it:
    a. Normal build:
       `docker build --file Dockerfile --tag gos-build-$tag . --progress=plain`
    b. Drop to shell on error:
       `export BUILDX_EXPERIMENTAL=1;`
       `docker build --file Dockerfile --tag gos-build-$tag . --progress=plain --invoke on-error`
    c. Optional: Save contents of caches in an image:
       `docker build --file Dockerfile-save-caches --tag gos-caches . --build-arg cache_buster=$num && docker run -it gos-caches find /cache -maxdepth 2`

Some random notes
=================

#docker run -it --network=host --mount type=bind,source=/nix,target=/nix ubuntu:22.04
docker run -it --mount type=bind,source=/nix,target=/nix ubuntu:22.04

docker build --file Dockerfile-build-tools --tag x1 .

docker run -it --mount type=bind,source=/nix,target=/nix x1

# How to debug a failed build?
# -> https://github.com/docker/buildx/blob/v0.11.2/docs/guides/debugging.md
# -> `export BUILDX_EXPERIMENTAL=1` and `--inspect=on-error`

#FIXME combine many of these files and use "--target" to stop early for development
#  https://docs.docker.com/build/building/multi-stage/#stop-at-a-specific-build-stage
#  -> Vermutlich eins mit dem "will ich immmer neu machen" und x5 und x6 separat.

#FIXME We want to mount /nix into the container for later build steps. Can we do that or only when running a container..?

