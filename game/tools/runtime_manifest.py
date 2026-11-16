"""Explicit deterministic runtime inputs shared by stamping and packaging."""
from pathlib import Path
import fnmatch
import re

MATURE_SUFFIXES = {'.gd', '.scn', '.tscn', '.tres', '.res', '.png', '.jpg', '.jpeg', '.webp', '.svg', '.import', '.uid', '.gdshader', '.shader'}
ART_SUFFIXES = {'.txt', '.import', '.gd', '.uid', '.gdshader', '.blend', '.glb', '.gltf', '.bin', '.png', '.jpg', '.jpeg', '.webp', '.json', '.md', '.py'}

def regular(root: Path, p: Path) -> bool:
    if p.is_symlink():
        raise ValueError(f'Symlink forbidden in manifest: {p}')
    return p.is_file() and p.resolve().is_relative_to(root.resolve())

def runtime_paths(root: Path) -> list[Path]:
    paths = [root / n for n in ('project.godot', 'main.tscn', 'main_menu.tscn', 'export_presets.cfg')]
    for folder, suffixes in [('scripts', {'.gd', '.uid'}), ('assets/audio', {'.wav', '.import'}), ('assets/models', {'.glb', '.import'}), ('assets/advanced_buildings', {'.gltf', '.bin', '.import'}), ('assets/fonts', {'.otf', '.ttf', '.import'}), ('assets/mature', MATURE_SUFFIXES)]:
        base = root / folder
        if base.exists():
            for p in base.rglob('*'):
                if p.is_symlink():
                    raise ValueError(f'Symlink forbidden in runtime: {p}')
                if folder == 'assets/mature' and any(p.name.lower().endswith(ext + '.import') for ext in ('.glb', '.gltf', '.blend')):
                    continue
                if p.is_file() and p.suffix.lower() in suffixes:
                    paths.append(p)
    for p in paths:
        if not regular(root, p):
            raise ValueError(f'Missing runtime input: {p}')
    return sorted(set(paths), key=lambda p: p.relative_to(root).as_posix())

def verify_mature_export_exclusions(root: Path) -> None:
    """Interchange copies must not silently enter all_resources exports."""
    preset = (root / 'export_presets.cfg').read_text()
    match = re.search(r'^exclude_filter="([^"]*)"', preset, re.M)
    filters = match.group(1).split(',') if match else []
    for p in (root / 'assets/mature').rglob('*'):
        if p.is_file() and (p.suffix.lower() in {'.glb', '.gltf', '.blend', '.bin'} or any(p.name.lower().endswith(ext + '.import') for ext in ('.glb', '.gltf', '.blend'))):
            name = p.relative_to(root).as_posix()
            if not any(fnmatch.fnmatchcase(name, pat.strip()) for pat in filters):
                raise ValueError(f'Interchange input must be moved under art/ or explicitly excluded from export: {name}')
