# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS build-base

RUN dnf --setopt=install_weak_deps=False -y install \
      binutils bison cmake diffutils file findutils flex gcc gcc-c++ git \
      java-17-openjdk-devel make patch python3 python3-devel python3-pip \
      rsync tar which xz zlib-devel zstd \
    && dnf clean all \
    && python3 -m pip install --no-cache-dir ninja==1.13.0

FROM build-base AS llvm-build
ARG LLVM_VERSION
ARG LLVM_SHA256
ARG LLVM_TARGETS
ARG LLVM_PROJECTS
ARG LLVM_ASSERTIONS
ARG JOBS=16
RUN set -eux; \
    mkdir -p /work/llvm/src /opt/llvmkit/sdk/share/licenses/llvm; \
    curl -fL --retry 5 \
      "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-project-${LLVM_VERSION}.src.tar.xz" \
      -o /work/llvm/source.tar.xz; \
    printf '%s  %s\n' "${LLVM_SHA256}" /work/llvm/source.tar.xz | sha256sum -c -; \
    tar -xJf /work/llvm/source.tar.xz -C /work/llvm/src --strip-components=1; \
    cp /work/llvm/src/llvm/LICENSE.TXT /opt/llvmkit/sdk/share/licenses/llvm/LICENSE.TXT; \
    cmake -S /work/llvm/src/llvm -B /work/llvm/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/llvmkit/sdk \
      "-DLLVM_ENABLE_PROJECTS=${LLVM_PROJECTS}" \
      "-DLLVM_TARGETS_TO_BUILD=${LLVM_TARGETS}" \
      "-DLLVM_ENABLE_ASSERTIONS=${LLVM_ASSERTIONS}" \
      -DLLVM_ENABLE_RTTI=ON \
      -DLLVM_ENABLE_PLUGINS=ON \
      -DLLVM_BUILD_LLVM_DYLIB=ON \
      -DLLVM_LINK_LLVM_DYLIB=ON \
      -DLLVM_INCLUDE_TESTS=OFF \
      -DLLVM_INCLUDE_EXAMPLES=OFF \
      -DLLVM_INCLUDE_BENCHMARKS=OFF \
      -DLLVM_INCLUDE_DOCS=OFF \
      -DLLVM_ENABLE_LIBEDIT=OFF \
      -DLLVM_ENABLE_LIBXML2=OFF \
      -DLLVM_ENABLE_TERMINFO=OFF \
      -DLLVM_ENABLE_ZSTD=OFF \
      -DLLVM_PARALLEL_LINK_JOBS=2; \
    cmake --build /work/llvm/build --parallel "${JOBS}"; \
    cmake --install /work/llvm/build; \
    rm -rf /work/llvm

