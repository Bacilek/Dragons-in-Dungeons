# TODO

A running scratch list of ideas raised in conversation but deliberately not being worked on yet.
Not a design doc (see `docs/architecture/*.md` for those) — just a place to park things so they
aren't lost. Delete an entry once it's picked up (either built, or promoted to a real design doc).

- **Giant Rat color variants** — make Gray/Brown/White mechanically distinct, not just cosmetic.

- **Class-select "Starting Equipment" tooltip** — `starting_equipment` field still blank/"TBD" for all 4 classes.

- ~~**Sort/triage unused Orc textures** — `sprites/characters/Orcs - unused/Orcs/orcs.png`.~~ (done — sorted into per-identity folders under `sprites/characters/_unused/`)

- **Body armor icons missing** — all 12 placeholder-reuse `materials/plate/iron.png`/`gold.png`: Padded, Leather, Studded Leather, Hide, Chain Shirt, Scale Mail, Breastplate, Half Plate, Ring Mail, Chain Mail, Splint, Plate.

- **Mold icon** — placeholder-reuses `materials/plate/iron.png`.

- **Torch icons missing** — unlit, lit, and burnt states all reuse the same `weapon_torch.png`.

- **Scroll icon** — no dedicated scroll sprite yet, every Scroll of &lt;Spell&gt; reuses that spell's own icon.

- **Difficult terrain status icon/effect** — no `icons/status/` art exists at all yet (shares `slowed.png` placeholder).

- **Enemy stat blocks missing** — Masked Orc (Orc), Orc Shaman (Priest), Wogol (Hobgoblin), Pumpkin Dude (Vineblight), Big Demon (Barbed Devil), Necromancer (Mage), Boar, Squirrel, Spiderling (see also line below, same gap).

- **Phase Spider enemy** — new enemy type, needs a Web sprite (for both spawning webs and the spider itself).

- **Boss starting gear** — let boss choose/pick starting gear instead of fixed loadout.

- ~~**New equip slots** — Trinket, Headgear, Boots, Gloves.~~ (done — `GameState.equipment` has `boots`/`gloves`/`head`/`trinket`)

- ~~**Remaining Conditions** — implement the rest beyond Poisoned/Prone/Restrained/Incapacitated (e.g. Frightened).~~ (done — Frightened fully implemented, `scripts/entities/CLAUDE.md`'s "Conditions" section; root CLAUDE.md's "Frightened is not yet implemented" line is stale and needs updating)

- **Paladin/Sorcerer sprites** — still no art, plain "?" fallback.

- **Wild Heart Squirrel/Boar sprites** — animal-form art missing.

- **Mold ranged interactions** — resolve Mold-forged ranged weapon vs. Versatile and vs. Reach.

- ~~**Bottles of Mud & Water** — new throwable item types.~~ (done — "Empty bottle mechanic", `scripts/world/CLAUDE.md`)

- **Subraces** — flesh out remaining race subrace mechanics/flavor abilities (Human miss-reroll). ~~Elf sub-race spell-like ability, Dragonborn breath weapon~~ (both done — Elven Lineage + Draconic Breath Weapon).

- **Twin Fang R1 redesign** — its Off-hand/Nick Hunter's Mark bonus is now baseline (no longer talent-gated), so R1 is a dead rank until it gets a new effect.

- ~~**Ranger icon art missing** — no icons under `icons/classes/ranger/` yet (Hunter's Mark, Trailblazer/Bloodhound/Twin Fang all render via the name-text fallback).~~ (done — `icons/classes/ranger/t0/t1/*.png` all exist)

- ~~**Spiderling enemy stat block** — smaller/weaker Spider variant (Small/Medium, low CR, early-floor filler), reusing the same Spider/{idle,run}.png sheet at a smaller `sprite_scale` than the Large Spider's 1.0.~~ (done — `enemy_id: "spiderling"` in `ENEMY_POOL`)

- **More cantrips** — Speak with Animals, Mending, Minor Illusion (promote from Gnomish-Lineage-only to real learnable `CANTRIP_IDS` entries, same treatment Darkness/Detect Magic/Longstrider got) plus Prestidigitation, Thaumaturgy, Druidcraft (net-new, no mechanism yet).

- **Tool proficiencies + Monk/Rogue property-restricted weapon profs** — no `Stats` field exists yet for tool proficiency (Bard's starting instrument — bagpipes/drum/flute/horn/lute/lyre, randomly picked — isn't implemented at all), and `proficient_simple_weapons`/`proficient_martial_weapons` are flat bools with no per-weapon-property granularity, so Monk (Martial-but-Light-only) and Rogue (Martial-but-Finesse-or-Light-only) currently leave `proficient_martial_weapons = false` as a conservative placeholder instead of their real restricted proficiency.

- **Fix "choose known spells" during long rest** - broken/needs cleanup.

- ~~**Fix Elf lineage cantrip not refreshing on long rest**.~~ (done — `elf_lineage_free_casts_remaining` refilled to 1 in `GameState.long_rest()`)

- **Dancing Lights cantrip** - not yet implemented.

- **Verbal spell components should wake sleeping enemies?** - idea, needs thought.
