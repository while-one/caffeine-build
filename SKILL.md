# Caffeine Build (caffeine-build) Context & Agent Guidelines

## 1. Project Context
`caffeine-build` is the unified build system repository for the entire Caffeine Framework ecosystem (`caffeine-hal`, `caffeine-hal-ports`, `caffeine-template`, and all future applications/middleware).

### Core Responsibilities
*   **Single Source of Truth for Build Infrastructure:** It contains the CMake toolchains, generic hardware presets, unified build scripts, and shared CMake macros.
*   **Decoupling:** It decouples the compiler discovery and linker scripts from the actual C code implementations (which reside in `caffeine-hal-ports` or application layers).
*   **Git Submodule Integration:** It is designed to be consumed purely as a **Git Submodule** by all other Caffeine repositories.

### Directory Structure
*   `cmake/toolchains/`: Contains cross-compiler definitions (e.g., `arm-gcc.cmake`, `riscv-gcc.cmake`). *Note: These files define **how** to compile, but must remain agnostic to specific silicon cores.*
*   `cmake/presets/`: Contains modular `CMakePresets.json` files that define vendor targets (e.g., STM32F407, GD32V).
*   `cmake/CaffeineMacros.cmake`: Contains global compiler options (e.g., `-Werror`, strict standard enforcement) to be reused by all consuming repositories, and utility functions like `cfn_add_firmware()` to automate generating `.hex`/`.bin` files and printing memory sizes.
*   `scripts/build.sh`: The unified orchestrator script that automatically wraps CMake builds inside Docker containers (for CI parity) or natively.
*   `Dockerfile` & `.github/workflows/docker-publish.yml`: These files manage the centralized build environment and are used to publish architecture-specific images to the GitHub Container Registry.
*   `config/`: Contains the global coding standards (`.clang-format` and `.clang-tidy`) shared across the ecosystem.

## 2. Ecosystem Standards & Documentation
All Caffeine repositories MUST maintain a consistent visual identity in their `README.md` files.

### A. README Header Mandate
Every `README.md` must include the standardized Caffeine logo and status badges at the very top. 
*   **Logo:** Points to `https://whileone.me`.
*   **Badges:** Must be updated to link to the specific repository where they reside (e.g., tags, CI status, last commit, and license). 
*   **Never Delete:** Do not remove the header when refactoring or updating documentation.

## 3. Agent Workflow Rules

When you are invoked to work on the build system or an application using it, you **must** adhere to the following rules:

### A. Submodule Awareness
*   **Path Resolution:** When generating code or writing CMake files in a consuming repository (like `caffeine-template`), you MUST reference build artifacts relative to the submodule directory (e.g., `caffeine-build/cmake/presets/base-arm.json` or `include(caffeine-build/cmake/CaffeineMacros.cmake)`).
*   **Never Duplicate:** Do not add new `CMakePresets.json` base files or `toolchain.cmake` files directly into an application's root directory. If a new architecture is needed, it must be added to `caffeine-build` first.

### B. CMake Constraints
*   **Preset Composition:** Applications define their own local `CMakePresets.json` which `include`s the required base preset from `caffeine-build`, and then creates a local preset inheriting from it to set the `CAFFEINE_MCU_MACRO` or `CAFFEINE_BOARD_LINKER`.
*   **Linker Script Resolution:** The linker scripts themselves live in `caffeine-hal-ports/linker/`. The generic presets in `caffeine-build` only define the filename (`CAFFEINE_BOARD_LINKER`). The `caffeine-hal-ports` CMake recipe is responsible for injecting the absolute path to that linker script via `target_link_options`.
*   **Global Compiler Options:** Applications and libraries MUST include `caffeine-build/cmake/CaffeineMacros.cmake` and apply `CAFFEINE_COMPILE_OPTIONS` to their targets to inherit the ecosystem's strict warning and optimization flags.

### C. Build Script Execution
*   When testing builds locally or in CI instructions, use the unified script located at the submodule path: `./caffeine-build/scripts/build.sh [--clean] <preset_name> <cmake_target>`.
*   **Incremental Builds:** The script persists the `build/` directory between runs.
*   **Clean Builds:** Use the `--clean` flag to force a full re-configuration and re-build.
*   Example: `./caffeine-build/scripts/build.sh linux-native caffeine-hal-ports-format`
*   Example (Clean): `./caffeine-build/scripts/build.sh --clean unit-tests-gtest all`