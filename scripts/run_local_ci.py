#!/usr/bin/env python3
"""
Caffeine Framework Local CI Runner
Orchestrates 'act' to run GitHub Actions locally with proper volume mapping and UID/GID preservation.
"""

import argparse
import os
import subprocess
import sys
import shutil
import json
from pathlib import Path

if sys.version_info < (3, 7):
    sys.exit("Error: Python 3.7+ required")


def clean_build_dir() -> None:
    """Attempts to remove the build directory. Warns if sudo is needed."""
    build_dirs = set()
    try:
        if Path("CMakePresets.json").exists():
            with open("CMakePresets.json", "r") as f:
                data = json.load(f)
                for preset in data.get("configurePresets", []):
                    binary_dir = preset.get("binaryDir", "")
                    if binary_dir:
                        # Extract the base directory if it uses ${sourceDir}/build/...
                        if binary_dir.startswith("${sourceDir}/"):
                            parts = binary_dir.replace("${sourceDir}/", "").split("/")
                            if parts and parts[0]:
                                build_dirs.add(parts[0])
                        else:
                            # fallback heuristic if it's just a name
                            parts = binary_dir.split("/")
                            # Filter out empty strings from absolute paths
                            valid_parts = [p for p in parts if p]
                            if valid_parts:
                                build_dirs.add(valid_parts[0])
    except Exception:
        pass

    if not build_dirs:
        build_dirs.add("build")

    for b_dir in sorted(build_dirs):
        build_dir = Path(b_dir)
        if build_dir.exists() and build_dir.is_dir():
            print(f"--- Cleaning {build_dir} ---")
            try:
                # Using rm -rf is often more robust than shutil.rmtree for mounted volumes
                subprocess.run(["rm", "-rf", "--", str(build_dir)], check=True)
            except Exception as e:
                print(f"Error cleaning build directory: {e}")
                print(f"Please try running: sudo rm -rf {build_dir}/")
                sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run Caffeine CI locally using 'act'")
    parser.add_argument(
        "--job", default="framework-ci", help="GitHub Action job to run"
    )
    parser.add_argument(
        "--image", default="caffeine-runner:latest", help="Docker image for the runner"
    )
    parser.add_argument(
        "--pull", action="store_true", help="Pull the docker image before running"
    )
    parser.add_argument(
        "act_args", nargs=argparse.REMAINDER, help="Additional arguments for 'act'"
    )

    args = parser.parse_args()

    if not shutil.which("act"):
        print(
            "Error: 'act' command not found. Please install it: https://github.com/nektos/act"
        )
        sys.exit(1)

    # 1. Enforce strict isolation
    clean_build_dir()

    # 2. Capture Host Identity
    uid = os.getuid()
    gid = os.getgid()

    # 3. Construct 'act' command list
    act_cmd = [
        "act",
        "-j",
        args.job,
        "-P",
        f"ubuntu-24.04={args.image}",
        "-v",
        "/var/run/docker.sock:/var/run/docker.sock",
        "--env",
        f"HOST_UID={uid}",
        "--env",
        f"HOST_GID={gid}",
        "--env",
        "CAFFEINE_CI=true",
    ]

    if not args.pull:
        act_cmd.append("--pull=false")

    if args.act_args:
        act_cmd.extend(args.act_args)

    print(f"--- Launching Local CI (act) as {uid}:{gid} ---")
    print(f"--- Command: {' '.join(act_cmd)} ---")
    try:
        result = subprocess.run(act_cmd, shell=False)
        sys.exit(result.returncode)
    except Exception as e:
        print(f"Error executing act: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
