"""Pet generation and care mechanics.

Pet data is split into two layers:

- "Bones": species, rarity, shiny, eye style, hat, stats. Pure function
  of the seed — recomputed every load, never trusted from disk.
- "Soul" + state: name, birth time, hunger / happiness / energy / last_tick.
  Persisted to disk.

The merge order on load is { **stored_soul, **bones }, so a tampered save
file can never give you a Legendary you didn't earn.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any

from .rng import rng_for_seed
from .species import SPECIES, EYE_STYLES, HATS_BY_RARITY


# (name, probability, stat_floor)
RARITIES = [
    ("Common",    0.60,  5),
    ("Uncommon",  0.25, 15),
    ("Rare",      0.10, 25),
    ("Epic",      0.04, 35),
    ("Legendary", 0.01, 50),
]

STAT_NAMES = ["DEBUGGING", "PATIENCE", "CHAOS", "WISDOM", "SNARK"]

# Care meters decay this many points per real-world hour.
DECAY_PER_HOUR = {
    "hunger": 8.0,
    "happiness": 6.0,
    "energy": 4.0,
}

# Fields that get serialized to disk. Everything else is recomputed from the seed.
_SOUL_FIELDS = ("seed", "name", "born_at", "hunger", "happiness", "energy", "last_tick")


def _roll_rarity(r) -> tuple[str, int]:
    roll = r.next_float()
    cumulative = 0.0
    for name, prob, floor in RARITIES:
        cumulative += prob
        if roll < cumulative:
            return name, floor
    return RARITIES[0][0], RARITIES[0][2]


def _roll_stats(r, floor: int) -> dict[str, int]:
    """Pick one peak stat, one dump stat, three scattered."""
    n = len(STAT_NAMES)
    peak_idx = r.randint(0, n - 1)
    dump_idx = r.randint(0, n - 1)
    while dump_idx == peak_idx:
        dump_idx = r.randint(0, n - 1)

    stats: dict[str, int] = {}
    for i, name in enumerate(STAT_NAMES):
        if i == peak_idx:
            stats[name] = min(100, floor + 50 + r.randint(0, 49))
        elif i == dump_idx:
            stats[name] = floor + r.randint(0, 4)
        else:
            stats[name] = min(100, floor + r.randint(0, 49))
    return stats


def compute_bones(seed: str) -> dict[str, Any]:
    """Deterministically derive species/rarity/shiny/eyes/hat/stats from seed."""
    r = rng_for_seed(seed)
    species = r.choice(SPECIES)
    rarity, floor = _roll_rarity(r)
    shiny = r.next_float() < 0.01
    eye_style = r.choice(EYE_STYLES)
    stats = _roll_stats(r, floor)
    hat_pool = HATS_BY_RARITY[rarity]
    hat = r.choice(hat_pool)
    return {
        "species": species,
        "rarity": rarity,
        "shiny": shiny,
        "eye_style": eye_style,
        "hat": hat,
        "stats": stats,
    }


@dataclass
class Pet:
    # Soul + state (persisted)
    seed: str
    name: str
    born_at: float = field(default_factory=time.time)
    hunger: float = 20.0
    happiness: float = 80.0
    energy: float = 80.0
    last_tick: float = field(default_factory=time.time)
    # Bones (recomputed from seed; never trusted from disk)
    species: str = ""
    rarity: str = ""
    shiny: bool = False
    eye_style: str = ""
    hat: str | None = None
    stats: dict[str, int] = field(default_factory=dict)

    def __post_init__(self) -> None:
        # Always overwrite bones from the seed.
        for k, v in compute_bones(self.seed).items():
            setattr(self, k, v)

    @classmethod
    def hatch(cls, seed: str, name: str | None = None) -> "Pet":
        chosen_name = name if name else _generate_name(seed)
        return cls(seed=seed, name=chosen_name)

    def tick(self, now: float | None = None) -> None:
        now = now if now is not None else time.time()
        elapsed_hours = max(0.0, (now - self.last_tick) / 3600.0)
        self.hunger = _clamp(self.hunger + DECAY_PER_HOUR["hunger"] * elapsed_hours)
        self.happiness = _clamp(self.happiness - DECAY_PER_HOUR["happiness"] * elapsed_hours)
        self.energy = _clamp(self.energy - DECAY_PER_HOUR["energy"] * elapsed_hours)
        self.last_tick = now

    def feed(self) -> str:
        self.tick()
        if self.hunger < 5:
            return f"{self.name} is too full to eat anything more."
        self.hunger = _clamp(self.hunger - 35)
        self.happiness = _clamp(self.happiness + 5)
        return f"You fed {self.name}. They munch happily."

    def play(self) -> str:
        self.tick()
        if self.energy < 15:
            return f"{self.name} is too tired to play right now."
        self.happiness = _clamp(self.happiness + 25)
        self.energy = _clamp(self.energy - 15)
        self.hunger = _clamp(self.hunger + 8)
        return f"You played with {self.name}. They had a blast!"

    def pet(self) -> str:
        self.tick()
        self.happiness = _clamp(self.happiness + 10)
        return f"You pet {self.name}. <3 <3 <3"

    def sleep(self) -> str:
        self.tick()
        if self.energy > 90:
            return f"{self.name} isn't sleepy at all."
        self.energy = _clamp(self.energy + 50)
        return f"{self.name} curls up for a nap. Zzz..."

    def mood(self) -> str:
        score = (100 - self.hunger) + self.happiness + self.energy
        if score >= 230:
            return "ecstatic"
        if score >= 180:
            return "happy"
        if score >= 130:
            return "okay"
        if score >= 80:
            return "grumpy"
        return "miserable"

    def to_dict(self) -> dict[str, Any]:
        return {k: getattr(self, k) for k in _SOUL_FIELDS}

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Pet":
        soul = {k: data[k] for k in _SOUL_FIELDS if k in data}
        return cls(**soul)


def _clamp(v: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, v))


_PREFIX = [
    "Bit", "Byte", "Pix", "Lumo", "Echo", "Zap", "Mochi", "Tuna",
    "Pog", "Nibble", "Quack", "Boba", "Zen", "Kiwi", "Sushi", "Pico",
    "Doodle", "Wobble", "Squish", "Twix",
]
_SUFFIX = [
    "kin", "let", "bert", "boo", "pop", "ster", "ling", "puff",
    "nut", "boop", "wick", "doo", "zoom", "tot", "san", "bee",
]


def _generate_name(seed: str) -> str:
    r = rng_for_seed(seed + ":name")
    return r.choice(_PREFIX) + r.choice(_SUFFIX)
