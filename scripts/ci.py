#!/usr/bin/env python3
"""
Caffeine Framework Unified CI Orchestrator
Manages the CI lifecycle (format, analyze, build, test, doc).
"""
import argparse
import json
import subprocess
import sys
import re
import os
from pathlib import Path

class CaffeineCI:
    def __init__(self, args):
        self.command = args.command
        self.specific_preset = args.preset
        self.use_local = args.use_local
        self.mounts = args.mount or []
        
        self.project_root = Path.cwd()
        self.build_script = self.project_root / "caffeine-build" / "scripts" / "build.py"
        
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
        match = re.search(r'project\s*\(\s*([a-zA-Z0-9_-]+)', content, re.MULTILINE)
        if match:
            return match.group(1)
        return "unknown"

    def _load_presets(self) -> dict:
        """Parses CMakePresets.json and optionally CMakeUserPresets.json."""
        presets_data = []
        for p in [Path("CMakePresets.json"), Path("CMakeUserPresets.json")]:
            if p.exists():
                with p.open("r") as f:
                    try:
                        presets_data.append(json.load(f))
                    except json.JSONDecodeError:
                        continue
        
        categories = {"universe": [], "hardware": [], "tests": []}
        all_names = []
        
        for data in presets_data:
            for preset in data.get("configurePresets", []):
                if preset.get("hidden", False):
                    continue
                    
                name = preset["name"]
                
                # If --use-local is passed, we ONLY process -local presets
                # If NOT passed, we SKIP -local presets
                if self.use_local:
                    if not name.endswith("-local"):
                        continue
                else:
                    if name.endswith("-local"):
                        continue

                all_names.append(name)
                cache = preset.get("cacheVariables", {})
                
                # Determine if it has tests
                has_tests = cache.get("CFN_BUILD_TESTS", "") == "ON"
                if not has_tests:
                    test_presets = data.get("testPresets", [])
                    has_tests = any(tp.get("name") == name for tp in test_presets)

                preset_data = {"name": name, "tests": has_tests}
                
                if cache.get("CAFFEINE_UNIVERSE_TARGET", "") == "ON":
                    categories["universe"].append(preset_data)
                elif has_tests:
                    categories["tests"].append(preset_data)
                else:
                    categories["hardware"].append(preset_data)
                
        categories["all_names"] = list(set(all_names)) # Ensure uniqueness
        return categories

    def run_stage(self, preset: str, stage: str) -> int:
        """Executes a specific CI stage for a preset."""
        # Find preset metadata to check if it's a universe target
        is_universe = any(p["name"] == preset for p in self.categories["universe"])
        
        # Pedantic Enforcement: format, analyze, and doc are GLOBAL stages.
        # They should only be used with a universe target.
        global_stages = ["format", "analyze", "doc"]
        if stage in global_stages and not is_universe:
            # If we have universe presets, we refuse to run global stages on non-universe targets.
            if self.categories["universe"]:
                print(f">>> [Skip] Stage '{stage}' is global and should only run on a universe preset.")
                return 0
            # Fallback: if no universe preset exists at all, we allow it (best effort)
            pass

        target_map = {
            "format": f"{self.project_name}-universe-check-format",
            "analyze": f"{self.project_name}-analyze",
            "build": "all",
            "test": "ctest --output-on-failure",
            "doc": f"{self.project_name}-docs"
        }
            
        target = target_map.get(stage)
        if not target:
            print(f"Error: Unknown CI stage '{stage}'")
            return 1
            
        cmd = ["python3", str(self.build_script), "--preset", preset, "--target", target]
        
        if self.use_local:
            cmd.append("--use-local")

        # Clean for format stage to ensure fresh check
        if stage == "format":
            cmd.append("--clean")
            
        for m in self.mounts:
            cmd.extend(["--mount", m])
            
        print(f">>> [{stage.upper()}] Validating Preset: {preset} (Target: {target})")
        
        try:
            # We call build.py directly
            result = subprocess.run(cmd)
            return result.returncode
        except Exception as e:
            print(f"Error executing stage {stage}: {e}")
            return 1

    def list_matrix(self):
        """Outputs the GHA matrix JSON."""
        # Combine hardware and tests for the 'hardware' matrix leg
        matrix = {
            "universe": self.categories["universe"],
            "hardware": self.categories["hardware"] + self.categories["tests"]
        }
        # Fallback: if no universe preset exists, use the first hardware/test preset for global tasks
        if not matrix["universe"] and matrix["hardware"]:
            # Create a synthetic universe entry from the first hardware preset
            # but we don't mark it as universe so run_stage allows fallback
            matrix["universe"].append(matrix["hardware"][0])
            
        print(json.dumps(matrix))

    def run_all(self) -> int:
        """Sequential execution of all stages for all presets."""
        print("--------------------------------------------------------------------------------")
        print(f" Starting Unified CI (Sequential) for project: {self.project_name}")
        print("--------------------------------------------------------------------------------")
        
        exit_code = 0
        
        # 1. Global Stages (Universe)
        # We run these once on the designated universe preset
        universe_presets = self.categories["universe"]
        # If no universe exists, we use the first available preset as fallback
        global_target_preset = ""
        if universe_presets:
            global_target_preset = universe_presets[0]["name"]
        elif self.categories["hardware"]:
            global_target_preset = self.categories["hardware"][0]["name"]
        elif self.categories["tests"]:
            global_target_preset = self.categories["tests"][0]["name"]

        if global_target_preset:
            exit_code |= self.run_stage(global_target_preset, "format")
            exit_code |= self.run_stage(global_target_preset, "analyze")
            exit_code |= self.run_stage(global_target_preset, "doc")
        
        # 2. Matrix Stages (Build, Test)
        # Analyze is now global, so we only run build and test here.
        for p_data in self.categories["hardware"] + self.categories["tests"]:
            p = p_data["name"]
            exit_code |= self.run_stage(p, "build")
            
            if p_data["tests"]:
                exit_code |= self.run_stage(p, "test")
                
        return exit_code

    def execute(self) -> int:
        if self.command == "list":
            self.list_matrix()
            return 0
            
        if self.command == "all":
            if self.specific_preset:
                # Run all stages for one specific preset
                exit_code = 0
                exit_code |= self.run_stage(self.specific_preset, "format")
                exit_code |= self.run_stage(self.specific_preset, "analyze")
                exit_code |= self.run_stage(self.specific_preset, "build")
                exit_code |= self.run_stage(self.specific_preset, "test")
                exit_code |= self.run_stage(self.specific_preset, "doc")
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

def main():
    parser = argparse.ArgumentParser(description="Caffeine CI Orchestrator")
    parser.add_argument("command", choices=["all", "list", "format", "analyze", "build", "test", "doc"], 
                        help="CI command to execute")
    parser.add_argument("preset", nargs="?", help="Specific preset to run for")
    parser.add_argument("--use-local", action="store_true", help="Filter for -local presets and pass --use-local to build.py")
    parser.add_argument("--mount", action="append", help="Docker volume mounts (src:dst)")
    
    args = parser.parse_args()
    ci = CaffeineCI(args)
    
    exit_code = ci.execute()
    
    # Summary
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    NC = '\033[0m'
    
    if args.command != "list":
        print("--------------------------------------------------------------------------------")
        if exit_code == 0:
            print(f"{GREEN}CI Validation passed{NC}")
        else:
            print(f"{RED}CI Validation failed{NC}")
        print("--------------------------------------------------------------------------------")
    
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
