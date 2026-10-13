# Boss arena: drag and drop

Audience: level designers. One scene gives you a complete Artemis fight.

`scenes/enemies/bosses/artemis_boss_arena.tscn`

## What is inside

| Part | What it does |
|---|---|
| `ArtemisBossArena` (a `BossArena`) | Trigger, two doors, camera lock, boss name and health bar, reward, memory of the defeat |
| `Artemis` (child) | The boss. `enemy_id` is already `greece_artemis` |
| `Sfx` | Three empty audio slots (doors, intro) |

## Place it

1. Drag the scene into your level.
2. Put its origin on the **floor line**, at the horizontal **centre of the room**. The prefab is sized for a 936x480 room (Greece T3): the arena rect runs from the floor up 480 px and 468 px to each side.
3. In the editor you see the debug draw: **cyan** arena (the walls Artemis clamps to; the thin cyan line below it is the camera rect, the arena grown by `camera_floor_margin`), **yellow** trigger (Luz entering it starts the fight), **red** doors, **white dot** the reward spot.
4. Resize in the inspector, group by group: `Arena`, `Trigger`, `Doors`. Keep the trigger away from the doors. Do not scale or rotate the arena node: resize the rects instead.
5. The doors must sit just inside real walls, so Luz cannot leave. Their height should cover the room's doorways.

## Rules

- **The camera rect bottom must include the floor tiles.** The locked camera is clamped to `arena_rect` plus `camera_floor_margin` (default 60 px) below the floor line. `arena_rect`'s bottom edge is the floor line, so with a margin of 0 the floor slab drops out of view when the fight starts. Keep the margin at least as tall as your floor tiles.
- **`enemy_id` must be unique per level.** The defeat is remembered by it. Two bosses with the same id share one corpse.
- Give the arena a different `boss_name` if you localize it.
- One-way platforms inside the arena are fine. Artemis never stands on them; her arrows, the rain and the moon dive all respect their physics.
- Put a **Stillness Desk before the arena** (the Hollow Knight bench rule), so a death never costs a long walk. Give it a unique `checkpoint_id` (`scenes/world/stillness_desk.tscn`).

## The reward and the defeat

- Beating Artemis opens the doors, releases the camera and drops the double jump pickup at the arena centre.
- She **stays dead for the whole run, as a corpse where she fell.** A desk rest, Luz dying, or leaving and coming back never revives her, and the corpse has no collision, no contact damage and gives no soul.
- If Luz leaves before taking the pickup, it **appears again** the next time the arena loads, until it is claimed. A reload can never lose the double jump.
- `BossProgress` (autoload) holds all of this per boss: defeated, where the corpse lies, reward claimed.
- **Save system note:** the project has no disk save yet. When one exists, save `BossProgress.to_dict()` and restore it with `from_dict()` in the **same save as Luz's abilities (the double jump)**. Out of sync they can softlock the zone.

## Test it

Open `scenes/levels/test/artemis_arena.tscn` (this prefab plus one middle platform and the HUD) and run the scene. Headless coverage lives in `tests/boss_arena_test.gd` and `tests/artemis_boss_test.gd`.

## Tuning and art

- Every number of the fight is an `@export` on the **`Artemis`** node, grouped: `Movement`, `Platforms`, `Dodge`, `Feint`, `Stagger`, `Interrupt`, one group per attack, `Phases`, `Defeat`, `Final Blow` and `Camera Shakes`.
- Arena timings (doors, intro, defeat beat) and the door shake are on the arena node.
- Animation and sound hooks: `docs/bosses/ARTEMIS_ANIMATIONS.md` (the animation contract and the audio cue table).
