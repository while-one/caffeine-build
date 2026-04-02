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
DOCKER_MOUNTS=()

show_help() {
    echo "Caffeine Framework Build Orchestrator"
    echo ""
    echo "Usage: ./build.sh [OPTIONS] [PRESET] [TARGET]"
    echo ""
    echo "Options:"
    echo "  --help, -h          Show this help message and exit"
    echo "  --clean             Perform a clean build (removes binary directory first)"
    echo "  --mount <src:dst>   Inject a local directory into the Docker container"
    echo "                      (e.g., --mount $(pwd)/../caffeine-hal:/caffeine-hal)"
    echo "  -D<var>=<value>     Pass arbitrary CMake arguments"
    echo ""
    echo "Arguments:"
    echo "  PRESET              The CMake preset to use (default: linux-native)"
    echo "  TARGET              The CMake target to build (default: all)"
    echo ""
    echo "Examples:"
    echo "  # Simple build"
    echo "  ./caffeine-build/scripts/build.sh linux-native all"
    echo ""
    echo "  # Clean build for cross-compilation"
    echo "  ./caffeine-build/scripts/build.sh --clean stm32f407-release"
    echo ""
    echo "  # Build with local dependency override"
    echo "  ./caffeine-build/scripts/build.sh --mount $(pwd)/../caffeine-hal:/caffeine-hal stm32f4-mock-tests-local"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --help|-h) show_help; exit 0 ;;
        --clean) CLEAN_BUILD=true ;;
        --mount)
            # Split src and dst. src might be relative.
            IFS=':' read -r SRC DST <<< "$2"
            if [[ ! "$SRC" == /* ]]; then
                SRC=$(realpath "$SRC")
            fi
            DOCKER_MOUNTS+=("-v" "$SRC:$DST")
            shift
            ;;
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
    # Query preset details. Fallback to default naming if query fails.
    PRESET_INFO=$(cmake --preset "$PRESET" -N 2>/dev/null || true)
    
    if [ -n "$PRESET_INFO" ]; then
        STAGE=$(echo "$PRESET_INFO" | grep "CAFFEINE_BUILD_STAGE" | cut -d'=' -f2 | tr -d '"' | xargs)
        # Extract binary directory from 'builds in' line
        # CMake output: "  builds in "/home/user/repo/build/preset""
        BINARY_DIR=$(echo "$PRESET_INFO" | grep "builds in" | sed 's/.*builds in "\(.*\)"/\1/' | xargs)
    fi
fi

# Fallback defaults
STAGE="${STAGE:-build-native}"
BINARY_DIR="${BINARY_DIR:-build/$PRESET}"

# --- 3. Binary Directory Normalization ---
# In Docker, the sourceDir is ALWAYS /work.
# If the extracted BINARY_DIR is absolute, it might contain the host path.
# We must ensure it points to the /work path inside the container.
if [[ "$BINARY_DIR" == "$(pwd)"* ]]; then
    # Convert host-absolute path to /work relative path
    BINARY_DIR="/work/${BINARY_DIR#$(pwd)/}"
elif [[ "$BINARY_DIR" != /* ]]; then
    # Already relative, make absolute to /work
    BINARY_DIR="/work/$BINARY_DIR"
elif [[ "$BINARY_DIR" == "/work"* ]]; then
    # Already correct
    :
else
    # It's an absolute path that doesn't match PWD. 
    # This happens in CI or nested submodules. 
    # Best effort: if it ends with build/..., we use that.
    if [[ "$BINARY_DIR" == *"build/"* ]]; then
        SUBPATH=$(echo "$BINARY_DIR" | sed 's/.*build\//build\//')
        BINARY_DIR="/work/$SUBPATH"
    fi
fi

REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-while-one}"
IMAGE_NAME="ghcr.io/${REPO_OWNER}/caffeine-build/${STAGE}:latest"

# --- 4. Environment Preparation ---
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

# --- 5. Build Command Construction ---
if [ -f "CMakePresets.json" ]; then
    if [[ "$TARGET" == ctest* ]]; then
        CMD="$TARGET"
    else
        CMD="cmake --preset $PRESET ${EXTRA_ARGS[*]} && \
             cmake --build $BINARY_DIR --target $TARGET"
    fi
else
    if [[ "$TARGET" == ctest* ]]; then
        CMD="cd build && $TARGET"
    else
        CMD="cmake -B build -DFETCHCONTENT_FULLY_DISCONNECTED=OFF ${EXTRA_ARGS[*]} && \
             cmake --build build --target $TARGET"
    fi
fi

# --- 6. Execution (Containerized) ---
CLEAN_CMD=""
if [ "$CLEAN_BUILD" = true ]; then
    LOCAL_BINARY_DIR=${BINARY_DIR#/work/}
    if [ -z "$LOCAL_BINARY_DIR" ] || [ "$LOCAL_BINARY_DIR" == "/" ] || [ "$LOCAL_BINARY_DIR" == "." ]; then
        echo "Error: Refusing to clean unsafe directory: '$LOCAL_BINARY_DIR'"
        exit 1
    fi
    CLEAN_CMD="rm -rf $LOCAL_BINARY_DIR && "
fi

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$(pwd)":/work \
    "${DOCKER_MOUNTS[@]}" \
    -w /work \
    "$IMAGE_NAME" \
    bash -c "${CLEAN_CMD}$CMD"
