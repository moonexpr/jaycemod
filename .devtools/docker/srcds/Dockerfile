# The dedicated server on Linux (srcds.py --runtime docker, srcds_docker.py):
# steamcmd on Ubuntu 22.04, and Python for srcds_docker.py and server_root.py,
# which the container runs from the repo it mounts. GMod itself is installed
# into a volume at start, not here, so an update needs no new image.
# Raise IMAGE's tag in srcds_docker.py with every change to this file.
FROM steamcmd/steamcmd:ubuntu-22

# libtinfo5 and libncurses5: srcds's console. ca-certificates: steamcmd's HTTPS.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 ca-certificates libtinfo5 libncurses5 \
 && rm -rf /var/lib/apt/lists/*

# steamcmd's image runs steamcmd; this one runs what srcds_docker.py names
ENTRYPOINT []
CMD ["python3", "--version"]
