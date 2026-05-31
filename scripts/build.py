#!/usr/bin/env python3
"""
Caffeine Framework Unified Build Orchestrator
Handles execution of CMake targets inside isolated Docker containers.
"""

import argparse
import subprocess
import sys
import os
import shutil
import shlex
from pathlib import Path

# Add caffeine_utils to path
sys.path.append(str(Path(__file__).resolve().parent))
import caffeine_utils

if sys.version_info < (3, 7):
    sys.exit("Error: Python 3.7+ required")

from typing import Optional, List


class CaffeineBuilder:
    def __init__(self, args: argparse.Namespace) -> None:
        self.preset_name = args.preset
        self.use_local = args.use_local

        # If use_local is passed, we automatically target the -local variant
        if self.use_local and not self.preset_name.endswith("-local"):
            self.preset_name = f"{self.preset_name}-local"

        self.target = args.target
        self.mode = args.mode
        self.clean = args.clean
        self.mounts = args.mount or []
        self.extra_args = args.extra_args or []

        # Determine paths and environment
        self.ci_mode = (
            os.environ.get("CAFFEINE_CI", "false").lower() == "true"
            or "GITHUB_ACTIONS" in os.environ
        )
        self.workspace = Path("/work")
        self.host_workspace = Path.cwd()

        # Load metadata from CMakePresets.json and CMakeUserPresets.json
        self._load_preset_data()

    def _load_preset_data(self) -> None:
        """Extracts build stage and binary directory from presets, following inheritance."""
        self.stage = "build-native"
        self.binary_dir: Optional[Path] = None
        self.automounts: List[str] = []

        presets_map = caffeine_utils.load_all_presets()
        merged = caffeine_utils.resolve_preset_inheritance(
            self.preset_name, presets_map
        )

        cache_vars = merged.get("cacheVariables", {})
        if "CAFFEINE_BUILD_STAGE" in cache_vars:
            self.stage = cache_vars["CAFFEINE_BUILD_STAGE"]

        if "binaryDir" in merged:
            raw_bin_dir = merged["binaryDir"]
            raw_bin_dir = raw_bin_dir.replace("${sourceDir}", str(self.host_workspace))
            raw_bin_dir = raw_bin_dir.replace("${presetName}", self.preset_name)
            self.binary_dir = self._normalize_path(raw_bin_dir)

        # Accumulate automounts
        vendor_caffeine = merged.get("vendor", {}).get("caffeine", {})
        for m in vendor_caffeine.get("mounts", []):
            host_path = m.get("host_path")
            container_path = m.get("container_path")
            if host_path and container_path:
                self.automounts.append(f"{host_path}:{container_path}")

        # Fallback for binaryDir if never found in inheritance tree
        if not self.binary_dir:
            self.binary_dir = self.workspace / "build" / self.preset_name

        # Merge accumulated automounts
        self.mounts.extend(self.automounts)

        repo_owner = os.environ.get("GITHUB_REPOSITORY_OWNER", "while-one")
        digest = os.environ.get("CAFFEINE_DOCKER_DIGEST")
        if self.ci_mode and digest:
            self.image = (
                f"ghcr.io/{repo_owner}/caffeine-build/{self.stage}@sha256:{digest}"
            )
        else:
            self.image = f"ghcr.io/{repo_owner}/caffeine-build/{self.stage}:latest"

    def _normalize_path(self, raw_path: str) -> Path:
        """Ensures a path is absolute relative to the /work container workspace."""
        p = Path(raw_path)

        # If it's absolute and matches the host workspace, convert to /work
        if p.is_absolute():
            try:
                relative = p.relative_to(self.host_workspace)
                return self.workspace / relative
            except ValueError:
                # It's absolute but not in our workspace
                return p

        # If it's relative, just join with /work
        return self.workspace / p

    def run_docker(self, bash_cmd: str) -> int:
        """Executes a bash command string inside the Caffeine build container."""
        if not shutil.which("docker"):
            print("Error: 'docker' not found. Please install Docker.")
            return 1

        result = subprocess.run(["docker", "info"], capture_output=True)
        if result.returncode != 0:
            print("Error: Docker daemon is not running.")
            return 1

        mount_args = []
        for m in self.mounts:
            if ":" not in m:
                print(f"Error: Invalid mount format '{m}'. Use src:dst.")
                return 1
            src, dst = m.split(":", 1)
            mount_args.extend(["-v", f"{Path(src).resolve()}:{dst}"])

        # Fix root ownership: prioritize HOST_UID/GID from environment
        uid = os.environ.get("HOST_UID", str(os.getuid()))
        gid = os.environ.get("HOST_GID", str(os.getgid()))

        tty_flag = ["-t"] if sys.stdin.isatty() else []

        docker_cmd = (
            ["docker", "run", "--rm"]
            + tty_flag
            + [
                "--user",
                f"{uid}:{gid}",
                "-v",
                f"{self.host_workspace}:/work",
                "-w",
                "/work",
                "-e",
                f"CAFFEINE_CI={str(self.ci_mode).lower()}",
            ]
            + mount_args
            + [self.image, "bash", "-c", bash_cmd]
        )

        print(
            "--------------------------------------------------------------------------------"
        )
        print(f" Image:      {self.image}")
        print(f" Preset:     {self.preset_name}")
        print(f" Target:     {self.target}")
        print(f" Binary Dir: {self.binary_dir}")
        print(f" Clean:      {self.clean}")
        if self.use_local:
            print(" Mode:       Local Overrides Active")
        print(
            "--------------------------------------------------------------------------------"
        )

        try:
            # We use check=False because we want to handle the return code ourselves
            result = subprocess.run(docker_cmd, timeout=3600)
            return result.returncode
        except Exception as e:
            print(f"Error executing Docker: {e}")
            return 1

    def build(self) -> int:
        """Constructs and executes the build pipeline."""
        cmd_chain = []

        # 1. Handle Clean
        if self.clean:
            # If we don't have binary_dir yet, use a safe default for cleaning
            target_bin = self.binary_dir or (
                self.workspace / "build" / self.preset_name
            )
            try:
                relative_bin = target_bin.relative_to(self.workspace)
            except ValueError:
                print(
                    f"Error: Refusing to clean path outside workspace bounds: {target_bin}"
                )
                return 1

            # Strict boundary check against path traversal elements
            if ".." in relative_bin.parts:
                print(
                    f"Error: Refusing to clean path with traversal attempts: {relative_bin}"
                )
                return 1

            cmd_chain.append(f"rm -rf -- {shlex.quote(str(relative_bin))}")

        # 2. Construction logic
        # Force color diagnostics for native output
        quoted_extra = [shlex.quote(arg) for arg in self.extra_args]
        extra = " ".join(quoted_extra + ["-D CMAKE_COLOR_DIAGNOSTICS=ON"])

        configure_cmd = f"cmake --preset {shlex.quote(self.preset_name)} {extra}"

        if self.mode == "test":
            cmd_chain.append(configure_cmd)
            cmd_chain.append(f"cmake --build {shlex.quote(str(self.binary_dir))}")
            target_arg = shlex.quote(self.target) if self.target != "all" else ""
            cmd_chain.append(
                f"ctest --preset {shlex.quote(self.preset_name)} --output-on-failure {target_arg}"
            )
        else:
            # Standard Build
            cmd_chain.append(configure_cmd)
            cmd_chain.append(
                f"cmake --build {shlex.quote(str(self.binary_dir))} --target {shlex.quote(self.target)}"
            )

        full_cmd = " && ".join(cmd_chain)
        return self.run_docker(full_cmd)


