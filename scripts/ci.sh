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

show_help() {
    echo "Caffeine Framework Unified CI Orchestrator"
    echo ""
    echo "Usage: ./ci.sh [OPTIONS] <COMMAND> [PRESET]"
    echo ""
    echo "Options:"
    echo "  --help, -h          Show this help message and exit"
    echo "  --mount <src:dst>   Inject a local directory into the underlying build container"
    echo ""
    echo "Commands:"
    echo "  all                 Run format, analyze, build, test, and doc stages for all presets"
    echo "  list                Generate a JSON list of available presets (for GitHub Actions)"
    echo "  format              Run clang-format check"
    echo "  analyze             Run clang-tidy and cppcheck"
    echo "  build               Run compilation"
    echo "  test                Run unit tests"
    echo "  doc                 Run Doxygen documentation generation"
    echo ""
    echo "Arguments:"
    echo "  PRESET              (Optional) Only run the command for a specific preset"
    echo ""
    echo "Example:"
    echo "  ./ci.sh --mount $(pwd)/../caffeine-hal:/caffeine-hal all stm32f4-mock-tests-local"
}

# 1. Configuration & Argument Parsing
COMMAND=""
SPECIFIC_PRESET=""
EXTRA_BUILD_ARGS=()

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --help|-h) show_help; exit 0 ;;
        --mount)
            EXTRA_BUILD_ARGS+=("--mount" "$2")
            shift
            ;;
        -*) EXTRA_BUILD_ARGS+=("$1") ;;
        *)
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
            elif [ -z "$SPECIFIC_PRESET" ]; then
                SPECIFIC_PRESET="$1"
            else
                EXTRA_BUILD_ARGS+=("$1")
            fi
            ;;
    esac
    shift
done

COMMAND="${COMMAND:-all}"

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
# Uses a more robust regex to find the preset names in double quotes,
# filtering out hidden base presets.
ALL_PRESETS=$(cmake --list-presets | grep -oP '(?<=")[^"]+(?=")' | grep -v "^base-")

# 3. Command Execution Logic
run_stage() {
    local PRESET=$1
    local STAGE=$2
    
    case "$STAGE" in
        format)
            # Use universe target if available, otherwise fallback to standard format
            local TARGET="${PROJECT_NAME}-check-format"
            if [ "$PRESET" == "universe-all-sources" ]; then
                TARGET="${PROJECT_NAME}-universe-check-format"
            fi
            echo ">>> [Format] Validating Preset: $PRESET (Target: $TARGET)"
            $BUILD_SCRIPT --clean "$PRESET" "$TARGET" "${EXTRA_BUILD_ARGS[@]}"
            ;;
        analyze)
            echo ">>> [Analyze] Validating Preset: $PRESET"
            $BUILD_SCRIPT "$PRESET" "${PROJECT_NAME}-analyze" "${EXTRA_BUILD_ARGS[@]}"
            ;;
        build)
            echo ">>> [Build] Validating Preset: $PRESET"
            $BUILD_SCRIPT "$PRESET" all "${EXTRA_BUILD_ARGS[@]}"
            ;;
        test)
            # Run the test preset if it exists (standardized matching-name convention)
            if cmake --list-presets=test | grep -q "\"$PRESET\""; then
                echo ">>> [Test] Validating Preset: $PRESET"
                $BUILD_SCRIPT "$PRESET" "ctest --preset $PRESET" "${EXTRA_BUILD_ARGS[@]}"
            fi
            ;;
        doc)
            # Run doxygen documentation target. 
            echo ">>> [Docs] Validating Preset: $PRESET"
            $BUILD_SCRIPT "$PRESET" "${PROJECT_NAME}-docs" "${EXTRA_BUILD_ARGS[@]}"
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
        # Check if tests are enabled for this preset via metadata or name
        res = subprocess.run(['cmake', '--preset', p, '-N'], capture_output=True, text=True)
        has_tests = 'CFN_BUILD_TESTS=\"ON\"' in res.stdout
        
        # Also check if a test preset exists
        res_test = subprocess.run(['cmake', '--list-presets=test'], capture_output=True, text=True)
        test_exists = f'\"{p}\"' in res_test.stdout or p == 'unit-tests-gtest'
        
        presets.append({'name': p, 'tests': has_tests or test_exists})
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
    
    # 1. Global Stages (Optimization: Run once for all sources if preset exists)
    HAS_UNIVERSE=false
    if echo "$ALL_PRESETS" | grep -q "universe-all-sources"; then
        echo ">>> Detected 'universe-all-sources' preset. Running global stages..."
        HAS_UNIVERSE=true
        run_stage "universe-all-sources" format
        run_stage "universe-all-sources" doc
        # Filter out the universe preset for the matrix loop
        MATRIX_PRESETS=$(echo "$ALL_PRESETS" | grep -v "universe-all-sources")
    else
        echo ">>> No 'universe-all-sources' preset found. Falling back to matrix-based global stages."
        MATRIX_PRESETS=$ALL_PRESETS
    fi

    # 2. Matrix Stages (Analyze, Build, Test)
    for P in $MATRIX_PRESETS; do
        if [ "$HAS_UNIVERSE" = false ]; then
            # If no universe preset, we must run format/doc in the loop
            run_stage "$P" format
            run_stage "$P" doc
        fi
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
