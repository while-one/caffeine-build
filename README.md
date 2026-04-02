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

This repository is the centralized build infrastructure for the **Caffeine Framework** ecosystem. It is designed to be consumed as a Git Submodule by all other repositories in the framework (`caffeine-hal`, `caffeine-hal-ports`, applications, and middleware).

## Purpose

By decoupling the build system from the code repositories, `caffeine-build` ensures:
1.  **Single Source of Truth:** CMake toolchains, hardware presets, and common macros are defined once.
2.  **IDE Compatibility:** Because it is cloned as a submodule before CMake runs, `CMakePresets.json` in consuming repositories can reliably inherit from `caffeine-build/cmake/presets/base.json`.
3.  **Unified Build Orchestration:** A standardized set of scripts (`build.sh`, `ci.sh`) ensures identical build and quality gate behavior locally and in CI.

## Directory Structure

*   `cmake/toolchains/`: Cross-compiler definitions (e.g., `arm-gcc.cmake`, `riscv-gcc.cmake`).
*   `cmake/presets/`: Centralized `base.json` containing shared configuration and test presets (`unit-tests-gtest`).
*   `cmake/CaffeineMacros.cmake`: Reusable functions (e.g., `cfn_add_firmware()`, `cfn_get_clang_tidy_extra_args()`).
*   `scripts/build.sh`: Main build orchestrator supporting incremental builds and custom binary dirs.
*   `scripts/ci.sh`: Unified CI script that supports granular commands for parallel matrix orchestration.
*   `config/coding/`: Global coding standards (`.clang-format`, `.clang-tidy`, `cppcheck-suppressions.txt`).

## Standardized Quality Gates

The repository provides two primary scripts for local and CI development:
- **`scripts/build.sh`**: Orchestrates builds for specific presets and targets.
- **`scripts/ci.sh`**: The unified quality gate orchestrator.

## Usage & Workflows

### 1. Basic Build Commands
Use `build.sh` to trigger compilation for a specific target and preset:
```bash
# Build everything for the native Linux preset
./caffeine-build/scripts/build.sh linux-native all

# Perform a clean build for an ARM target
./caffeine-build/scripts/build.sh --clean stm32f407-release
```

### 2. Full CI Validation
Run the complete quality gate (Format -> Analyze -> Build -> Test -> Doc) locally:
```bash
# Validate all presets
./caffeine-build/scripts/ci.sh all

# Validate only a specific preset
./caffeine-build/scripts/ci.sh all stm32f4-mock-tests
```

### 3. Developing with Local Dependencies (Local Mounts)
If you are iterating on multiple framework repositories simultaneously (e.g., adding a feature to `caffeine-hal` and testing it in `caffeine-hal-ports`), you can use the `--mount` flag to inject your local changes into the Docker build container without committing.

**Workflow:**
1.  In your project (e.g., `caffeine-hal-ports`), create a `CMakeUserPresets.json` that overrides the dependency path:
    ```json
    {
      "version": 4,
      "configurePresets": [
        {
          "name": "local-dev",
          "inherits": "stm32f4-mock-tests",
          "cacheVariables": {
            "FETCHCONTENT_SOURCE_DIR_CAFFEINE-HAL": "/caffeine-hal"
          }
        }
      ]
    }
    ```
2.  Run the build or CI script with the `--mount` flag to map your host directory to the path expected by CMake:
    ```bash
    ./caffeine-build/scripts/ci.sh --mount $(pwd)/../caffeine-hal:/caffeine-hal all local-dev
    ```

## Usage in Applications

1.  Add this repository as a submodule: `git submodule add https://github.com/while-one/caffeine-build.git caffeine-build`
2.  Inherit from `base.json` in your local `CMakePresets.json`:
    ```json
    {
      "include": ["caffeine-build/cmake/presets/base.json"],
      "configurePresets": [
        {
          "name": "my-target",
          "inherits": "base-arm",
          "cacheVariables": {
            "CFN_HAL_PORT_VENDOR": "stm32",
            "CFN_HAL_PORT_FAMILY": "stm32f4",
            "CFN_HAL_PORT_TARGET": "stm32f417vgtx"
          }
        }
      ]
    }
    ```

---

## Support the Gallery

While this library is no Mondrian, it deals with a different form of **abstraction art**. Hardware abstraction is a craft of its own—one that keeps your application code portable and your debugging sessions short.

Whether **Caffeine** is fueling an elegant embedded project or just helping you wake up your hardware, you can contribute in the following ways:

* **Star & Share:** If you find this project useful, give it a ⭐ on GitHub and share it with your fellow firmware engineers. It helps others find the library and grows the Caffeine community.
* **Show & Tell:** If you are using Caffeine in a project (personal or professional), **let me know!** Hearing how it's being used is a huge motivator.
* **Propose Features:** If the library is missing a specific "brushstroke," let's design the interface together.
* **Port New Targets:** Help us expand the collection by porting the HAL to new silicon or peripheral sets.
* **Expand the HIL Lab:** Contributions go primarily toward acquiring new development boards. These serve as dedicated **Hardware-in-the-Loop** test targets, ensuring every commit remains rock-solid across our entire fleet of supported hardware.

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
