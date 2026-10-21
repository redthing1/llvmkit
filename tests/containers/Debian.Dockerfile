FROM docker.io/library/debian:12
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       cmake g++ ninja-build zstd \
    && rm -rf /var/lib/apt/lists/*
