"""Command-line interface for the local tamagotchi."""

from __future__ import annotations

import argparse
import sys
import uuid

from . import storage
from .pet import Pet
from .render import render_card, status_line


def _require_pet() -> Pet:
    pet = storage.load()
    if pet is None:
        print("No pet found. Hatch one with: tamagotchi hatch")
        sys.exit(1)
    return pet


def cmd_hatch(args: argparse.Namespace) -> int:
    existing = storage.load()
    if existing and not args.force:
        print(f"You already have a pet: {status_line(existing)}")
        print("Use --force to replace them (this cannot be undone).")
        return 1
    seed = args.seed or uuid.uuid4().hex
    pet = Pet.hatch(seed=seed, name=args.name)
    storage.save(pet)
    print("An egg cracks open...")
    print()
    print(render_card(pet))
    return 0


def cmd_status(_: argparse.Namespace) -> int:
    pet = _require_pet()
    print(status_line(pet))
    storage.save(pet)
    return 0


def cmd_card(_: argparse.Namespace) -> int:
    pet = _require_pet()
    print(render_card(pet))
    storage.save(pet)
    return 0


def _do_action(method_name: str) -> int:
    pet = _require_pet()
    msg = getattr(pet, method_name)()
    storage.save(pet)
    print(msg)
    print(status_line(pet))
    return 0


def cmd_feed(_: argparse.Namespace) -> int:
    return _do_action("feed")


def cmd_play(_: argparse.Namespace) -> int:
    return _do_action("play")


def cmd_pet(_: argparse.Namespace) -> int:
    return _do_action("pet")


def cmd_sleep(_: argparse.Namespace) -> int:
    return _do_action("sleep")


def cmd_reset(args: argparse.Namespace) -> int:
    pet = storage.load()
    if pet is None:
        print("No pet to reset.")
        return 0
    if not args.yes:
        print(f"This will permanently delete {pet.name}. Use --yes to confirm.")
        return 1
    storage.delete()
    print(f"{pet.name} has flown away. Goodbye, friend.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="tamagotchi",
        description="A local terminal virtual pet.",
    )
    sub = p.add_subparsers(dest="command", required=True)

    hatch = sub.add_parser("hatch", help="Hatch a new pet.")
    hatch.add_argument("--seed", help="Deterministic seed (any string).")
    hatch.add_argument("--name", help="Override the generated name.")
    hatch.add_argument("--force", action="store_true",
                       help="Replace an existing pet.")
    hatch.set_defaults(func=cmd_hatch)

    sub.add_parser("status", help="Show a one-line status.").set_defaults(func=cmd_status)
    sub.add_parser("card", help="Show the full stat card.").set_defaults(func=cmd_card)
    sub.add_parser("feed", help="Feed your pet.").set_defaults(func=cmd_feed)
    sub.add_parser("play", help="Play with your pet.").set_defaults(func=cmd_play)
    sub.add_parser("pet", help="Pet your pet.").set_defaults(func=cmd_pet)
    sub.add_parser("sleep", help="Let your pet rest.").set_defaults(func=cmd_sleep)

    reset = sub.add_parser("reset", help="Delete your pet.")
    reset.add_argument("--yes", action="store_true", help="Confirm deletion.")
    reset.set_defaults(func=cmd_reset)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)
