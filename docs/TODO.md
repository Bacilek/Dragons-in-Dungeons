# TODO

A running scratch list of ideas raised in conversation but deliberately not being worked on yet.
Not a design doc (see `docs/architecture/*.md` for those) — just a place to park things so they
aren't lost. Delete an entry once it's picked up (either built, or promoted to a real design doc).

- **Differentiate Giant Rat color variants mechanically.** Right now Gray/Brown/White are a purely
  cosmetic random pick (`ENEMY_POOL`'s `"sprite_variants"`, `scripts/entities/CLAUDE.md`). Idea:
  give one color a mechanical edge (e.g. faster, hits harder, a different/extra trait) so the
  recolor also signals a distinct threat, Shattered-Pixel-Dungeon-tier-variant style. Raised while
  adding the base Giant Rat (2026-07-26); not started.

- **Fill in "Starting Equipment" on the class-select info tooltip.** `scripts/ui/class_select.gd`'s
  per-class `"info"` dict (hover the small "i" badge on a class tile) has a `starting_equipment`
  field that's deliberately left `""` (renders as "TBD") for all 4 classes — needs the actual
  starting-gear list per class (see `GameState.give_class_starting_items()` →
  `_give_{class}_starting_items()` in `scripts/autoloads/game_state.gd` for the real granted
  items) written out as player-facing text. Raised 2026-07-26; not started.

- **Sort/triage unused Orc textures.** `sprites/characters/Orcs - unused/Orcs/orcs.png` — not yet
  gone through, sitting there raw. 2026-07-26.
