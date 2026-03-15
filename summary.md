# Caffeine Framework Refactoring Summary

## Overview of Changes

The build infrastructure across the Caffeine Framework has been successfully decoupled and centralized into a new repository, `caffeine-build`. This ensures a single source of truth for toolchains, generic hardware presets, coding standards, and build scripts. 

### 1. `caffeine-build` Repository Setup
- **Toolchains & Presets:** Migrated `cmake/toolchains` and `cmake/presets/base.json` (and other generic bases) from `caffeine-hal-ports`.
- **Coding Standards:** Centralized `.clang-format` and `.clang-tidy` into `config/coding/`.
- **Build Scripts:** Consolidated `build-local.sh` from `hal` and `hal-ports` into a unified `scripts/build.sh`. This script handles both `CMakePresets.json` (for apps/ports) and standard CMake builds (for `hal`).
- **CMake Macros:** Created `cmake/CaffeineMacros.cmake` containing `cfn_add_firmware()` to automate the generation of `.hex`/`.bin` files and memory size printing.
- **Documentation:** Created `README.md` and `SKILL.md` to document the purpose and usage of the build infrastructure for both human developers and AI agents.

### 2. Ecosystem Restructuring
All repositories in the ecosystem (`caffeine-hal`, `caffeine-hal-ports`, `caffeine-template`, `caffeine-app-hil`, `caffeine-services`) were updated to use `caffeine-build` as a Git Submodule:
- **`caffeine-hal-ports`:** 
  - Purged local toolchains, generic presets, and build scripts.
  - Updated `CMakeLists.txt` to inject the absolute path of linker scripts as an `INTERFACE` property via `target_link_options`. Applications linking to `caffeine::hal-ports` automatically inherit the required linker scripts and CPU flags.
  - Updated custom tool targets (`caffeine-hal-ports-format`, `caffeine-hal-ports-tidy`) to use the submodule's config files.
- **`caffeine-hal`:** 
  - Purged local coding standards and build scripts.
  - Updated custom tool targets to use the submodule's config files.
- **Applications & Templates:** 
  - Added the submodule.
  - Updated `CMakePresets.json` files to inherit from `caffeine-build/cmake/presets/base.json`.
  - Updated `CMakeLists.txt` files to include `caffeine-build/cmake/CaffeineMacros.cmake` and documented the usage of `cfn_add_firmware()`.
  - Updated `README.md` instructions to refer to the new `caffeine-build/scripts/build.sh`.

### 3. Docker Infrastructure Migration
- **Dockerfile & Publish Workflow:** Moved the `Dockerfile` and `.github/workflows/docker-publish.yml` from `caffeine-hal` into `caffeine-build`.
- **Scripts & CI:** Updated the `build.sh` script and CI workflows across the ecosystem to reference the new `ghcr.io/.../caffeine-build/` container images.

### 4. Documentation & Agent Skills
- **Common README Header:** Standardized the top common header (logo and status badges) across all repositories. Badges are correctly linked to the respective repository's releases, CI, and commits.
- **SKILL.md Everywhere:** Created or updated `SKILL.md` in all repositories to provide descriptive, pedantic instructions for future developers and AI coding agents. These files enforce the Caffeine Framework's philosophy, coding standards (C11, Allman style), and the new submodule-based build architecture.

---

## Uncertainties and Required Checks

While the architectural restructuring is complete, the following items require manual verification or testing to ensure absolute parity and stability:

1. **GitHub Actions Submodule Checkout:**
   - In the CI workflows (`.github/workflows/ci.yml`) across all repositories, the `actions/checkout@v4` step has been updated to include `submodules: recursive`. This should work seamlessly since the repositories are public.
2. **`CMakePresets.json` Path Resolution in IDEs:**
   - The presets in applications include `caffeine-build/cmake/presets/base.json`. We need to verify that IDEs like CLion and VSCode properly resolve these paths natively immediately after a `git clone --recursive`.
3. **Linker Script Path Injection:**
   - In `caffeine-hal-ports`, the absolute path to the linker script is generated using `${CMAKE_CURRENT_LIST_DIR}/../../../linker/${CAFFEINE_BOARD_LINKER}`. We need to verify that CMake successfully resolves and propagates this path to consuming applications without triggering "File not found" errors during the linking phase.

---

## Missing Items / Manual Action Required

The following items must be performed manually by the user:

1. **Delete Old Docker Images:**
   - The old Docker images hosted under the `caffeine-hal` package registry on GitHub Container Registry (`ghcr.io`) must be manually deleted via the GitHub UI, as this cannot be automated via git.
2. **Pushing Commits:**
   - You must push the `caffeine-build` repository to `origin main` *before* pushing the changes in the other repositories, so the submodules can correctly resolve the hashes.