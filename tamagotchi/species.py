"""The 18 species, ASCII sprites, and hat unlocks."""

SPECIES = [
    "Duck", "Goose", "Cat", "Rabbit", "Owl", "Penguin",
    "Turtle", "Snail", "Dragon", "Octopus", "Axolotl", "Ghost",
    "Robot", "Blob", "Cactus", "Mushroom", "Chonk", "Capybara",
]

SPRITES = {
    "Duck": [
        "  __",
        "<(o )___",
        " ( ._> /",
        "  `---'",
    ],
    "Goose": [
        "   ___",
        "  (o )>",
        "   \\__\\__",
        "    \\___\\",
    ],
    "Cat": [
        " /\\_/\\",
        "( o.o )",
        " > ^ <",
    ],
    "Rabbit": [
        " (\\(\\",
        " (-.-)",
        " o_(\")(\")",
    ],
    "Owl": [
        "  ,_,",
        " (O,O)",
        " (   )",
        "--\"-\"--",
    ],
    "Penguin": [
        "  ,--.",
        " ( oo )",
        " /`--'\\",
        " ^^  ^^",
    ],
    "Turtle": [
        "    _____",
        "   /     \\",
        "__/ () () \\",
        "\\___\\___/_/",
    ],
    "Snail": [
        "     _@_",
        "   _/   \\_",
        "__(o,_,_,o)__",
    ],
    "Dragon": [
        "    /\\___/\\",
        "   ( o   o )",
        "    >  ^  <",
        "   /|     |\\",
        "  ~~       ~~",
    ],
    "Octopus": [
        "   ___",
        "  /o o\\",
        " ( \\_/ )",
        " /|||||\\",
    ],
    "Axolotl": [
        "  >^..^<",
        " /(    )\\",
        "  \"\"\"\"\"\"",
    ],
    "Ghost": [
        "  .-.",
        " ( o.o)",
        " > ^ <",
        " ~~~~~",
    ],
    "Robot": [
        "  [   ]",
        "  |o_o|",
        "  |---|",
        "  /| |\\",
    ],
    "Blob": [
        "  .---.",
        " ( o o )",
        "  '~~~'",
    ],
    "Cactus": [
        "   _",
        "  | |_",
        " _|   |",
        "|_  o |",
        "  |___|",
    ],
    "Mushroom": [
        "  .-\"\"-.",
        " /  o o \\",
        " \\______/",
        "   |  |",
    ],
    "Chonk": [
        "   ___",
        "  (o,o)",
        "  (   )",
        " --\"-\"--",
    ],
    "Capybara": [
        "    ___",
        "  _(o,o)_",
        " / `---' \\",
        "  \"\"   \"\"",
    ],
}

EYE_STYLES = ["o", "O", "^", "•", "x", "·"]

# Rarity-gated hat pools. Common always rolls None; everything Uncommon+
# is guaranteed to wear something.
HATS_BY_RARITY = {
    "Common":    [None],
    "Uncommon":  ["crown", "top hat", "propeller"],
    "Rare":      ["crown", "top hat", "propeller", "halo", "wizard hat"],
    "Epic":      ["crown", "top hat", "propeller", "halo", "wizard hat", "beanie"],
    "Legendary": ["crown", "top hat", "propeller", "halo", "wizard hat", "beanie", "tiny duck"],
}


def sprite_for(species: str) -> list[str]:
    return list(SPRITES.get(species, ["  ?_?", " (   )"]))
