#!/bin/bash
set -e

# ==============================================================================
# Caffeine Framework Unified CI Orchestrator (Parallel Matrix Ready)
# ==============================================================================

PROJECT_ROOT=$(pwd)
BUILD_SCRIPT="${PROJECT_ROOT}/caffeine-build/scripts/build.sh"

if [ ! -f "CMakePresets.json" ]; then
    echo "Error: CMakePresets.json not found in $(pwd)"
    exit 1
fi

# 1. Configuration & Argument Parsing
# Command: list, format, analyze, build, test, all (default)
COMMAND="${1:-all}"
SPECIFIC_PRESET="$2"

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

# 2. Preset Discovery
# The output starts with two spaces then the preset name in double quotes
ALL_PRESETS=$(cmake --list-presets | grep -E "^  \"" | cut -d'"' -f2 | grep -v "^base-")

# 3. Command Execution Logic
run_stage() {
    local PRESET=$1
    local STAGE=$2
    
    # Query metadata natively
    PRESET_METADATA=$(cmake --preset "$PRESET" -N 2>/dev/null || true)
    if [ -z "$PRESET_METADATA" ]; then
        echo ">>> Skipping Preset: $PRESET (Configuration failed - likely missing toolchain)"
        return 0
    fi

    BUILD_TESTS=$(echo "$PRESET_METADATA" | grep "CFN_BUILD_TESTS" | cut -d'=' -f2 | tr -d '"' | xargs || echo "OFF")

    case "$STAGE" in
        format)
            echo ">>> [Format] Validating Preset: $PRESET"
            $BUILD_SCRIPT --clean "$PRESET" "${PROJECT_NAME}-format" -DFORMAT_DRY_RUN=ON
            ;;
        analyze)
            echo ">>> [Analyze] Validating Preset: $PRESET"
            $BUILD_SCRIPT "$PRESET" "${PROJECT_NAME}-analyze"
            ;;
        build)
            echo ">>> [Build] Validating Preset: $PRESET"
            $BUILD_SCRIPT "$PRESET" all
            ;;
        test)
            if [ "$BUILD_TESTS" == "ON" ]; then
                echo ">>> [Test] Validating Preset: $PRESET"
                if cmake --list-presets=test | grep -q "\"$PRESET\""; then
                    $BUILD_SCRIPT "$PRESET" ctest
                else
                    $BUILD_SCRIPT "$PRESET" ctest unit-tests-gtest
                fi
            else
                echo ">>> [Test] Skipping Preset: $PRESET (Tests not enabled)"
            fi
            ;;
        *)
            echo "Error: Unknown CI stage '$STAGE'"
            exit 1
            ;;
    esac
}

# 4. Dispatcher
if [ "$COMMAND" == "list" ]; then
    # Generate JSON matrix for GitHub Actions
    echo "$ALL_PRESETS" | python3 -c "
import json, subprocess, sys
presets = []
for line in sys.stdin:
    p = line.strip()
    if not p: continue
    try:
        res = subprocess.run(['cmake', '--preset', p, '-N'], capture_output=True, text=True)
        build_tests = 'ON' if 'CFN_BUILD_TESTS=\"ON\"' in res.stdout else 'OFF'
        presets.append({'name': p, 'tests': build_tests == 'ON'})
    except:
        continue
print(json.dumps(presets))
"
    exit 0
fi

if [ "$COMMAND" == "all" ]; then
    echo "--------------------------------------------------------------------------------"
    echo " Starting Unified CI (Sequential) for project: $PROJECT_NAME"
    echo "--------------------------------------------------------------------------------"
    for P in $ALL_PRESETS; do
        run_stage "$P" format
        run_stage "$P" analyze
        run_stage "$P" build
        run_stage "$P" test
    done
elif [ -n "$SPECIFIC_PRESET" ]; then
    run_stage "$SPECIFIC_PRESET" "$COMMAND"
else
    # Run specific stage for all presets
    for P in $ALL_PRESETS; do
        run_stage "$P" "$COMMAND"
    done
fi
