#!/bin/bash
PRESET_OR_STAGE=${1:-linux-native}
CMAKE_TARGET=${2:-all}
shift 2
EXTRA_ARGS="$@" # All remaining arguments

# Determine the appropriate Docker stage based on the input
if [[ "$PRESET_OR_STAGE" == *"arm"* || "$PRESET_OR_STAGE" == *"stm32"* ]]; then
  STAGE="build-arm"
elif [[ "$PRESET_OR_STAGE" == *"riscv"* || "$PRESET_OR_STAGE" == *"gd32"* ]]; then
  STAGE="build-riscv"
elif [[ "$PRESET_OR_STAGE" == *"native"* ]]; then
  STAGE="build-native"
else
  # Default fallback if it doesn't match known patterns
  STAGE="build-native"
fi

# The image is built and pushed by the caffeine-build repository
REPO_OWNER=${GITHUB_REPOSITORY_OWNER:-while-one}
IMAGE_NAME="ghcr.io/${REPO_OWNER}/caffeine-build/$STAGE:latest"

# Pull the image to ensure it's up-to-date
echo "Pulling Docker image: $IMAGE_NAME"
docker pull "$IMAGE_NAME" || { echo "Failed to pull image $IMAGE_NAME. Please ensure it's built and pushed from caffeine-build."; exit 1; }

# Check if we should use presets or standard build
if [[ "$PRESET_OR_STAGE" == *"native"* && ! -f "CMakePresets.json" ]]; then
  # Standard build without presets
  docker run --rm -v "$(pwd)":/work -w /work "$IMAGE_NAME" \
      bash -c "rm -rf build && cmake -B build -DFETCHCONTENT_FULLY_DISCONNECTED=OFF $EXTRA_ARGS && cmake --build build --target $CMAKE_TARGET"
else
  # Build using preset
  docker run --rm -v "$(pwd)":/work -w /work "$IMAGE_NAME" \
      bash -c "rm -rf build && cmake --preset $PRESET_OR_STAGE $EXTRA_ARGS && cmake --build build/$PRESET_OR_STAGE --target $CMAKE_TARGET"
fi
