#!/bin/bash
set -e

# ==============================================================================
# Caffeine Framework Unified Build Orchestrator (Refactored)
# ==============================================================================

# --- 1. Configuration & Defaults ---
CLEAN_BUILD=false
PRESET=""
TARGET=""
EXTRA_ARGS=()

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --clean) CLEAN_BUILD=true ;;
        -*) EXTRA_ARGS+=("$1") ;;
        *)
            if [ -z "$PRESET" ]; then
                PRESET="$1"
            elif [ -z "$TARGET" ]; then
                TARGET="$1"
            else
                EXTRA_ARGS+=("$1")
            fi
            ;;
    esac
    shift
done

# Set defaults if not provided
PRESET="${PRESET:-linux-native}"
TARGET="${TARGET:-all}"

# --- 2. Architecture Detection ---
# Extract specialized Docker image stage and binary directory from the preset.
if [ -f "CMakePresets.json" ]; then
    # We query CMake for the preset metadata. 
    # Use -N (dry-run) to get the configuration details including binaryDir.
    PRESET_INFO=$(cmake --preset "$PRESET" -N 2>/dev/null || true)
    
    if [ -z "$PRESET_INFO" ]; then
        echo "Error: Could not find or load preset '$PRESET'"
        exit 1
    fi

    STAGE=$(echo "$PRESET_INFO" | grep "CAFFEINE_BUILD_STAGE" | cut -d'=' -f2 | tr -d '"' | xargs)
    # Correctly extract the binary directory from the 'builds in' line
    BINARY_DIR=$(echo "$PRESET_INFO" | grep "builds in" | sed 's/.*builds in "\(.*\)"/\1/' | xargs)
fi

# Fallback defaults
STAGE="${STAGE:-build-native}"
BINARY_DIR="${BINARY_DIR:-build/$PRESET}"

# Convert relative BINARY_DIR to absolute path relative to /work for the build command
if [[ "$BINARY_DIR" != /* ]]; then
    BINARY_DIR="/work/$BINARY_DIR"
fi

REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-while-one}"
IMAGE_NAME="ghcr.io/${REPO_OWNER}/caffeine-build/${STAGE}:latest"

# --- 3. Environment Preparation ---
echo "--------------------------------------------------------------------------------"
echo " Image:      $IMAGE_NAME"
echo " Preset:     $PRESET"
echo " Target:     $TARGET"
echo " Binary Dir: $BINARY_DIR"
echo " Clean:      $CLEAN_BUILD"
echo "--------------------------------------------------------------------------------"

# Ensure we have the latest infrastructure image
docker pull "$IMAGE_NAME" || {
    echo "Error: Failed to pull build image. Check your internet connection or GHCR permissions."
    exit 1
}

# --- 4. Build Command Construction ---
if [ -f "CMakePresets.json" ]; then
    if [ "$TARGET" == "ctest" ]; then
        # We MUST run ctest from the actual binary directory for it to find the test driver.
        # We don't use --preset here because the Preset file is in the source dir, not build dir.
        CMD="cd $BINARY_DIR && ctest --output-on-failure"
    else
        CMD="cmake --preset $PRESET ${EXTRA_ARGS[*]} && \
             cmake --build $BINARY_DIR --target $TARGET"
    fi
else
    if [ "$TARGET" == "ctest" ]; then
        CMD="cd build && ctest --output-on-failure"
    else
        CMD="cmake -B build -DFETCHCONTENT_FULLY_DISCONNECTED=OFF ${EXTRA_ARGS[*]} && \
             cmake --build build --target $TARGET"
    fi
fi

# --- 5. Execution (Containerized) ---
CLEAN_CMD=""
if [ "$CLEAN_BUILD" = true ]; then
    # We clean the local binary directory relative to the host
    LOCAL_BINARY_DIR=${BINARY_DIR#/work/}
    CLEAN_CMD="rm -rf $LOCAL_BINARY_DIR && "
fi

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$(pwd)":/work \
    -w /work \
    "$IMAGE_NAME" \
    bash -c "${CLEAN_CMD}$CMD"
