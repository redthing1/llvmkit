FROM docker.io/library/almalinux:9
RUN dnf --setopt=install_weak_deps=False -y install \
      cmake gcc gcc-c++ python3-pip tar zstd \
    && dnf clean all \
    && python3 -m pip install --no-cache-dir ninja==1.13.0
