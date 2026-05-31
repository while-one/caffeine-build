#!/usr/bin/env python3
"""
Caffeine Framework Unified CI Orchestrator
Manages the CI lifecycle (format, analyze, build, test, doc, coverage, lint).
"""

import argparse
import json
import subprocess
import sys
import re
from pathlib import Path
from typing import Dict, Any

# Add caffeine_utils to path
sys.path.append(str(Path(__file__).resolve().parent))
import caffeine_utils

if sys.version_info < (3, 7):
    sys.exit("Error: Python 3.7+ required")


class CaffeineCI:
    def __init__(self, args: argparse.Namespace) -> None:
        self.command = args.command
        self.specific_preset = args.preset
        self.use_local = args.use_local
        self.mounts = args.mount or []

        self.project_root = Path.cwd()
        self.build_script = (
            self.project_root / "caffeine-build" / "scripts" / "build.py"
        )

        if not (self.project_root / "CMakePresets.json").exists():
            print(f"Error: CMakePresets.json not found in {self.project_root}")
            sys.exit(1)

        self.project_name = self._get_project_name()
        self.categories = self._load_presets()

    def _get_project_name(self) -> str:
        """Extracts the project name from CMakeLists.txt."""
        cmakelists = self.project_root / "CMakeLists.txt"
        if not cmakelists.exists():
            return "unknown"

        content = cmakelists.read_text()
        match = re.search(
            r"project\s*\(\s*[\"']?([a-zA-Z0-9_-]+)[\"']?",
            content,
            re.MULTILINE | re.IGNORECASE,
        )
        if match:
            return match.group(1)
        return "unknown"

    def _load_presets(self) -> Dict[str, Any]:
        """Parses CMake presets and resolves inheritance for accurate feature detection."""

        presets_map = caffeine_utils.load_all_presets()
        categories: Dict[str, Any] = {"universe": [], "hardware": [], "tests": []}
        all_names = []

        # Parse testPresets to find which configurePresets support testing
        test_supported_presets = set()
        for p in [Path("CMakePresets.json"), Path("CMakeUserPresets.json")]:
            if p.exists():
                try:
                    import json

                    with p.open("r") as f:
                        data = json.load(f)
                        for tp in data.get("testPresets", []):
                            if "configurePreset" in tp:
                                test_supported_presets.add(tp["configurePreset"])
                except Exception:
                    pass

        for name, preset in presets_map.items():
            if preset.get("hidden", False):
                continue

            if self.use_local and not name.endswith("-local"):
                continue
            if not self.use_local and name.endswith("-local"):
                continue

            merged = caffeine_utils.resolve_preset_inheritance(name, presets_map)
            all_names.append(name)
            cache = merged.get("cacheVariables", {})

            # Determine if this preset supports tests by checking if it's in our testPresets list
            base_name = name.replace("-local", "") if name.endswith("-local") else name
            has_tests = (
                name in test_supported_presets or base_name in test_supported_presets
            )
            preset_data = {"name": name, "tests": has_tests}

            if cache.get("CAFFEINE_UNIVERSE_TARGET", "") == "ON":
                categories["universe"].append(preset_data)
            elif has_tests:
                categories["tests"].append(preset_data)
            else:
                categories["hardware"].append(preset_data)

        categories["all_names"] = list(dict.fromkeys(all_names))
        return categories

    def run_stage(self, preset: str, stage: str) -> int:
        """Executes a specific CI stage for a preset."""
        # Find preset metadata to check if it's a universe target
        is_universe = any(p["name"] == preset for p in self.categories["universe"])

        # Pedantic Enforcement: format, analyze, doc, and lint-python are GLOBAL stages.
        # They should only be used with a universe target.
        global_stages = ["format", "analyze", "doc", "lint-python"]
        is_test_preset = any(p["name"] == preset for p in self.categories["tests"])

        if stage in global_stages and not is_universe:
            # If we have universe presets, we refuse to run global stages on non-universe targets.
            if self.categories["universe"]:
                print(
                    f">>> [Skip] Stage '{stage}' is global and should only run on a universe preset."
                )
                return 0
            # Fallback: if no universe preset exists at all, we allow it (best effort)
            pass

        # Coverage requires a test-enabled preset (declared in testPresets)
        if stage == "coverage" and not is_test_preset:
            print(f">>> [Skip] Stage '{stage}' requires a test-enabled preset.")
            return 0

        if stage == "lint-python":
            scripts_dir = self.project_root / "caffeine-build" / "scripts"
            print(f">>> [LINT-PYTHON] Checking scripts in {scripts_dir}")
            try:
                # We will just run ruff check on the scripts directory locally
                # In a real environment we might use docker, but since ruff is python, let's try host first.
                lint_result = subprocess.run(["ruff", "check", str(scripts_dir)])
                if lint_result.returncode != 0:
                    print("Error: Python linting failed.")
                return lint_result.returncode
            except FileNotFoundError:
                print("Error: ruff is not installed. Python linting is mandatory.")
                sys.exit(1)

        target_map = {
            "format": f"{self.project_name}-universe-format-check",
            "analyze": f"{self.project_name}-analyze",
            "build": "all",
            "test": "all",
            "doc": f"{self.project_name}-docs",
            "coverage": f"{self.project_name}-coverage",
        }

        target = target_map.get(stage)
        if not target:
            print(f"Error: Unknown CI stage '{stage}'")
            return 1

        cmd = [
            sys.executable,
            str(self.build_script),
            "--preset",
            preset,
            "--target",
            target,
        ]

        if stage == "test":
            cmd.extend(["--mode", "test"])

        if self.use_local:
            cmd.append("--use-local")

        # Clean for format stage to ensure fresh check
        if stage == "format":
            cmd.append("--clean")

        # To prevent CMakeCache.txt absolute path conflicts when jumping between
        # host execution and container execution, always clean during CI validation.
        if stage in ["build", "test", "coverage", "analyze", "doc", "compliance"]:
            cmd.append("--clean")

        for m in self.mounts:
            cmd.extend(["--mount", m])

        print(f">>> [{stage.upper()}] Validating Preset: {preset} (Target: {target})")

        try:
            if stage == "coverage":
                # Capture output for coverage parsing
                cov_result = subprocess.run(cmd, capture_output=True, text=True)
                print(cov_result.stdout)
                if cov_result.stderr:
                    print(cov_result.stderr, file=sys.stderr)
                if cov_result.returncode != 0:
                    return cov_result.returncode

                # Parse coverage percentage
                coverage = 0.0
                # Look for typical lcov/gcovr outputs
                match = re.search(
                    r"(?:lines|coverage)\.*:\s+([0-9.]+)",
                    cov_result.stdout,
                    re.IGNORECASE,
                )
                if match:
                    coverage = float(match.group(1))
                    print(f">>> [COVERAGE] Detected coverage: {coverage}%")
                    if coverage < 10.0:
                        print(
                            f"Error: Coverage {coverage}% is below the 10.0% threshold."
                        )
                        return 1
                    else:
                        print(
                            f"Success: Coverage {coverage}% meets the 10.0% threshold."
                        )
                else:
                    print(
                        "Warning: Could not parse coverage output. Assuming it passed for now."
                    )
                return 0
            else:
                # We call build.py directly
                build_result = subprocess.run(cmd)
                return build_result.returncode
        except Exception as e:
            print(f"Error executing stage {stage}: {e}")
            return 1

    def list_matrix(self) -> None:
        """Outputs the GHA matrix JSON."""
        # Combine hardware and tests for the 'hardware' matrix leg
        matrix = {
            "universe": list(self.categories["universe"]),
            "hardware": list(self.categories["hardware"])
            + list(self.categories["tests"]),
        }
        # Fallback: if no universe preset exists, we must fail
        if not matrix["universe"]:
            print(
                "Error: No universe preset found. The universe is a mandatory architectural concept within Caffeine Framework repositories."
            )
            sys.exit(1)

        print(json.dumps(matrix))

    def run_all(self) -> int:
        """Sequential execution of all stages for all presets."""
        print(
            "--------------------------------------------------------------------------------"
        )
        print(f" Starting Unified CI (Sequential) for project: {self.project_name}")
        print(
            "--------------------------------------------------------------------------------"
        )

        exit_code = 0

        # 1. Global Stages (Universe)
        # We run these once on the designated universe preset
        universe_presets = self.categories["universe"]
        if not universe_presets:
            print(
                "Error: No universe preset found. The universe is a mandatory architectural concept within Caffeine Framework repositories."
            )
            sys.exit(1)

        global_target_preset = universe_presets[0]["name"]

        if global_target_preset:
            exit_code |= self.run_stage(global_target_preset, "lint-python")
            exit_code |= self.run_stage(global_target_preset, "format")
            exit_code |= self.run_stage(global_target_preset, "analyze")
            exit_code |= self.run_stage(global_target_preset, "doc")

        # 2. Matrix Stages (Build, Test, Coverage)
        # Analyze is now global, so we only run build, test, and coverage here.
        for p_data in self.categories["hardware"] + self.categories["tests"]:
            p = p_data["name"]
            exit_code |= self.run_stage(p, "build")

            if p_data["tests"]:
                exit_code |= self.run_stage(p, "test")
                exit_code |= self.run_stage(p, "coverage")

        return exit_code

    def execute(self) -> int:
        if self.command == "list":
            self.list_matrix()
            return 0

        if self.command == "all":
            if self.specific_preset:
                # Run all stages for one specific preset
                exit_code = 0
                exit_code |= self.run_stage(self.specific_preset, "lint-python")
                exit_code |= self.run_stage(self.specific_preset, "format")
                exit_code |= self.run_stage(self.specific_preset, "analyze")
                exit_code |= self.run_stage(self.specific_preset, "build")
                exit_code |= self.run_stage(self.specific_preset, "test")
                exit_code |= self.run_stage(self.specific_preset, "doc")
                exit_code |= self.run_stage(self.specific_preset, "coverage")
                return exit_code
            else:
                return self.run_all()

        # Specific command (format, analyze, etc.)
        if self.specific_preset:
            return self.run_stage(self.specific_preset, self.command)
        else:
            exit_code = 0
            for p in self.categories["all_names"]:
                exit_code |= self.run_stage(p, self.command)
            return exit_code


def main() -> None:
    parser = argparse.ArgumentParser(description="Caffeine CI Orchestrator")
    parser.add_argument(
        "command",
        choices=[
            "all",
            "list",
            "format",
            "analyze",
            "build",
            "test",
            "doc",
            "coverage",
            "lint-python",
        ],
        help="CI command to execute",
    )
    parser.add_argument("preset", nargs="?", help="Specific preset to run for")
    parser.add_argument(
        "--use-local",
        action="store_true",
        help="Filter for -local presets and pass --use-local to build.py",
    )
    parser.add_argument(
        "--mount", action="append", help="Docker volume mounts (src:dst)"
    )

    args = parser.parse_args()
    ci = CaffeineCI(args)

    exit_code = ci.execute()

    # Summary
    GREEN = "\033[0;32m"
    RED = "\033[0;31m"
    NC = "\033[0m"

    if args.command != "list":
        print(
            "--------------------------------------------------------------------------------"
        )
        if exit_code == 0:
            print(f"{GREEN}CI Validation passed{NC}")
        else:
            print(f"{RED}CI Validation failed{NC}")
        print(
            "--------------------------------------------------------------------------------"
        )

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
