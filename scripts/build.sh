#!/bin/bash
set -e

# ==============================================================================
# Caffeine Framework Unified Build Orchestrator (Final Clean Version)
# ==============================================================================

# --- 1. Configuration & Defaults ---
PRESET="${1:-linux-native}"
TARGET="${2:-all}"

# Shift to capture any remaining arguments as extra CMake flags
if [ "$#" -ge 2 ]; then
    shift 2
elif [ "$#" -ge 1 ]; then
    shift 1
fi
EXTRA_ARGS=("$@")

# --- 2. Architecture Detection ---
# Map preset/stage keywords to the correct specialized Docker image
if [[ "$PRESET" == *"arm"* || "$PRESET" == *"stm32"* ]]; then
    STAGE="build-arm"
elif [[ "$PRESET" == *"riscv"* || "$PRESET" == *"gd32"* ]]; then
    STAGE="build-riscv"
else
    STAGE="build-native"
fi

REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-while-one}"
IMAGE_NAME="ghcr.io/${REPO_OWNER}/caffeine-build/${STAGE}:latest"

# --- 3. Environment Preparation ---
echo "--------------------------------------------------------------------------------"
echo " Image:  $IMAGE_NAME"
echo " Preset: $PRESET"
echo " Target: $TARGET"
echo "--------------------------------------------------------------------------------"

# Ensure we have the latest infrastructure image
docker pull "$IMAGE_NAME" || {
    echo "Error: Failed to pull build image. Check your internet connection or GHCR permissions."
    exit 1
}

# --- 4. Build Command Construction ---
# We use an array to maintain proper quoting when passing to bash -c
if [ -f "CMakePresets.json" ]; then
    # Modern Preset-based Workflow
    CMD="cmake --preset $PRESET ${EXTRA_ARGS[*]} && \
         cmake --build build/$PRESET --target $TARGET"
else
    # Standard Native Workflow
    CMD="cmake -B build -DFETCHCONTENT_FULLY_DISCONNECTED=OFF ${EXTRA_ARGS[*]} && \
         cmake --build build --target $TARGET"
fi

# --- 5. Execution (Containerized) ---
# We use --user to ensure files created in the volume match the host user's UID/GID
# this prevents "permission denied" or "git ownership" errors during FetchContent.
docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$(pwd)":/work \
    -w /work \
    "$IMAGE_NAME" \
    bash -c "rm -rf build && $CMD"
