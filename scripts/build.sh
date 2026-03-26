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
    PRESET_INFO=$(cmake --preset "$PRESET" -N 2>/dev/null)
    STAGE=$(echo "$PRESET_INFO" | grep "CAFFEINE_BUILD_STAGE" | cut -d'=' -f2 | tr -d '"' | xargs)
    BINARY_DIR=$(echo "$PRESET_INFO" | grep "binaryDir" | cut -d'=' -f2 | tr -d '"' | xargs)
fi

# Fallback defaults
STAGE="${STAGE:-build-native}"
BINARY_DIR="${BINARY_DIR:-build/$PRESET}"

# Convert relative BINARY_DIR to absolute path relative to /work for the build command
# If BINARY_DIR is absolute (starts with /), we assume it's already mapped or correct.
# However, CMakePresets usually use ${sourceDir}, which becomes /work in the container.
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
# We use an array to maintain proper quoting when passing to bash -c
if [ -f "CMakePresets.json" ]; then
    # Modern Preset-based Workflow
    if [ "$TARGET" == "ctest" ]; then
        CMD="ctest --preset $PRESET --output-on-failure"
    else
        CMD="cmake --preset $PRESET ${EXTRA_ARGS[*]} && \
             cmake --build $BINARY_DIR --target $TARGET"
    fi
else
    # Standard Native Workflow
    if [ "$TARGET" == "ctest" ]; then
        CMD="cd build && ctest --output-on-failure"
    else
        CMD="cmake -B build -DFETCHCONTENT_FULLY_DISCONNECTED=OFF ${EXTRA_ARGS[*]} && \
             cmake --build build --target $TARGET"
    fi
fi

# --- 5. Execution (Containerized) ---
# We use --user to ensure files created in the volume match the host user's UID/GID
# this prevents "permission denied" or "git ownership" errors during FetchContent.
CLEAN_CMD=""
if [ "$CLEAN_BUILD" = true ]; then
    # We clean the local 'build' dir if it exists, or the specific BINARY_DIR if it's relative
    CLEAN_CMD="rm -rf build ${BINARY_DIR#/work/} && "
fi

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$(pwd)":/work \
    -w /work \
    "$IMAGE_NAME" \
    bash -c "${CLEAN_CMD}$CMD"
