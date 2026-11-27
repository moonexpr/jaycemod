# The repo's binary modules built for GMod's Linux server (native_linux.py):
# Rust on Ubuntu 22.04, the server image's (.workbench/docker/srcds), so a
# module links against no newer glibc than the server has.
# Raise IMAGE's tag in native_linux.py with every change to this file.
FROM ubuntu:22.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*

# rustup's toolchain, readable by the operator native_linux.py runs cargo as
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain 1.97.0 --no-modify-path \
 && chmod -R a+rX /usr/local/rustup /usr/local/cargo
