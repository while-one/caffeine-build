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
            "CFN_HAL_PORT_VENDOR": "stm32",
            "CFN_HAL_PORT_FAMILY": "stm32f4",
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
