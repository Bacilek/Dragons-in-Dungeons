# TODO

A running scratch list of ideas raised in conversation but deliberately not being worked on yet.
Not a design doc (see `docs/architecture/*.md` for those) — just a place to park things so they
aren't lost. Delete an entry once it's picked up (either built, or promoted to a real design doc).

- **Giant Rat color variants** — make Gray/Brown/White mechanically distinct, not just cosmetic.

- **Class-select "Starting Equipment" tooltip** — `starting_equipment` field still blank/"TBD" for all 4 classes.

- **Sort/triage unused Orc textures** — `sprites/characters/Orcs - unused/Orcs/orcs.png`.

- **Spell icons missing** — Expeditious Retreat, False Life, Fog Cloud, Invisibility (all render blank, `icons/spells/1|2/`).

- **Body armor icons missing** — all 12 placeholder-reuse `materials/plate/iron.png`/`gold.png`: Padded, Leather, Studded Leather, Hide, Chain Shirt, Scale Mail, Breastplate, Half Plate, Ring Mail, Chain Mail, Splint, Plate.

- **Mold icon** — placeholder-reuses `materials/plate/iron.png`.

- **Scroll icon** — no dedicated scroll sprite yet, every Scroll of &lt;Spell&gt; reuses that spell's own icon.

- **Difficult terrain status icon/effect** — no `icons/status/` art exists at all yet (shares `slowed.png` placeholder).

- **Enemy stat blocks missing** — Masked Orc (Orc), Orc Shaman (Priest), Wogol (Hobgoblin), Pumpkin Dude (Vineblight), Big Demon (Barbed Devil), Necromancer (Mage).

- **Phase Spider enemy** — new enemy type, needs a Web sprite (for both spawning webs and the spider itself).

- **Boss starting gear** — let boss choose/pick starting gear instead of fixed loadout.

- **New equip slots** — Trinket, Headgear, Boots, Gloves.

- **Remaining Conditions** — implement the rest beyond Poisoned/Prone/Restrained/Incapacitated (e.g. Frightened).

- **Paladin/Sorcerer sprites** — still no art, plain "?" fallback.

- **Wild Heart Squirrel/Boar sprites** — animal-form art missing.

- **Mold ranged interactions** — resolve Mold-forged ranged weapon vs. Versatile and vs. Reach.

- **Bottles of Mud & Water** — new throwable item types.

- **Subraces** — flesh out remaining race subrace mechanics/flavor abilities (Human miss-reroll, Elf sub-race spell-like ability, Dragonborn breath weapon).

- **Twin Fang R1 redesign** — its Off-hand/Nick Hunter's Mark bonus is now baseline (no longer talent-gated), so R1 is a dead rank until it gets a new effect.

- **Ranger icon art missing** — no icons under `icons/classes/ranger/` yet (Hunter's Mark, Trailblazer/Bloodhound/Twin Fang all render via the name-text fallback).

- **Spiderling enemy stat block** — smaller/weaker Spider variant (Small/Medium, low CR, early-floor filler), reusing the same Spider/{idle,run}.png sheet at a smaller `sprite_scale` than the Large Spider's 1.0.
