# --- Stage 1: Base (Common tools + GTest) ---
FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    cmake git build-essential python3 curl tar \
    clang-format clang-tidy cppcheck doxygen ninja-build gcovr \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/gtest
RUN git clone https://github.com/google/googletest.git -b v1.14.0 . \
    && mkdir build && cd build \
    && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local \
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
FROM base AS build-native
