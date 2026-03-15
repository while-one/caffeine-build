# Caffeine Framework Refactoring Summary

## Overview of Changes

The build infrastructure across the Caffeine Framework has been successfully decoupled and centralized into a new repository, `caffeine-build`. This ensures a single source of truth for toolchains, generic hardware presets, coding standards, and build scripts.

### 1. `caffeine-build` Repository Setup
- **Toolchains & Presets:** Migrated `cmake/toolchains` and `cmake/presets/` (and other generic bases) from `caffeine-hal-ports`.
- **Coding Standards:** Centralized `.clang-format` and `.clang-tidy` into `config/coding/`.
- **Build Scripts:** Consolidated `build-local.sh` from `hal` and `hal-ports` into a unified `scripts/build.sh`. This script handles both `CMakePresets.json` (for apps/ports) and standard CMake builds (for `hal`) with robust Docker permission handling.
- **CMake Macros:** Created `cmake/CaffeineMacros.cmake` containing `cfn_add_firmware()` to automate the generation of `.hex`/`.bin` files and memory size printing.
- **Docker Infrastructure:** Moved the multi-stage `Dockerfile` and `docker-publish.yml` workflow to this repository. All build images are now hosted under the `caffeine-build` registry.
- **Versioning:** Established a SemVer-based versioning mechanism for the SDK.

### 2. Ecosystem Restructuring
All repositories in the ecosystem (`caffeine-hal`, `caffeine-hal-ports`, `caffeine-template`, `caffeine-app-hil`, `caffeine-services`) were updated to use `caffeine-build` as a Git Submodule:
- **`caffeine-hal-ports`:** 
  - Purged local toolchains, generic presets, and build scripts.
  - **Linker Script Encapsulation:** Updated to automatically export actual linker scripts via `INTERFACE` properties using absolute submodule paths. Applications linking to `caffeine::hal-ports` now inherit the memory map automatically.
- **Submodule Pinning:** All repositories now point to the **`v0.1.0` tag** of `caffeine-build` instead of the `main` branch, ensuring build stability across the framework.
- **Continuous Integration:** Standardized all `.github/workflows/ci.yml` files to use `submodules: recursive` and pull images from the `caffeine-build` GHCR registry.
- **Documentation & Skills:** Standardized README headers across all repositories and created comprehensive `SKILL.md` files to guide future developers and AI agents.

## Verification Status

| Target | Result | Repository |
| --- | --- | --- |
| **Linux Native** | `PASSED` | `caffeine-hal-ports`, `caffeine-template` |
| **STM32F417VG** | `PASSED` | `caffeine-hal-ports` |
| **Mock Tests** | `PASSED` | `caffeine-hal-ports` |
| **App Integration**| `PASSED` | `caffeine-app-hil` |

---

## Final Manual Actions Required

To synchronize these changes with GitHub, the owner must:

1.  **Push `caffeine-build` first:** Navigate to the `caffeine-build` repository and push the `refactor-build` branch.
2.  **Push other repositories:** Once `caffeine-build` is on the remote, push the updated branches for all other repositories.
3.  **Clean up GHCR:** Manually delete the old Docker images from the `caffeine-hal` package registry on GitHub.
