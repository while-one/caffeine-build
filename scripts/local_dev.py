#!/usr/bin/env python3
"""
Caffeine Framework Local Development Helper
Generates CMakeUserPresets.json to facilitate local dependency overrides.
"""

import argparse
import json
import sys
from pathlib import Path

if sys.version_info < (3, 7):
    sys.exit("Error: Python 3.7+ required")


from typing import Any, Dict, cast


def load_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    with open(path, "r") as f:
        try:
            return cast(Dict[str, Any], json.load(f))
        except json.JSONDecodeError:
            print(f"Error: Failed to parse {path}")
            return {}


def save_json(path: Path, data: Dict[str, Any]) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=4)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate CMakeUserPresets for local overrides"
    )
    parser.add_argument("--preset", required=True, help="Base configure preset name")
    parser.add_argument(
        "--dep",
        action="append",
        required=True,
        help="Dependency name (e.g., caffeine_hal)",
    )
    parser.add_argument(
        "--path", action="append", required=True, help="Local path to the dependency"
    )

    args = parser.parse_args()

    if len(args.dep) != len(args.path):
        print(
            "Error: The number of --dep arguments must match the number of --path arguments."
        )
        sys.exit(1)

    presets_path = Path("CMakePresets.json")
    user_presets_path = Path("CMakeUserPresets.json")

    if not presets_path.exists():
        print("Error: CMakePresets.json not found in current directory.")
        sys.exit(1)

    presets = load_json(presets_path)
    user_presets = load_json(user_presets_path)

    # 1. Verify base preset exists
    base_exists = any(
        p.get("name") == args.preset for p in presets.get("configurePresets", [])
    )
    if not base_exists:
        print(f"Error: Base preset '{args.preset}' not found in CMakePresets.json")
        sys.exit(1)

    # 2. Prepare user presets structure
    if not user_presets:
        user_presets = {
            "version": presets.get("version", 4),
            "configurePresets": [],
            "buildPresets": [],
            "testPresets": [],
        }

    user_presets.setdefault("configurePresets", [])
    user_presets.setdefault("buildPresets", [])
    user_presets.setdefault("testPresets", [])

    local_preset_name = f"{args.preset}-local"

    # 3. Create or update the CONFIGURE preset
    target_preset = None
    for p in user_presets["configurePresets"]:
        if p.get("name") == local_preset_name:
            target_preset = p
            break

    if not target_preset:
        target_preset = {
            "name": local_preset_name,
            "inherits": args.preset,
            "cacheVariables": {},
            "vendor": {"caffeine": {"mounts": []}},
        }
        user_presets["configurePresets"].append(target_preset)

    # 4. Create or update the BUILD preset
    build_preset = None
    for p in user_presets["buildPresets"]:
        if p.get("name") == local_preset_name:
            build_preset = p
            break
    if not build_preset:
        user_presets["buildPresets"].append(
            {"name": local_preset_name, "configurePreset": local_preset_name}
        )

    # 5. Create or update the TEST preset
    test_preset = None
    for p in user_presets["testPresets"]:
        if p.get("name") == local_preset_name:
            test_preset = p
            break
    if not test_preset:
        user_presets["testPresets"].append(
            {
                "name": local_preset_name,
                "configurePreset": local_preset_name,
                "output": {"outputOnFailure": True},
            }
        )

    # Ensure caffeine vendor structure in configure preset
    target_preset.setdefault("vendor", {}).setdefault("caffeine", {}).setdefault(
        "mounts", []
    )

    for dep_name, dep_path_str in zip(args.dep, args.path):
        dep_path = Path(dep_path_str)
        if not dep_path.is_dir():
            print(
                f"Error: Dependency path does not exist or is not a directory: {dep_path}"
            )
            sys.exit(1)

        dep_upper = dep_name.upper().replace("-", "_")
        dep_lower = dep_name.lower().replace("_", "-")
        container_path = f"/work/.local/{dep_lower}"

        # 6. Inject FetchContent override
        if "cacheVariables" not in target_preset:
            target_preset["cacheVariables"] = {}
        target_preset["cacheVariables"][
            f"FETCHCONTENT_SOURCE_DIR_{dep_upper}"
        ] = container_path

        # 7. Inject mount metadata
        abs_host_path = str(dep_path.resolve())
        mount_entry = {"host_path": abs_host_path, "container_path": container_path}

        # Check if mount already exists for this container path
        found = False
        for m in target_preset["vendor"]["caffeine"]["mounts"]:
            if m["container_path"] == container_path:
                m["host_path"] = abs_host_path
                found = True
                break
        if not found:
            target_preset["vendor"]["caffeine"]["mounts"].append(mount_entry)

        print(f"Mapped {dep_name} -> {abs_host_path}")

    save_json(user_presets_path, user_presets)
    print(f"Successfully generated/updated user preset: {local_preset_name}")


if __name__ == "__main__":
    main()
