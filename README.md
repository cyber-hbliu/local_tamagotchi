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

A pet's species, rarity, name, hat, eye style, and 5 personality stats
(DEBUGGING / PATIENCE / CHAOS / WISDOM / SNARK) are all derived from
your seed via a deterministic Mulberry32 PRNG. Same seed in, same pet
out — every time.

Rarity drop rates:

| Rarity            | Drop rate |
|-------------------|-----------|
| Common            | 60%       |
| Rare              | 25%       |
| Epic              | 10%       |
| Legendary         | ~4%       |
| Shiny Legendary   | 0.01%     |

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
