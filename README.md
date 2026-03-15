<p align="center">
  <a href="https://whileone.me">
    <img src="https://whileone.me/images/caffeine-small.png" alt="Caffeine Logo" width="384" height="384">
  </a>
</p>



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

# Caffeine-Build

This repository is the centralized build infrastructure for the **Caffeine Framework** ecosystem. It is designed to be consumed as a Git Submodule by all other repositories in the framework (`caffeine-hal`, `caffeine-hal-ports`, applications, and middleware).

## Purpose

By decoupling the build system from the code repositories, `caffeine-build` ensures:
1.  **Single Source of Truth:** CMake toolchains, hardware presets, and common macros are defined once.
2.  **IDE Compatibility:** Because it is cloned as a submodule before CMake runs, `CMakePresets.json` in consuming repositories can reliably inherit from `caffeine-build/cmake/presets/base-arm.json` without parsing errors in IDEs like CLion or VSCode.
3.  **Unified Build Scripts:** A single `scripts/build.sh` script orchestrates Dockerized or native cross-compilation identically across all projects.

## Directory Structure

*   `cmake/toolchains/`: Cross-compiler definitions (e.g., `arm-gcc.cmake`, `riscv-gcc.cmake`).
*   `cmake/presets/`: Modular `CMakePresets.json` files for vendor targets (e.g., STM32F407, GD32V).
*   `cmake/CaffeineMacros.cmake`: Helper functions (e.g., `cfn_add_firmware()`) to automate `.hex`/`.bin` generation.
*   `scripts/build.sh`: Unified build orchestrator.
*   `config/coding/`: Global coding standards (`.clang-format` and `.clang-tidy`).

## Usage in Applications

To use this build system in a new Caffeine application:

1.  Add this repository as a submodule:
    ```bash
    git submodule add https://github.com/while-one/caffeine-build.git caffeine-build
    ```
2.  Create a local `CMakePresets.json` that inherits from a build preset:
    ```json
    {
      "version": 4,
      "include": ["caffeine-build/cmake/presets/base-arm.json"],
      "configurePresets": [
        {
          "name": "app-stm32f407",
          "inherits": "base-arm",
          "cacheVariables": {
            "CAFFEINE_VENDOR": "stm32",
            "CAFFEINE_PORT_FAMILY": "stm32f4",
            "CAFFEINE_MCU_MACRO": "STM32F407xx",
            "CAFFEINE_BOARD_LINKER": "STM32F407VGTX_FLASH.ld"
          }
        }
      ]
    }
    ```
3.  Load the macros in your `CMakeLists.txt`:
    ```cmake
    include(caffeine-build/cmake/CaffeineMacros.cmake)
    # ... your targets ...
    cfn_add_firmware(my_target)
    ```

## Shared Ecosystem Standards

All repositories using `caffeine-build` inherit the framework's strict coding standards via the `config/` directory:
*   **Formatting:** Enforces a 120-column limit, 4-space indentation, and Allman-style braces.
*   **Static Analysis:** Enforces strict C11 compliance, memory safety rules (no dynamic allocation).

---

## Support

They say dealing with abstraction is a form of art, so I suppose that makes me an artist? Whether this caffeine fuels an elegant HAL or a deep debugging session, I appreciate you being part of the gallery.

If my projects helped you, buy me a brew or if the opposite open a PR!

<a href="https://www.buymeacoffee.com/whileone" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-blue.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

---

## License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.
