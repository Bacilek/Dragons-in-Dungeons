# Weapon Tiers — Design Doc

**Status: design-only, nothing in this doc is implemented yet.** Written after the Unified Weapon
Tooltip pass (`scripts/items/CLAUDE.md`'s "Unified weapon tooltip format") gave every weapon a real
5e gold/silver price. Mirrors the format of `cr-budgeted-spawning-design.md` (numbered sections,
"already in place vs. greenfield", code-snippet-driven, explicit deferred-scope list).

---

## 1. The problem

Real D&D 2024 gold prices (which every current weapon now uses verbatim — see
`scripts/items/CLAUDE.md`'s "Every weapon is now priced") **do not track combat power** in this
engine the way a Shattered-Pixel-Dungeon-style tier list would want. 5e prices reflect crafting
cost/rarity flavor, not balance:

| Weapon | Price | `fmin`/`fmax` (today) | Dice | Mastery | Category |
|---|---|---|---|---|---|
| Quarterstaff | 2sp | 1–10 | 1d6/1d8 (versatile) | Topple | Simple |
| Javelin | 5sp | 1–10 | 1d6 | Slow | Simple |
| Spear | 1gp | 1–10 | 1d6/1d8 (versatile) | Sap | Simple |
| Dagger | 2gp | 1–10 | 1d4 | Nick | Simple |
| Handaxe | 5gp | 1–10 | 1d6 | Vex | Simple |
| Maul | 10gp | 3–10 | ~2d6 (avg 7) | Topple | Martial |
| Torch | 10gp | 1–10 | 1d4 | *(none)* | Simple |
| Glaive | 20gp | 3–10 | 1d10 + Reach | Graze | Martial |
| **Rapier** | **25gp** | **1–10** | 1d8 finesse | Vex | Martial |
| **Greataxe** | **30gp** | **starting gear, no `fmin`/`fmax` — never floor loot** | 1d12 | Cleave | Martial |
| Greatsword | 50gp | 3–10 | ~2d12 (avg 7) | Graze | Martial |
| Short Bow | 50gp | 2–6 | 1d6 ranged | Vex | Simple |
| Longbow | 50gp | 5–10 | 1d8 ranged, long 20 | Slow | Martial |
| Heavy Crossbow | 120gp | 5–10 | 1d10 ranged, long 16 | Push | Martial |

Two concrete problems fall out of this table:

1. **Rapier is priced like a mid/late weapon (25gp, Martial, 1d8 finesse) but gated like a Tier-1
   starter (`fmin=1`)** — it can appear on floor 1 right alongside the Dagger/Quarterstaff, despite
   being strictly stronger than everything else available that early. Nothing else has this
   mismatch this badly, but it's evidence `fmin`/`fmax` was authored ad hoc per weapon, not from a
   single tier table.
2. **The Barbarian's Greataxe (1d12, the single best damage die of any melee weapon, a free
   mastery, Martial proficiency the class already has) is guaranteed starting gear, floor 1, no
   gate at all.** Per the direct owner's own framing: "pokud Barbarian dostane Greataxe tak je to
   pro něj end game" — there's no floor-loot weapon that meaningfully upgrades a Barbarian's damage
   output for the rest of the run unless it's a *magic* Greataxe (`+1`/attuned bonus — infrastructure
   exists, `scripts/items/CLAUDE.md`'s "Attunement", but no concrete magic weapon item exists yet).
   A brand-new level-1 Barbarian is handed what should be a Tier-4 find.

---

## 2. What already exists, reused as-is

- **`Item.gold_value`/`silver_value`** — real price per weapon, now fully populated (§ "Every
  weapon is now priced" in `scripts/items/CLAUDE.md`). This doc does NOT propose changing any
  price — prices stay 5e-authentic; only `fmin`/`fmax` (and, conditionally, starting-gear
  placement) are up for revision.
- **`Item.floor_min`/`floor_max`** (`fmin`/`fmax` pool keys) — this IS the tier-gate mechanism
  already, exactly like SPD's tier system: `_spawn_items()`/`_spawn_locked_doors()`/
  `_spawn_treasure()` all filter `ITEM_POOL` by `current_floor` against this band. **No new
  mechanism needs to be built** — this doc is about re-deriving each weapon's `fmin`/`fmax` from an
  explicit tier assignment instead of the current per-weapon ad hoc values, and about extending the
  same band concept to two places that currently bypass it entirely (Barbarian starting gear, boss
  loot).
- **CR-budgeted enemy spawning** (`cr-budgeted-spawning-design.md`, implemented) — a precedent for
  "a numeric field the designer already authored (there: `cr`; here: `gold_value`) drives a
  spawn-weighting decision" — this doc's Tier table plays the same conceptual role `"cr"` plays for
  enemies, just for `ITEM_POOL` weapons instead.
- **Boss loot** (`scripts/world/CLAUDE.md`'s "Boss floors" / `drop_boss_loot()`) — currently
  **potions-only**, no weapon ever drops from a boss. This is the natural hook for "late-game
  weapons should come from bosses, not the flat floor-loot roll" (see §5).

**Greenfield:**
- No explicit Tier number/label anywhere in the codebase — `fmin`/`fmax` bands exist per-weapon but
  were never derived from a shared table.
- No weapon ever drops from boss loot.
- No resolution yet for what the Barbarian (or any class with guaranteed starting gear) should
  start with instead of a Tier-4 weapon — **explicitly unresolved, see §6**.

---

## 3. Proposed tiers

Five tiers (SPD has Tier 1–5; this roster is small enough that Tier 0 covers the non-combat-focused
Torch instead of needing a full 5th combat tier yet). Each tier maps to an `fmin` floor band —
`fmax` stays `10` for every tier (nothing currently ages out of the loot pool by design, matching
today's convention).

| Tier | `fmin` | Weapons | Rationale |
|---|---|---|---|
| **0** (utility) | 1 | Torch | Priced for its light/utility mechanic, not combat — deliberately excluded from the combat power ranking below. |
| **1** (starter) | 1 | Quarterstaff, Spear, Dagger, Handaxe, Javelin | Cheapest 5 (2sp–5gp), 1d4–1d6 dice, Simple category — every class can wield at least one Tier-1 weapon day one. |
| **2** (early) | 3 | Maul, Glaive, Short Bow | 10–50gp band but each has a real early-game-appropriate ceiling (Maul's Topple, Glaive's Reach, Short Bow's ranged access) rather than a flat damage jump — Short Bow's `fmin` stays where it already is (2), not bumped to 3, since ranged access this early is a class-defining Ranger tool, not a power spike. |
| **3** (mid) | 4–5 | **Rapier** (moved from 1 → 4), Greatsword, Longbow | Rapier's move is the one concrete `fmin` change this table proposes outright (see §1) — 25gp/1d8-finesse/Martial doesn't belong next to a 2sp Quarterstaff. Longbow/Greatsword keep roughly their current bands. |
| **4** (late) | 6–8 | Heavy Crossbow, **Greataxe** (moved from "never floor loot" → a real `fmin`/`fmax` entry) | Heavy Crossbow already sits here by price (120gp) and gate (`fmin=5`, proposed bump to 6 for a cleaner tier boundary). Greataxe becomes an actual **find** instead of guaranteed gear — the fix to §1's second problem, contingent on §6's resolution. |

**This table is a starting proposal, not locked math** — same disclaimer `cr-budgeted-spawning-design.md`
§2 makes about its own constants: tune tier boundaries during playtesting, especially the Tier
2/3 boundary (Short Bow vs. Rapier is a judgment call about ranged-access-vs-raw-damage that's
easy to get wrong on paper).

---

## 4. Enemy weapon drops (secondary tie-in, not required for v1)

Orc Warrior/Ogre already drop a **Javelin**-flavored item via the unrelated `"thrown_weapon"` enemy
schema mechanism (`scripts/entities/CLAUDE.md`) — that's a separate code path (builds its own `Item`
from the enemy pool entry's own fields) and is NOT proposed to change here. This section is about
whether a *generic* enemy could ever drop a real `ITEM_POOL` weapon (it currently can't — only gold
and, for bosses, a potion). Noted as a natural v2 extension of this tier table (an enemy whose own
`"cr"` roughly matches a weapon's tier could have a small chance to drop it) but **not designed
further here** — keeping this doc focused on the tier table and the floor-loot/starting-gear fix.

---

## 5. Boss loot (secondary tie-in, not required for v1)

`drop_boss_loot()` is potions-only today. A natural follow-up once tiers exist: a boss could have a
chance to drop a Tier-3/4 weapon appropriate to the floor it guards (floor-5 boss → Tier 3/4 pool,
floor-10 boss → Tier 4) instead of only ever dropping a potion + gold pile. **Not designed further
here** — flagged as a good v2 once the base tier table (§3) is implemented and playtested, same
"don't bundle unrelated follow-ups into one pass" reasoning `cr-budgeted-spawning-design.md` §6
uses for its own deferred items.

---

## 6. Open question: Barbarian (and future classes') starting gear — UNRESOLVED

This is the one part of the tier table that changes actual class-identity gameplay, not just loot
tables, so it needs a decision before implementation — direct owner explicitly deferred this
("necháme to až rozdělíme zbraně do tiers"). Once §3's tiers are settled, pick one:

- **(a) Downgrade to a Tier-1 weapon.** Barbarian starts with e.g. a Handaxe or Spear instead of
  the Greataxe; the Greataxe becomes a genuine Tier-4 floor find (per §3). Cleanest fix, but changes
  the class's opening-turns feel (no more free Cleave from level 1 — Cleave requires actually
  finding a Cleave-mastery weapon, and currently the Greataxe is the *only* Cleave weapon in the
  game, so losing it as a guarantee means a Barbarian might go an entire run without ever seeing
  Cleave unless one drops).
- **(b) Keep a Greataxe-shaped starter, but a mechanically weaker "Worn Greataxe"** (same weapon
  identity/flavor, reduced die or no mastery) distinct from the real floor-loot Greataxe — preserves
  the class fantasy of starting with a big axe while still leaving room for a genuine upgrade later.
  Requires a second `ITEM_POOL`-adjacent entry (starting-gear-only, like today's Greataxe already
  is) plus the real Greataxe added separately at Tier 4.
- **(c) Leave the Barbarian's Greataxe exactly as-is** (accept it as an intentional class
  perk — "Barbarians are strong from turn one") and only apply the Tier table to floor loot / other
  classes' gear. Simplest, zero risk, but doesn't address the specific complaint that motivated this
  doc.

No recommendation is made here on purpose — this is a class-balance/feel decision, not a technical
one, and should be made by the owner after seeing the tier table in §3 land and get played, not
speculatively now.

---

## 7. Scope: v1 vs. deferred

**In scope for v1 (a future implementation pass, once approved):**
- Rederive every weapon's `fmin`/`fmax` from the §3 tier table (mostly confirms existing values;
  Rapier `1→4` and Greataxe `(none)→6` are the two real changes).
- Add the real Greataxe as an `ITEM_POOL` entry (Tier 4, `fmin=6, fmax=10`), separate from
  whatever the Barbarian's starting-gear resolution (§6) ends up being.
- Mirror both changes in `debug_panel.ALL_ITEMS` per the usual item-sync rule.

**Explicitly deferred (noted here, not designed further — don't build unless asked):**
- §6's starting-gear resolution — a decision, not a build task, and gates whether/how §3's Greataxe
  entry interacts with Barbarian onboarding at all.
- §4 (enemy weapon drops) and §5 (boss weapon loot) — natural extensions, not required for the tier
  table itself to be useful.
- Magic/`+N` weapon variants (a `+1 Greataxe` etc.) — `Item.requires_attunement`/`bonus_damage`
  infrastructure already exists (`scripts/items/CLAUDE.md`'s "Attunement") but no concrete magic
  weapon item has ever been authored; a "found a magic version of your Tier-4 weapon" late-game
  hook would need this doc's tiers to exist first anyway.
- A Shop tie-in (`special-rooms-economy-design.md`'s deferred sessions 7e/7f) — tiers would make a
  shop's stock list an obvious next consumer of this same table, but the Shop itself isn't built.

---

## 8. Estimated implementation size

Small once §6 is resolved — purely `fmin`/`fmax` edits on existing `ITEM_POOL` entries plus one new
entry (Greataxe) mirrored into `debug_panel.ALL_ITEMS`. No new fields, no new functions, no changes
to spawn/save/combat code (the existing `_spawn_items()`/`_spawn_locked_doors()`/`_spawn_treasure()`
floor-band filters already read `fmin`/`fmax` generically). The actual blocker to starting work is
§6, not engineering effort.
