"""Deterministic PRNG and identity-based pet generation.

The 'bones' of a pet (species, rarity, stats) are derived deterministically
from a seed string. Same seed -> same pet, always.
"""

SALT = "friend-2026-401"

_FNV_OFFSET = 0x811C9DC5
_FNV_PRIME = 0x01000193


def fnv1a(s: str) -> int:
    h = _FNV_OFFSET
    for byte in s.encode("utf-8"):
        h ^= byte
        h = (h * _FNV_PRIME) & 0xFFFFFFFF
    return h


def _hash_seed(seed: str) -> int:
    return fnv1a(f"{SALT}:{seed}")


class Mulberry32:
    """Tiny deterministic 32-bit PRNG (Mulberry32)."""

    def __init__(self, state: int) -> None:
        self.state = state & 0xFFFFFFFF

    def next_u32(self) -> int:
        self.state = (self.state + 0x6D2B79F5) & 0xFFFFFFFF
        t = self.state
        t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
        t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF
        return (t ^ (t >> 14)) & 0xFFFFFFFF

    def next_float(self) -> float:
        return self.next_u32() / 0x100000000

    def randint(self, low: int, high: int) -> int:
        """Inclusive on both ends."""
        span = high - low + 1
        return low + (self.next_u32() % span)

    def choice(self, items):
        return items[self.next_u32() % len(items)]


def rng_for_seed(seed: str) -> Mulberry32:
    return Mulberry32(_hash_seed(seed))
