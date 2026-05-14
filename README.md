# Local Tamagotchi

A terminal virtual pet, inspired by Claude Code's `/buddy`. 18 species,
5 rarity tiers, deterministic generation, and classic Tamagotchi care
mechanics — all running locally, no network required.

## Requirements

- Python 3.10+

## Quick start

```sh
# Hatch a pet (random seed)
python -m tamagotchi hatch

# Or hatch with a specific seed for deterministic results
python -m tamagotchi hatch --seed your-name-here

# See the full stat card with ASCII sprite
python -m tamagotchi card

# Take care of your buddy
python -m tamagotchi feed
python -m tamagotchi play
python -m tamagotchi pet
python -m tamagotchi sleep

# Quick one-liner status
python -m tamagotchi status
```

State is saved to `~/.local_tamagotchi.json`. Override with the
`TAMAGOTCHI_SAVE` environment variable if you want to keep multiple pets
or sandbox tests.

## How generation works

A pet has two layers:

- **Bones** — species, rarity, shiny, eye style, hat, stats. Pure function
  of your seed (FNV-1a hash → Mulberry32 PRNG). Recomputed every load
  and never trusted from disk, so editing the save file can't give you
  a Legendary.
- **Soul + state** — name, birth time, hunger / happiness / energy.
  Persisted to `~/.local_tamagotchi.json`.

Rarity ladder:

| Rarity     | Drop rate | Stat floor | Hat pool                  |
|------------|-----------|------------|---------------------------|
| Common     | 60%       | 5          | (none)                    |
| Uncommon   | 25%       | 15         | crown / top hat / propeller |
| Rare       | 10%       | 25         | + halo, wizard hat        |
| Epic       | 4%        | 35         | + beanie                  |
| Legendary  | 1%        | 50         | + tiny duck               |

Stats use a peak / dump / scattered roll: one stat is boosted to
`floor + 50..99`, one is held near the floor, and the remaining three
are scattered. Higher rarity ⇒ higher floor ⇒ statistically stronger
pet across the board.

There's an independent 1% chance for any pet to roll Shiny on top.

## Care mechanics

Hunger, happiness, and energy decay in real time between commands.
Feed your pet to reduce hunger, play to boost happiness (costs energy),
pet for a small happiness bump, and sleep to restore energy. The mood
shown in the status line is a function of all three.

## Reset

```sh
python -m tamagotchi reset --yes
```

## License

MIT