FROM llvm-build AS remill-build
ARG REMILL_COMMIT
ARG GFLAGS_COMMIT
ARG GLOG_COMMIT
ARG GOOGLETEST_COMMIT
ARG XED_COMMIT
ARG MBUILD_COMMIT
ARG SLEIGH_COMMIT
ARG REMILL_JOBS=16
COPY patches/remill/ /patches/remill/
COPY patches/sleigh/ /patches/sleigh/
COPY scripts/collect-remill-deps /usr/local/bin/collect-remill-deps
RUN set -eux; \
    mkdir -p /work/remill/src /opt/llvmkit/sdk/share/licenses/remill; \
    git -C /work/remill/src init; \
    git -C /work/remill/src remote add origin https://github.com/lifting-bits/remill.git; \
    git -C /work/remill/src fetch --depth 1 origin "${REMILL_COMMIT}"; \
    git -C /work/remill/src checkout --detach FETCH_HEAD; \
    test "$(git -C /work/remill/src rev-parse HEAD)" = "${REMILL_COMMIT}"; \
    for patch_file in /patches/remill/*.patch; do \
      git -C /work/remill/src apply "$patch_file"; \
    done; \
    cp /work/remill/src/LICENSE /opt/llvmkit/sdk/share/licenses/remill/LICENSE; \
    cmake -S /work/remill/src/dependencies -B /work/remill/deps-build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=/opt/llvmkit/sdk/bin/clang \
      -DCMAKE_CXX_COMPILER=/opt/llvmkit/sdk/bin/clang++ \
      -DCMAKE_PREFIX_PATH=/opt/llvmkit/sdk \
      -DCMAKE_INSTALL_PREFIX=/opt/llvmkit/deps \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DUSE_EXTERNAL_LLVM=ON \
      -DENABLE_SLEIGH=ON \
      "-DLLVMKIT_GFLAGS_COMMIT=${GFLAGS_COMMIT}" \
      "-DLLVMKIT_GLOG_COMMIT=${GLOG_COMMIT}" \
      "-DLLVMKIT_GOOGLETEST_COMMIT=${GOOGLETEST_COMMIT}" \
      "-DLLVMKIT_XED_COMMIT=${XED_COMMIT}" \
      "-DLLVMKIT_MBUILD_COMMIT=${MBUILD_COMMIT}" \
      "-DLLVMKIT_SLEIGH_COMMIT=${SLEIGH_COMMIT}" \
      -DLLVMKIT_SLEIGH_PATCH=/patches/sleigh/0001-spec-dir-env.patch \
      -DBUILD_SHARED_LIBS=OFF; \
    cmake --build /work/remill/deps-build --parallel "${REMILL_JOBS}"; \
    bash /usr/local/bin/collect-remill-deps \
      /work/remill/deps-build /opt/llvmkit/sdk; \
    cmake -S /work/remill/src -B /work/remill/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=/opt/llvmkit/sdk/bin/clang \
      -DCMAKE_CXX_COMPILER=/opt/llvmkit/sdk/bin/clang++ \
      '-DCMAKE_PREFIX_PATH=/opt/llvmkit/deps;/opt/llvmkit/sdk' \
      -DLLVM_DIR=/opt/llvmkit/sdk/lib/cmake/llvm \
      -DCMAKE_INSTALL_PREFIX=/opt/llvmkit/sdk \
      -DCMAKE_INSTALL_LIBDIR=lib \
      '-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib' \
      -DREMILL_FETCH_SLEIGH=OFF \
      -DREMILL_ENABLE_TESTING=OFF \
      -DREMILL_ENABLE_INSTALL_TARGET=ON; \
    cmake --build /work/remill/build --parallel "${REMILL_JOBS}"; \
    cmake --install /work/remill/build; \
    rsync -a --exclude=/lib/cmake/llvm/ --exclude=/.build_config \
      /opt/llvmkit/deps/ /opt/llvmkit/sdk/; \
    rm -rf /work/remill /opt/llvmkit/deps

FROM llvm-build AS llvm-package
ARG LLVM_VERSION
ARG LLVM_SHA256
ARG LLVM_TARGETS
ARG LLVM_PROJECTS
ARG LLVM_ASSERTIONS
ARG ABI
ARG BUILD_ID
ARG BASE_IMAGE
COPY consumer/toolchain.cmake /opt/llvmkit/sdk/share/cmake/toolchain.cmake
COPY scripts/package-sdk /usr/local/bin/package-sdk
RUN chmod +x /usr/local/bin/package-sdk && /usr/local/bin/package-sdk llvm

FROM scratch AS llvm-artifact
COPY --from=llvm-package /out/ /

FROM remill-build AS lab-build
ARG LIEF_VERSION
ARG LIEF_COMMIT
ARG LIEF_MACHO
ARG LIEF_ANDROID
ARG LIEF_JSON
ARG LIEF_JOBS=16
COPY patches/lief/ /patches/lief/
RUN set -eux; \
    mkdir -p /work/lief/src /opt/llvmkit/sdk/share/licenses/lief; \
    git -C /work/lief/src init; \
    git -C /work/lief/src remote add origin https://github.com/lief-project/LIEF.git; \
    git -C /work/lief/src fetch --depth 1 origin "refs/tags/${LIEF_VERSION}:refs/tags/${LIEF_VERSION}"; \
    git -C /work/lief/src checkout --detach "${LIEF_VERSION}"; \
    test "$(git -C /work/lief/src rev-parse HEAD)" = "${LIEF_COMMIT}"; \
    for patch_file in /patches/lief/*.patch; do \
      if test -f "$patch_file"; then git -C /work/lief/src apply "$patch_file"; fi; \
    done; \
    cp /work/lief/src/LICENSE /opt/llvmkit/sdk/share/licenses/lief/LICENSE; \
    cmake -S /work/lief/src -B /work/lief/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=/opt/llvmkit/sdk/bin/clang \
      -DCMAKE_CXX_COMPILER=/opt/llvmkit/sdk/bin/clang++ \
      -DCMAKE_INSTALL_PREFIX=/opt/llvmkit/sdk \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_SHARED_LIBS=ON \
      -DLIEF_INSTALL=ON \
      -DLIEF_ELF=ON -DLIEF_PE=ON -DLIEF_COFF=ON \
      "-DLIEF_MACHO=${LIEF_MACHO}" \
      "-DLIEF_DEX=${LIEF_ANDROID}" "-DLIEF_ART=${LIEF_ANDROID}" \
      "-DLIEF_OAT=${LIEF_ANDROID}" "-DLIEF_VDEX=${LIEF_ANDROID}" \
      "-DLIEF_ENABLE_JSON=${LIEF_JSON}" \
      -DLIEF_PYTHON_API=OFF -DLIEF_C_API=OFF \
      -DLIEF_EXAMPLES=OFF -DLIEF_TESTS=OFF -DLIEF_USE_MELKOR=OFF \
      -DLIEF_USE_CCACHE=OFF; \
    cmake --build /work/lief/build --parallel "${LIEF_JOBS}"; \
    cmake --install /work/lief/build; \
    rm -rf /work/lief

FROM lab-build AS lab-package
ARG LLVM_VERSION
ARG LLVM_SHA256
ARG LLVM_TARGETS
ARG LLVM_PROJECTS
ARG LLVM_ASSERTIONS
ARG REMILL_VERSION
ARG REMILL_COMMIT
ARG LIEF_VERSION
ARG LIEF_COMMIT
ARG LIEF_MACHO
ARG LIEF_ANDROID
ARG LIEF_JSON
ARG GFLAGS_COMMIT
ARG GLOG_COMMIT
ARG GOOGLETEST_COMMIT
ARG XED_COMMIT
ARG MBUILD_COMMIT
ARG SLEIGH_COMMIT
ARG ABI
ARG BUILD_ID
ARG BASE_IMAGE
COPY consumer/toolchain.cmake /opt/llvmkit/sdk/share/cmake/toolchain.cmake
COPY scripts/package-sdk /usr/local/bin/package-sdk
RUN chmod +x /usr/local/bin/package-sdk && /usr/local/bin/package-sdk lab

FROM scratch AS lab-artifact
COPY --from=lab-package /out/ /
