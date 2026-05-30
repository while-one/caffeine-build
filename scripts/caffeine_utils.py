import json
from pathlib import Path
from typing import Optional, Set, Dict, Any, cast


def load_all_presets() -> Dict[str, Any]:
    """Loads all presets from CMakePresets.json and CMakeUserPresets.json into a flat map."""
    presets_map = {}
    for p in [Path("CMakePresets.json"), Path("CMakeUserPresets.json")]:
        if p.exists():
            with p.open("r") as f:
                try:
                    data = json.load(f)
                    for pr in data.get("configurePresets", []):
                        presets_map[pr["name"]] = pr
                except json.JSONDecodeError as e:
                    import sys

                    print(f"FATAL ERROR: Failed to parse JSON in {p}: {e}")
                    sys.exit(1)
    return presets_map


def resolve_preset_inheritance(
    preset_name: str, presets_map: Dict[str, Any]
) -> Dict[str, Any]:
    """Recursively resolves a preset's inheritance, returning a merged preset dict."""
    merged: Dict[str, Any] = {}

    def resolve(name: str, visited: Optional[Set[str]] = None) -> None:
        if visited is None:
            visited = set()
        if name in visited:
            return
        visited.add(name)

        if name not in presets_map:
            return

        preset = presets_map[name]

        # 1. Resolve Parent first (if any)
        parent = preset.get("inherits")
        if parent:
            if isinstance(parent, list):
                for p_name in reversed(parent):  # Last one takes precedence
                    resolve(p_name, visited)
            else:
                resolve(parent, visited)

        # 2. Apply current preset overrides (merge cacheVariables, vendor, etc.)
        for key, value in preset.items():
            if key == "cacheVariables":
                cast(
                    Dict[str, Any],
                    merged.setdefault("cacheVariables", cast(Dict[str, Any], {})),
                ).update(value)
            elif key == "vendor":
                # For vendor we might just need to do a shallow merge or specific caffeine merge
                if "vendor" not in merged:
                    merged["vendor"] = cast(Dict[str, Any], {})
                for vendor_name, vendor_data in value.items():
                    if vendor_name == "caffeine" and isinstance(vendor_data, dict):
                        # Merge mounts
                        vendor_dict = cast(
                            Dict[str, Any],
                            merged.setdefault("vendor", cast(Dict[str, Any], {})),
                        )
                        caffeine_dict = cast(
                            Dict[str, Any],
                            vendor_dict.setdefault(
                                "caffeine", cast(Dict[str, Any], {})
                            ),
                        )
                        caffeine_dict.setdefault("mounts", [])
                        caffeine_dict["mounts"].extend(vendor_data.get("mounts", []))
                    else:
                        merged["vendor"][vendor_name] = vendor_data
            else:
                merged[key] = value

    resolve(preset_name)
    return merged
