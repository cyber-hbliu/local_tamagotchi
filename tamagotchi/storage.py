"""Load and save pet state to a local JSON file."""

import json
import os
from pathlib import Path

from .pet import Pet


def default_save_path() -> Path:
    override = os.environ.get("TAMAGOTCHI_SAVE")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".local_tamagotchi.json"


def load(path: Path | None = None) -> Pet | None:
    path = path or default_save_path()
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    return Pet.from_dict(data)


def save(pet: Pet, path: Path | None = None) -> Path:
    path = path or default_save_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(pet.to_dict(), f, indent=2)
    return path


def delete(path: Path | None = None) -> bool:
    path = path or default_save_path()
    if path.exists():
        path.unlink()
        return True
    return False
