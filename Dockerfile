# --- Stage 1: Base (Common tools + GTest) ---
FROM ubuntu:24.04 AS base

LABEL org.opencontainers.image.title="Caffeine Build Toolchain"
LABEL org.opencontainers.image.description="Dockerized cross-compilation environments for the Caffeine Framework"
LABEL org.opencontainers.image.source="https://github.com/while-one/caffeine-build"

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    cmake git build-essential python3 curl tar wget gnupg lsb-release software-properties-common \
    doxygen ninja-build gcovr

# Add official LLVM 22 repository and install toolset
RUN wget https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh \
    && ./llvm.sh 22 \
    && apt-get install -y clang-format-22 clang-tidy-22 \
    && ln -sf /usr/bin/clang-format-22 /usr/bin/clang-format \
    && ln -sf /usr/bin/clang-tidy-22 /usr/bin/clang-tidy \
    && rm -f llvm.sh \
    && rm -rf /var/lib/apt/lists/*

# Compile Cppcheck 2.20.0 from source for strict host parity
RUN git clone https://github.com/danmar/cppcheck.git --branch 2.20.0 --depth 1 /tmp/cppcheck \
    && mkdir /tmp/cppcheck/build && cd /tmp/cppcheck/build \
    && cmake -DCMAKE_BUILD_TYPE=Release .. \
    && make -j$(nproc) install \
    && rm -rf /tmp/cppcheck

WORKDIR /tmp/gtest
# Pin GTest to the commit SHA of v1.14.0 for supply-chain security
RUN git clone https://github.com/google/googletest.git . \
    && git checkout f8d7d77c06936315286eb55f8de22cd23c188571 \
    && mkdir build && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
    && make -j$(nproc) && make install && rm -rf /tmp/gtest

# --- Stage 2: ARM ---
FROM base AS build-arm
RUN apt-get update && apt-get install -y gcc-arm-none-eabi binutils-arm-none-eabi \
    && rm -rf /var/lib/apt/lists/*

# --- Stage 3: RISC-V ---
FROM base AS build-riscv
RUN apt-get update && apt-get install -y gcc-riscv64-unknown-elf \
    && rm -rf /var/lib/apt/lists/*

# --- Stage 4: Native Linux ---
# This stage is intentionally empty. It exists as an alias to 'base'
# to satisfy the CAFFEINE_BUILD_STAGE=build-native naming convention 
# expected by the build.py orchestrator.
FROM base AS build-native
