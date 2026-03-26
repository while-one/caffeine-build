#!/bin/bash
set -e

# ==============================================================================
# Caffeine Framework Unified CI Orchestrator
# ==============================================================================

PROJECT_ROOT=$(pwd)
BUILD_SCRIPT="${PROJECT_ROOT}/caffeine-build/scripts/build.sh"

if [ ! -f "CMakePresets.json" ]; then
    echo "Error: CMakePresets.json not found in $(pwd)"
    exit 1
fi

# Get project name from CMakeLists.txt
PROJECT_NAME=$(python3 -c "
import re
with open('CMakeLists.txt') as f:
    content = f.read()
    match = re.search(r'project\s*\(\s*([a-zA-Z0-9_-]+)', content, re.MULTILINE)
    if match:
        print(match.group(1))
")

if [ -z "$PROJECT_NAME" ]; then
    echo "Error: Could not identify project name in CMakeLists.txt"
    exit 1
fi

# Use cmake to list all available presets (handles inheritance and includes)
# The output starts with two spaces then the preset name in double quotes
ALL_PRESETS=$(cmake --list-presets | grep -E "^  \"" | cut -d'"' -f2 | grep -v "^base-")

echo "--------------------------------------------------------------------------------"
echo " Starting Unified CI for project: $PROJECT_NAME"
echo "--------------------------------------------------------------------------------"

if [ -z "$ALL_PRESETS" ]; then
    echo "Warning: No presets found to validate."
fi

for PRESET in $ALL_PRESETS; do
    # We query metadata inside the container via build.sh if needed, 
    # but for now we query natively to see if we should run tests.
    BUILD_TESTS=$(cmake --preset "$PRESET" -N 2>/dev/null | grep "CFN_BUILD_TESTS" | cut -d'=' -f2 | tr -d '"' | xargs || echo "OFF")
    
    echo ""
    echo ">>> Validating Preset: $PRESET (Tests: ${BUILD_TESTS:-OFF})"
    echo "--------------------------------------------------------------------------------"

    # 1. Format Check (Dry-run)
    echo "[1/4] Checking Formatting..."
    $BUILD_SCRIPT --clean "$PRESET" "${PROJECT_NAME}-format" -DFORMAT_DRY_RUN=ON

    # 2. Static Analysis
    echo "[2/4] Running Static Analysis..."
    $BUILD_SCRIPT "$PRESET" "${PROJECT_NAME}-analyze"

    # 3. Build All
    echo "[3/4] Building All Targets..."
    $BUILD_SCRIPT "$PRESET" all

    # 4. Run Tests (if enabled)
    if [ "$BUILD_TESTS" == "ON" ]; then
        echo "[4/4] Running Unit Tests..."
        $BUILD_SCRIPT "$PRESET" ctest
    else
        echo "[4/4] Skipping Unit Tests."
    fi
done

echo ""
echo "--------------------------------------------------------------------------------"
echo " Unified CI Completed Successfully!"
echo "--------------------------------------------------------------------------------"
