"""Terminal rendering helpers."""

from __future__ import annotations

import os

from .pet import Pet, STAT_NAMES
from .species import sprite_for


# ANSI colors. Suppressed when NO_COLOR is set or stdout isn't a TTY.
_COLORS = {
    "reset": "\033[0m",
    "bold": "\033[1m",
    "dim": "\033[2m",
    "white": "\033[97m",
    "green": "\033[92m",
    "magenta": "\033[95m",
    "yellow": "\033[93m",
    "cyan": "\033[96m",
    "red": "\033[91m",
    "blue": "\033[94m",
}

RARITY_COLORS = {
    "Common": "white",
    "Uncommon": "green",
    "Rare": "blue",
    "Epic": "magenta",
    "Legendary": "yellow",
}


def _use_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    return True


def color(text: str, name: str) -> str:
    if not _use_color():
        return text
    code = _COLORS.get(name, "")
    return f"{code}{text}{_COLORS['reset']}"


def bar(value: float, width: int = 20, good_high: bool = True) -> str:
    filled = int(round((value / 100.0) * width))
    filled = max(0, min(width, filled))
    pct = value
    if good_high:
        c = "green" if pct >= 60 else "yellow" if pct >= 30 else "red"
    else:
        c = "green" if pct <= 40 else "yellow" if pct <= 70 else "red"
    bar_str = "#" * filled + "-" * (width - filled)
    return color(f"[{bar_str}] {int(pct):>3}", c)


def _decorate_sprite(pet: Pet) -> list[str]:
    lines = sprite_for(pet.species)
    if pet.shiny:
        lines = [l + "  *" for l in lines]
    if pet.hat:
        lines = [f"  ({pet.hat})"] + lines
    rarity_color = RARITY_COLORS.get(pet.rarity, "white")
    return [color(l, rarity_color) for l in lines]


def status_line(pet: Pet) -> str:
    pet.tick()
    rarity = color(pet.rarity, RARITY_COLORS.get(pet.rarity, "white"))
    shiny = color(" Shiny", "cyan") if pet.shiny else ""
    return (
        f"{color(pet.name, 'bold')} the {rarity}{shiny} {pet.species} "
        f"— feeling {pet.mood()}"
    )


def render_card(pet: Pet) -> str:
    pet.tick()
    sprite = _decorate_sprite(pet)
    sprite_width = max((len(_strip_ansi(l)) for l in sprite), default=0)

    header = status_line(pet)
    info_lines = [
        "",
        f"Hunger     {bar(pet.hunger, good_high=False)}",
        f"Happiness  {bar(pet.happiness)}",
        f"Energy     {bar(pet.energy)}",
        "",
        color("Stats", "bold"),
    ]
    for s in STAT_NAMES:
        info_lines.append(f"  {s:<10} {pet.stats[s]:>3}")

    # Pad sprite to same height as info block.
    height = max(len(sprite), len(info_lines))
    sprite = sprite + [""] * (height - len(sprite))
    info_lines = info_lines + [""] * (height - len(info_lines))

    body = []
    pad = sprite_width + 4
    for sline, iline in zip(sprite, info_lines):
        visible = len(_strip_ansi(sline))
        spacer = " " * max(0, pad - visible)
        body.append(f"  {sline}{spacer}{iline}")

    return "\n".join([header, ""] + body)


def _strip_ansi(s: str) -> str:
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\033":
            while i < len(s) and s[i] != "m":
                i += 1
            i += 1
            continue
        out.append(s[i])
        i += 1
    return "".join(out)
