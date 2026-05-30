#!/usr/bin/env python3
"""
Caffeine Framework Unified Build Orchestrator
Handles execution of CMake targets inside isolated Docker containers.
"""
import argparse
import subprocess
import sys
import os
import json
from pathlib import Path

class CaffeineBuilder:
    def __init__(self, args):
        self.preset_name = args.preset
        self.use_local = args.use_local
        
        # If use_local is passed, we automatically target the -local variant
        if self.use_local and not self.preset_name.endswith("-local"):
            self.preset_name = f"{self.preset_name}-local"

        self.target = args.target
        self.clean = args.clean
        self.mounts = args.mount or []
        self.extra_args = args.extra_args or []
        
        # Determine paths and environment
        self.ci_mode = os.environ.get("CAFFEINE_CI", "false").lower() == "true" or "GITHUB_ACTIONS" in os.environ
        self.workspace = Path("/work")
        self.host_workspace = Path.cwd()
        
        # Load metadata from CMakePresets.json and CMakeUserPresets.json
        self._load_preset_data()
        
    def _load_preset_data(self):
        """Extracts build stage and binary directory from presets, following inheritance."""
        self.stage = "build-native"
        self.binary_dir = None
        self.automounts = []
        
        # Load all presets into a flat map for easier inheritance traversal
        presets_map = {}
        for p in [Path("CMakePresets.json"), Path("CMakeUserPresets.json")]:
            if p.exists():
                with p.open("r") as f:
                    try:
                        data = json.load(f)
                        for pr in data.get("configurePresets", []):
                            presets_map[pr["name"]] = pr
                    except json.JSONDecodeError:
                        continue

        def resolve_preset(name):
            if name not in presets_map:
                return
            
            preset = presets_map[name]
            
            # 1. Resolve Parent first (if any)
            parent = preset.get("inherits")
            if parent:
                if isinstance(parent, list):
                    for p_name in reversed(parent): # Last one takes precedence
                        resolve_preset(p_name)
                else:
                    resolve_preset(parent)
            
            # 2. Apply current preset overrides
            cache_vars = preset.get("cacheVariables", {})
            if "CAFFEINE_BUILD_STAGE" in cache_vars:
                self.stage = cache_vars["CAFFEINE_BUILD_STAGE"]
            
            if "binaryDir" in preset:
                raw_bin_dir = preset["binaryDir"]
                raw_bin_dir = raw_bin_dir.replace("${sourceDir}", str(self.host_workspace))
                raw_bin_dir = raw_bin_dir.replace("${presetName}", self.preset_name)
                self.binary_dir = self._normalize_path(raw_bin_dir)
            
            # Accumulate automounts
            vendor_caffeine = preset.get("vendor", {}).get("caffeine", {})
            for m in vendor_caffeine.get("mounts", []):
                host_path = m.get("host_path")
                container_path = m.get("container_path")
                if host_path and container_path:
                    self.automounts.append(f"{host_path}:{container_path}")

        resolve_preset(self.preset_name)
        
        # Fallback for binaryDir if never found in inheritance tree
        if not self.binary_dir:
            self.binary_dir = self.workspace / "build" / self.preset_name
            
        # Merge accumulated automounts
        self.mounts.extend(self.automounts)
        
        repo_owner = os.environ.get("GITHUB_REPOSITORY_OWNER", "while-one")
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
                # It's absolute but not in our workspace (e.g. /tmp)
                # If it's in a known build structure, try to rescue it
                if "build/" in str(p):
                    subpath = str(p).split("build/", 1)[1]
                    return self.workspace / "build" / subpath
                return p
        
        # If it's relative, just join with /work
        return self.workspace / p

    def run_docker(self, bash_cmd: str) -> int:
        """Executes a bash command string inside the Caffeine build container."""
        mount_args = []
        for m in self.mounts:
            if ':' not in m:
                print(f"Error: Invalid mount format '{m}'. Use src:dst.")
                return 1
            src, dst = m.split(':', 1)
            mount_args.extend(["-v", f"{Path(src).resolve()}:{dst}"])

        # Fix root ownership: prioritize HOST_UID/GID from environment
        uid = os.environ.get("HOST_UID", str(os.getuid()))
        gid = os.environ.get("HOST_GID", str(os.getgid()))

        # Use -t for pseudo-TTY to support color output from compiler
        docker_cmd = [
            "docker", "run", "--rm", "-t",
            "--user", f"{uid}:{gid}",
            "-v", f"{self.host_workspace}:/work",
            "-w", "/work",
            "-e", f"CAFFEINE_CI={str(self.ci_mode).lower()}"
        ] + mount_args + [self.image, "bash", "-c", bash_cmd]

        print(f"--------------------------------------------------------------------------------")
        print(f" Image:      {self.image}")
        print(f" Preset:     {self.preset_name}")
        print(f" Target:     {self.target}")
        print(f" Binary Dir: {self.binary_dir}")
        print(f" Clean:      {self.clean}")
        if self.use_local:
            print(f" Mode:       Local Overrides Active")
        print(f"--------------------------------------------------------------------------------")

        try:
            # We use check=False because we want to handle the return code ourselves
            result = subprocess.run(docker_cmd)
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
            target_bin = self.binary_dir or (self.workspace / "build" / self.preset_name)
            relative_bin = target_bin.relative_to(self.workspace)
            # Safety check to prevent rm -rf /work or /
            if str(relative_bin) not in [".", "..", "/"]:
                cmd_chain.append(f"rm -rf {relative_bin}")
            else:
                print(f"Error: Refusing to clean unsafe directory: '{relative_bin}'")
                return 1

        # 2. Construction logic
        # Force color diagnostics for native output
        extra = " ".join(self.extra_args + ["-D CMAKE_COLOR_DIAGNOSTICS=ON"])
        
        # We need to capture the output of the configuration step to find the ACTUAL binary directory
        # because CMake might have hardcoded it in a parent preset.
        configure_cmd = f"cmake --preset {self.preset_name} {extra}"
        
        # In Docker, we'll run the configure command and look for "Build files have been written to: <path>"
        # However, to keep it simple and robust, we'll just let CMake tell us where it build.
        
        if self.target.startswith("ctest"):
            # Enforce explicitly: Configure -> Build -> Test
            # We use a clever trick: we use 'cmake --build .' inside the directory CMake just configured
            cmd_chain.append(configure_cmd)
            # Find the binary dir from the preset name as a fallback, 
            # but usually CMake will just work if we use the same preset for build.
            cmd_chain.append(f"cmake --build --preset {self.preset_name}")
            # For ctest, we need the directory. We'll assume the one we parsed or fallback.
            cmd_chain.append(f"ctest --preset {self.preset_name} {self.target.replace('ctest', '', 1)}")
        else:
            # Standard Build
            cmd_chain.append(configure_cmd)
            cmd_chain.append(f"cmake --build --preset {self.preset_name} --target {self.target}")

        full_cmd = " && ".join(cmd_chain)
        return self.run_docker(full_cmd)

def main():
    parser = argparse.ArgumentParser(description="Caffeine Build Engine")
    parser.add_argument("--preset", default="linux-native", help="CMake preset")
    parser.add_argument("--target", default="all", help="CMake target")
    parser.add_argument("--clean", action="store_true", help="Clean build directory first")
    parser.add_argument("--use-local", action="store_true", help="Automatically use -local preset and mounts from CMakeUserPresets.json")
    parser.add_argument("--mount", action="append", help="Docker volume mounts (src:dst)")
    parser.add_argument("extra_args", nargs=argparse.REMAINDER, help="Additional CMake args")
    
    args = parser.parse_args()
    builder = CaffeineBuilder(args)
    
    exit_code = builder.build()
    
    # Summary
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    NC = '\033[0m'
    
    print("--------------------------------------------------------------------------------")
    if exit_code == 0:
        print(f"{GREEN}All builds passed{NC}")
    else:
        print(f"{RED}Target failed: {args.target} ({args.preset}){NC}")
    print("--------------------------------------------------------------------------------")
    
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
