"""Pet generation and care mechanics."""

from __future__ import annotations

import time
from dataclasses import dataclass, asdict, field
from typing import Any

from .rng import rng_for_seed
from .species import SPECIES, EYE_STYLES, HATS, sprite_for


RARITIES = [
    ("Common",           0.6000, "white"),
    ("Rare",             0.2500, "green"),
    ("Epic",             0.1000, "magenta"),
    ("Legendary",        0.0399, "yellow"),
    ("Shiny Legendary",  0.0001, "cyan"),
]

STAT_NAMES = ["DEBUGGING", "PATIENCE", "CHAOS", "WISDOM", "SNARK"]

# Care meters decay this many points per real-world hour.
DECAY_PER_HOUR = {
    "hunger": 8.0,      # rises with time (0 = full, 100 = starving)
    "happiness": 6.0,   # falls with time
    "energy": 4.0,      # falls with time
}


def _roll_rarity(r) -> str:
    roll = r.next_float()
    cumulative = 0.0
    for name, prob, _ in RARITIES:
        cumulative += prob
        if roll < cumulative:
            return name
    return RARITIES[0][0]


@dataclass
class Pet:
    seed: str
    name: str
    species: str
    rarity: str
    shiny: bool
    eye_style: str
    hat: str | None
    stats: dict[str, int]
    hunger: float = 20.0
    happiness: float = 80.0
    energy: float = 80.0
    born_at: float = field(default_factory=time.time)
    last_tick: float = field(default_factory=time.time)

    @classmethod
    def hatch(cls, seed: str, name: str | None = None) -> "Pet":
        r = rng_for_seed(seed)
        species = r.choice(SPECIES)
        rarity = _roll_rarity(r)
        shiny = r.next_float() < 0.01
        eye_style = r.choice(EYE_STYLES)
        hat = r.choice(HATS)
        stats = {s: r.randint(1, 99) for s in STAT_NAMES}
        chosen_name = name if name else _generate_name(seed, species)
        return cls(
            seed=seed,
            name=chosen_name,
            species=species,
            rarity=rarity,
            shiny=shiny,
            eye_style=eye_style,
            hat=hat,
            stats=stats,
        )

    def tick(self, now: float | None = None) -> None:
        now = now or time.time()
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
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Pet":
        return cls(**data)


def _clamp(v: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, v))


# A small bank of name parts. Selection is deterministic via seed.
_PREFIX = [
    "Bit", "Byte", "Pix", "Lumo", "Echo", "Zap", "Mochi", "Tuna",
    "Pog", "Nibble", "Quack", "Boba", "Zen", "Kiwi", "Sushi", "Pico",
    "Doodle", "Wobble", "Squish", "Twix",
]
_SUFFIX = [
    "kin", "let", "bert", "boo", "pop", "ster", "ling", "puff",
    "nut", "boop", "wick", "doo", "zoom", "tot", "san", "bee",
]


def _generate_name(seed: str, species: str) -> str:
    r = rng_for_seed(seed + ":name:" + species)
    return r.choice(_PREFIX) + r.choice(_SUFFIX)