def main() -> None:
    parser = argparse.ArgumentParser(description="Caffeine Build Engine")
    parser.add_argument("--preset", required=True, help="CMake preset")
    parser.add_argument("--target", default="all", help="CMake target")
    parser.add_argument(
        "--mode",
        default="build",
        choices=["configure", "build", "test"],
        help="Build mode",
    )
    parser.add_argument(
        "--clean", action="store_true", help="Clean build directory first"
    )
    parser.add_argument(
        "--use-local",
        action="store_true",
        help="Automatically use -local preset and mounts from CMakeUserPresets.json",
    )
    parser.add_argument(
        "--mount", action="append", help="Docker volume mounts (src:dst)"
    )
    parser.add_argument(
        "extra_args", nargs=argparse.REMAINDER, help="Additional CMake args"
    )

    args = parser.parse_args()
    builder = CaffeineBuilder(args)

    exit_code = builder.build()

    # Summary
    GREEN = "\033[0;32m"
    RED = "\033[0;31m"
    NC = "\033[0m"

    print(
        "--------------------------------------------------------------------------------"
    )
    if exit_code == 0:
        print(f"{GREEN}All builds passed{NC}")
    else:
        print(f"{RED}Target failed: {args.target} ({args.preset}){NC}")
    print(
        "--------------------------------------------------------------------------------"
    )

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
