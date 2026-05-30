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
from pathlib import Path

def clean_build_dir():
    """Attempts to remove the build directory. Warns if sudo is needed."""
    build_dir = Path("build")
    if build_dir.exists():
        print(f"--- Cleaning {build_dir} ---")
        try:
            # Using rm -rf is often more robust than shutil.rmtree for mounted volumes
            subprocess.run(["rm", "-rf", str(build_dir)], check=True)
        except Exception as e:
            print(f"Error cleaning build directory: {e}")
            print("Please try running: sudo rm -rf build/")
            sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Run Caffeine CI locally using 'act'")
    parser.add_argument("--job", default="framework-ci", help="GitHub Action job to run")
    parser.add_argument("--image", default="caffeine-runner:latest", help="Docker image for the runner")
    parser.add_argument("--pull", action="store_true", help="Pull the docker image before running")
    parser.add_argument("act_args", nargs=argparse.REMAINDER, help="Additional arguments for 'act'")
    
    args = parser.parse_args()
    
    # 1. Enforce strict isolation
    clean_build_dir()
    
    # 2. Capture Host Identity
    uid = os.getuid()
    gid = os.getgid()
    
    # 3. Construct 'act' command string
    act_cmd = f'act -j {args.job} -P ubuntu-24.04={args.image} -v /var/run/docker.sock:/var/run/docker.sock ' \
              f'-e HOST_UID={uid} -e HOST_GID={gid} -e CAFFEINE_CI=true'
    
    if not args.pull:
        act_cmd += " --pull=false"
        
    if args.act_args:
        act_cmd += " " + " ".join(args.act_args)
        
    print(f"--- Launching Local CI (act) as {uid}:{gid} ---")
    print(f"--- Command: {act_cmd} ---")
    try:
        # Using shell=True to let the shell handle the argument parsing which 'act' expects
        result = subprocess.run(act_cmd, shell=True)
        sys.exit(result.returncode)
    except FileNotFoundError:
        print("Error: 'act' command not found. Please install it: https://github.com/nektos/act")
        sys.exit(1)
    except Exception as e:
        print(f"Error executing act: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
