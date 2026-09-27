#!/usr/bin/env python3
"""Validate the Minecraft assets consumed by the Godot resource renderer.

This is intentionally independent of Godot. It verifies that representative
client blockstates resolve through their model-parent and texture-variable
chains to PNGs in both the authoritative extracted payload and the staged
Godot copy. It catches broken staging and resource-path regressions before an
APK export starts.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "extracted" / "assets" / "minecraft"
STAGED = ROOT / "godot_extension" / "minecraft_assets" / "minecraft"
REPRESENTATIVE_BLOCKS = (
    "grass_block",
    "stone",
    "oak_log",
    "oak_leaves",
    "glass",
    "torch",
)


def read_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return data


def minecraft_id(identifier: str) -> str:
    return identifier.removeprefix("minecraft:")


def select_model(asset_root: Path, block_name: str) -> dict[str, Any]:
    state = read_json(asset_root / "blockstates" / f"{block_name}.json")
    variants = state.get("variants")
    if isinstance(variants, dict) and variants:
        selected = variants.get("")
        if selected is None:
            selected = variants[sorted(variants)[0]]
    else:
        multipart = state.get("multipart")
        if not isinstance(multipart, list) or not multipart:
            raise ValueError(f"No variants or multipart data: {block_name}")
        selected = multipart[0].get("apply")
    if isinstance(selected, list):
        selected = selected[0]
    if not isinstance(selected, dict) or not isinstance(selected.get("model"), str):
        raise ValueError(f"No model selected for {block_name}")
    return selected


def resolve_model(asset_root: Path, model_name: str, seen: set[str] | None = None) -> dict[str, Any]:
    seen = set() if seen is None else seen
    model_name = minecraft_id(model_name)
    if model_name in seen:
        raise ValueError(f"Cyclic model parent: {model_name}")
    seen.add(model_name)
    model = read_json(asset_root / "models" / f"{model_name}.json")
    parent: dict[str, Any] = {}
    if isinstance(model.get("parent"), str):
        parent = resolve_model(asset_root, model["parent"], seen)
    textures = dict(parent.get("textures", {}))
    textures.update(model.get("textures", {}))
    elements = model.get("elements", parent.get("elements", []))
    return {"textures": textures, "elements": elements}


def resolve_texture(reference: str, textures: dict[str, Any]) -> str:
    visited: set[str] = set()
    while reference.startswith("#"):
        key = reference[1:]
        if key in visited or key not in textures:
            raise ValueError(f"Unresolvable texture variable: {reference}")
        visited.add(key)
        value = textures[key]
        if isinstance(value, dict):
            value = value.get("sprite")
        if not isinstance(value, str):
            raise ValueError(f"Unresolvable texture variable: {reference}")
        reference = value
    return minecraft_id(reference)


def verify_renderer_inputs(asset_root: Path) -> int:
    texture_count = 0
    for block_name in REPRESENTATIVE_BLOCKS:
        selection = select_model(asset_root, block_name)
        model = resolve_model(asset_root, selection["model"])
        elements = model["elements"]
        if not isinstance(elements, list) or not elements:
            raise ValueError(f"No renderable model elements for {block_name}")
        for element in elements:
            if not isinstance(element, dict):
                continue
            faces = element.get("faces", {})
            if not isinstance(faces, dict):
                continue
            for face in faces.values():
                if not isinstance(face, dict) or not isinstance(face.get("texture"), str):
                    continue
                texture = resolve_texture(face["texture"], model["textures"])
                texture_path = asset_root / "textures" / f"{texture}.png"
                if not texture_path.is_file():
                    raise FileNotFoundError(f"Missing block texture: {texture_path}")
                texture_count += 1
    return texture_count


def main() -> int:
    if not SOURCE.is_dir():
        raise FileNotFoundError(f"Client assets are missing: {SOURCE}")
    if not STAGED.is_dir():
        raise FileNotFoundError("Staged Godot assets are missing; run tools/stage_minecraft_assets.py")

    source_files = sum(path.is_file() for path in SOURCE.rglob("*"))
    staged_files = sum(path.is_file() for path in STAGED.rglob("*"))
    if source_files != staged_files:
        raise RuntimeError(f"Staging mismatch: source={source_files}, staged={staged_files}")

    source_textures = verify_renderer_inputs(SOURCE)
    staged_textures = verify_renderer_inputs(STAGED)
    if source_textures != staged_textures:
        raise RuntimeError("Staged renderer inputs differ from the client payload")

    print(
        f"Resource-pack renderer inputs verified: {source_files:,} files; "
        f"{source_textures} representative textured faces resolved"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError, RuntimeError) as error:
        print(f"resource-pack validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
