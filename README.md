<p align="center">
  <a href="https://whileone.me">
    <img src="https://raw.githubusercontent.com/while-one/caffeine-build/main/assets/logo.png" alt="Caffeine Logo" width="50%">
  </a>
<h1 align="center">The Caffeine Framework</h1>
</p>

# Caffeine-Build

<p align="center">
  <img src="https://img.shields.io/badge/C-11-blue.svg?style=flat-square&logo=c" alt="C11">
  <img src="https://img.shields.io/badge/CMake-%23008FBA.svg?style=flat-square&logo=cmake&logoColor=white" alt="CMake">
  <a href="https://github.com/while-one/caffeine-build/tags">
    <img src="https://img.shields.io/github/v/tag/while-one/caffeine-build?style=flat-square&label=Release" alt="Latest Release">
  </a>
  <a href="https://github.com/while-one/caffeine-build/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/while-one/caffeine-build/ci.yml?style=flat-square&branch=main" alt="CI Status">
  </a>
  <a href="https://github.com/while-one/caffeine-build/commits/main">
    <img src="https://img.shields.io/github/last-commit/while-one/caffeine-build.svg?style=flat-square" alt="Last Commit">
  </a>
  <a href="https://github.com/while-one/caffeine-build/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/while-one/caffeine-build?style=flat-square&color=blue" alt="License: MIT">
  </a>
</p>

This repository is the centralized build and CI infrastructure for the **Caffeine Framework** ecosystem. It is designed to be consumed as a Git Submodule by all other repositories (`caffeine-hal`, `caffeine-hal-ports`, etc.) to ensure global consistency, ABI safety, and unified build orchestration.

## Core Architectural Pillars

### 1. Centralized Hardware Authority
Hardware target definitions (CPU cores, FPU settings, ABI flags, and linker script names) reside strictly within this repository in `cmake/ports/`. This ensures that every component in the ecosystem compiles with identical machine optimizations, preventing binary incompatibilities (e.g., mixing hard-float and soft-float) across the HAL, SAL, and Applications.

### 2. ABI Safety & Global Flag Injection
The framework automatically manages architecture-specific compiler flags.
*   **Automatic Detection**: When a project includes `CaffeineMacros.cmake`, it automatically loads the target definition based on the `CFN_HAL_PORT_TARGET` preset.
*   **Safe Injection**: Flags like `-mcpu` and `-mfpu` are injected globally using `add_compile_options()`, but **only** when `CMAKE_CROSSCOMPILING` is true. This allows the same code to be compiled for host simulation (mock tests) and real silicon (HIL) without manual configuration changes.

### 3. "Universe" CI Optimization
To minimize CI overhead, the framework introduces the **Universe Target** pattern. Instead of running formatting and documentation checks for every single MCU in a build matrix, the `ci-all-sources` preset enables a single-pass "Universe" validation that recursively catches every source and header file in the repository.

---

## Directory Structure

*   `cmake/ports/`: **The Hardware Authority**. Contains `<target>.cmake` files defining silicon properties (e.g., `stm32f417vgtx.cmake`).
*   `cmake/presets/`: Centralized CMake presets. `base.json` defines standard configurations for ARM, RISC-V, and Native builds.
*   `cmake/toolchains/`: CMake toolchain files for cross-compilation (e.g., `arm-gcc.cmake`).
*   `cmake/CaffeineMacros.cmake`: The core framework logic engine. Contains all shared build and quality gate functions.
*   `scripts/build.sh`: Containerized build orchestrator. Maps local PWD to `/work` in Docker and handles architecture detection.
*   `scripts/ci.sh`: Unified CI orchestrator. Manages sequential or parallel quality gates (Format, Analyze, Build, Test, Doc).
*   `config/coding/`: Standards definitions (`.clang-format`, `.clang-tidy`, `cppcheck-suppressions.txt`).

---

## Core Macro Reference (`CaffeineMacros.cmake`)

### `cfn_apply_target_architecture()`
*   **Behavior**: Automatically called on inclusion.
*   **Function**: Loads the `.cmake` file from `cmake/ports/` matching the current target and applies global compiler flags if cross-compiling.

### `cfn_add_universe_targets()`
*   **Behavior**: Must be called explicitly in `CMakeLists.txt`.
*   **Function**: Recursively globs all `src` and `include` files to create `${PROJECT_NAME}-universe-format`.

### `cfn_add_code_quality_targets(TARGET_NAME ...)`
*   **Behavior**: Standardizes static analysis.
*   **Args**: Supports `FORMAT_SOURCES`, `ANALYSIS_SOURCES`, and custom `TIDY_ARGS`.

### `cfn_add_docs(TARGET_NAME INPUTS ...)`
*   **Behavior**: Standardizes single-pass Doxygen generation.
*   **Requirement**: Requires an explicit list of `INPUTS` (e.g., `${CFN_UNIVERSE_SOURCES}`).

---

## Usage & Workflows

### Unified Build Orchestration
Use `build.sh` to trigger compilation inside the standardized Caffeine Docker environment:
```bash
# Build for a specific target with a clean state
./caffeine-build/scripts/build.sh --clean stm32f417vg-release all

# Build using local dependency overrides (Local Mounts)
./caffeine-build/scripts/build.sh --mount $(pwd)/../caffeine-hal:/caffeine-hal unit-tests-local
```

### Full CI Validation
Run the complete quality gate (Format -> Analyze -> Build -> Test -> Doc) locally:
```bash
# Optimized validation using the Universe preset
./caffeine-build/scripts/ci.sh all
```

---

## Support the Gallery

While this library is no Mondrian, it deals with a different form of **abstraction art**. Hardware abstraction is a craft of its own—one that keeps your application code portable and your debugging sessions short.

Whether **Caffeine** is fueling an elegant embedded project or just helping you wake up your hardware, you can contribute in the following ways:

*   **Star and Share:** If you find this project useful, give it a ⭐ on GitHub and share it with your fellow firmware engineers. It helps others find the library and grows the Caffeine community.
*   **Show and Tell:** If you are using Caffeine in a project (personal or professional), let me know! Hearing how it's being used is a motivator.
*   **Propose Features:** If the library is missing a specific "brushstroke," let's design the interface together.
*   **Port New Targets:** Help us expand the collection by porting the HAL to new silicon or peripheral sets.
*   **Expand the HIL Lab:** Contributions go primarily toward acquiring new development boards. These serve as dedicated **Hardware-in-the-Loop** test targets, ensuring every commit remains rock-solid across our entire fleet of supported hardware.

**If my projects helped you, feel free to buy me a brew. Or if it caused you an extra debugging session, open a PR!**

<a href="https://www.buymeacoffee.com/whileone" target="_blank">
  <img src="https://img.shields.io/badge/Caffeine%20me--0077ff?style=for-the-badge&logo=buy-me-a-coffee&logoColor=white" 
       height="40" 
       style="border-radius: 5px;">
</a>&nbsp;&nbsp;&nbsp;&nbsp;
<a href="https://github.com/sponsors/while-one" target="_blank">
<img src="https://img.shields.io/badge/Sponsor--ea4aaa?style=for-the-badge&logo=github-sponsors" height="40" style="border-radius: 5px;"> </a>&nbsp;&nbsp;&nbsp;
<a href="https://github.com/while-one/caffeine-build/compare" target="_blank">
<img src="https://img.shields.io/badge/Open%20a%20PR--orange?style=for-the-badge&logo=github&logoColor=white" height="40" style="border-radius: 5px;">
</a>

---

## License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.
