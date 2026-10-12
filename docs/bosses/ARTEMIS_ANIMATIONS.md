# Artemis animation contract

Audience: Codex (art agent). Goal: replace Artemis's `Polygon2D` placeholders with final art **without touching gameplay logic**.
Every number below comes from `scripts/enemies/bosses/artemis_boss.gd` (`@export` names in `code`), `spectral_stag.gd`, `boss_telegraph.gd`, `scenes/enemies/bosses/artemis.tscn` and `artemis_arrow.tscn`. Where a frame count is needed it is **derived** (`frames = duration x fps`) and marked as a suggestion.

---

## 1. Purpose, rule 0 and character brief

### Rule 0 (docs/ASSETS.md section 0, highest priority)

Artemis shares the **one art style, one palette, one outline weight and one pixel scale** of Luz and the Greece zone. Anything that does not fit is redone before integration, even if it works.

- Pixel art, integer pixels, `Nearest` filter (`texture_filter = 1`, as `ShadowOwl`).
- Outline: strong dark outline `#1A1410` (ASSETS.md palette), same weight as Luz after scaling.
- Pixel scale: Luz is drawn at 331.5 px body and scaled to 48 px (`LUZ_BODY_PIXELS`, `body_height`). Artemis is a boss, so she is taller than Luz (collision 56 px vs Luz 48 px) but must use the **same on-screen pixel size**: if her sheet is drawn larger than the final size, the scale factor must produce the same apparent pixel grid as Luz. Do not mix scales.
- Total palette stays within the game's ~16-32 colour budget. Greece-specific swatches: see "Unknowns" at the end.

### Character brief

| Aspect | Direction |
|---|---|
| Role | Huntress goddess. Ranged kiter, agile, controlled, never brutish. |
| Silhouette | Slim, tall, upright. Long hair or veil trailing behind (reads motion). Bow is the dominant prop and must read at phone size. |
| Props | Recurve bow (right hand, in front), quiver on back (left side of the sprite when facing right), short dagger at the belt (used only for the slash). |
| Motif | Crescent moon: on the bow tips, a circlet or clasp. Keeps the "moon" read for phase 2. |
| Palette | Cool and restrained, following docs/GOTHIC_ART_DIRECTION.md: dark navy shadows (`#090D1D`, `#101A33`), cobalt edge light (`#24558A`, `#4C79A8`), pale cloth (`#B8C9DC`). Warm accent only on the bow wood and belt (`#D8792E`, `#F0AE4C`). Placeholder hues (green cloak, gold bow) are not binding. |
| Phase 2 "Full Moon" | Same character, same pixel grid. Add **silver accents**: moon-silver glints on bow tips and hair, a faint halo behind the head, brighter cloth highlights. Do not change the silhouette, hitboxes or proportions, so phase 1 clips can be reused with a recolour. |
| Mood | Cold, elegant, dangerous. No gore. |

The silhouette must stay readable against dark navy backgrounds: keep a light value on the body edge.

---

## 2. Technical contract

### 2.1 Nodes the art must respect

| Path (under `Artemis`, a `CharacterBody2D`) | Contract |
|---|---|
| `Visual` (`Node2D`) | Code owns it: `scale = (facing, crouch)`, `position.y` (dive), `rotation`, `scale` and `modulate` (stagger tint, corpse pose), `visible` (off-screen dive). **Never animate these properties from art.** |
| `Visual/Body` (`Polygon2D`) | **Keep.** `Enemy._setup_flash` clones its polygon into a white hurt flash, and `BossTelegraph.bind_body` clones it into the colour glow. Set `visible = false` (as `shadow_owl.tscn`) and make the polygon trace the **final art silhouette** so flash and glow match the sprite. The clones have their own visibility, so a hidden `Body` still flashes. |
| `Visual/AnimatedSprite2D` (new) | The final art. Add it as the **first child of `Visual`** (index 0) so the glow and flash clones, inserted after `Body`, draw above it. `texture_filter = 1`. |
| `Visual/Bow/Muzzle` (`Marker2D`) | **Keep the path.** Arrows spawn here (`@onready _muzzle`) and aim lines start here. Local position now `(17, -34)` (Bow `(13,-34)` + Muzzle `(4,0)`). Match the bow hand to it, or move the node in the scene (position only) and keep draw/release poses within about 6 px of it. |
| Old polygons `Cloak`, `Quiver`, `Belt`, `Head`, `Hair`, `Arm`, `Bow/Limbs`, `Bow/String` | Delete or `visible = false` once the sprite carries them. Logic does not read them. Keep `Bow` (the node) because it parents `Muzzle`. |
| `CollisionShape2D`, `ContactDamage`, `DaggerHitbox`, `DiveHitbox`, `SpectralStag` shapes | **Unchanged.** Art adapts to them (2.3). |
| `Telegraph` (`BossTelegraph`) | Logic API. Art may restyle visuals but not the calls (section 4). |
| `SpectralStag/Body` (`Polygon2D`) | Replace with `SpectralStag/AnimatedSprite2D`; keep or hide `Body` as above. |

### 2.2 Origin, facing and scale

- **Origin = feet, horizontally centred.** The collision box spans y 0 to -56 above the origin.
- **Art is drawn facing RIGHT (+x).** `Visual.scale.x = facing` flips the whole node; the sprite flips for free. Never bake a left-facing variant. Asymmetric props (quiver left, bow right) are therefore correct for the right-facing frame.
- `Visual.scale.y = 0.8` while vault CROUCH is active (`CROUCH_SCALE`, `_apply_visual`). Draw the crouch clip assuming this squash **or** set `CROUCH_SCALE := 1.0` (a tuning constant, not logic) and let the art carry the squash. Pick one; do not double it.
- Scale like other enemies: sheet cell larger than final, `AnimatedSprite2D.scale` set so the character's pixel grid matches Luz (`ShadowOwl` uses `0.28` on a `Visual/AnimatedSprite2D` offset to the collision centre). Offset the sprite so the cell's foot row sits on the origin.
- All frames of all clips share one cell size and one foot row. No per-frame offset correction in code (same rule as `LuzAnimationCatalog`).

### 2.3 Collision and hit shapes the art must match (do not change)

| Shape | Size and position (from origin, right-facing) | Art implication |
|---|---|---|
| Body + `ContactDamage` | 26 x 56 at `(0,-28)`: x +-13, y 0 to -56 | Torso fits ~26 px wide. Bow, hair and cloak may overhang. |
| `DaggerHitbox` | 56 x 40 at `(40,-28)` (`DAGGER_REACH`): x 12 to 68, y -8 to -48 | The slash arc and blade sweep must cover this box during the active frames, and no more than about 8 px beyond. |
| `DiveHitbox` | 44 x 56 at `(0,-28)`, falls with `Visual` | The diving body fits x +-22, y 0 to -56. |
| `SpectralStag` shape | 60 x 48 at `(0,-24)`: x +-30, y 0 to -48 | Stag body fits this box; antlers may rise above. |
| Arrow | Circle radius 5 (10 px diameter) | See section 4. |

### 2.4 Sheet and cell format (follow the existing pipeline)

- One PNG sheet per skin (`artemis_p1.png`, `artemis_p2.png`) under `assets/art/greece/bosses/artemis/`, transparent background, one uniform grid, **one cell size for the whole sheet** (suggest 256 x 256, boss on the same pixel grid as Luz after scaling; Codex may choose another size but must keep it uniform and state it in the manifest).
- Same pipeline as Luz: a JSON manifest (`animation_manifest.json`: `grid {columns, rows, cell_width, cell_height}`, `clips {name: [frame indices]}`, `events {name: frame index}`) and a repack script so feet land on the same row in every cell.
- `p2` sheet has an identical layout and clip list (silver accents only).
- Stag: separate small sheet `spectral_stag.png`, same rules.

### 2.5 Registration: `artemis_animation_catalog.gd` (proposed)

New file `scripts/enemies/bosses/artemis_animation_catalog.gd`, `class_name ArtemisAnimationCatalog extends RefCounted`, mirroring `LuzAnimationCatalog`:

- `const CLIP_SPEEDS` (default fps per clip), `const LOOPING_CLIPS`, `const MANIFEST_PATH`.
- `static func build_sprite_frames(skin: StringName) -> SpriteFrames`: slices grid regions into `AtlasTexture`s (same as `_build_frame_texture`).
- Playback speed is **derived at play time**: `speed = frame_count / duration`, with the duration coming from the logic's own timers (as Luz's `clip_durations`). This keeps art locked to exports and makes phase 2's `phase_two_recover_scale` free.
- Manifest `events` give the key frame (release, impact). The catalog stretches the frames before the event frame to fill the telegraph and the rest to fill the remainder, like `CONTACT_SYNCED_CLIPS`.

### 2.6 How logic calls clips (proposed single hook)

Add to `artemis_boss.gd` one method, and nothing else of logic:

```gdscript
func _play(clip: StringName, duration := 0.0) -> void
```

It does nothing when `_sprite` is null (placeholders keep working), skips if the clip is already playing and looping, and sets `speed_scale` so the clip lasts `duration` (0 = clip default fps). Skin swap: `_set_skin(PHASE_TWO)` in the same file.

Hook points (each is one added line; no behaviour change):

| Call site in `artemis_boss.gd` | Clip(s) |
|---|---|
| `_enter_state(state, duration)` after `_apply_visual()` | State default: `IDLE` -> `idle`; `STAGGER` -> `stagger_in` then `stagger_loop`; `TRANSITION` -> `phase_transition`; `DEFEATED` -> `defeat`; `FEINT` -> `feint_dash` |
| `_update_reposition` / `_kite` (per frame, from `velocity.x`) | `idle` when `velocity.x == 0`; `walk_fwd` when `sign(velocity.x) == _facing`; `walk_back` otherwise. Only while `is_on_floor()` |
| `_start_hop(state, dir, speed, hop, time)` | Add a `clip` argument: `backstep` (from `_try_backstep`, `_try_chain_hop`), `dodge` (from `_try_dodge`), `dagger_flip` (from `_end_active`, DAGGER) |
| `_update_feint` when `_feint_retreating` flips true | `feint_stop` then `feint_retreat` |
| `_set_attack_phase(phase)` | Table in section 3, by `_attack` and phase |
| `_animate_aimed_shot`, `_animate_fan` when `locked` first becomes true | `shot_hold` / `fan_hold` |
| `_animate_moon_dive`, `_begin_dive_fall`, `_end_dive` | `dive_leap`, (hidden), `dive_fall`, `dive_stuck` |
| `_start_vault`, `_launch_vault`, `_land_vault` | `vault_crouch`, `vault_air`, `vault_land` |
| `_try_interrupt` / `attack_interrupted` signal | `interrupt_flinch` (cuts the running telegraph clip) |
| `_try_transition` / phase change at the TRANSITION midpoint | `_set_skin(PHASE_TWO)` |
| `_reset_ai` | `idle`, skin back to phase one |
| `SpectralStag.launch` / `deactivate` | `stag_appear` then `stag_run`; hidden on deactivate |

Signal `attack_interrupted(attack: int)`: emitted when a hit cancels a telegraph (`Attack` value, or -1 for the vault crouch). Hook VFX and the `interrupt_flinch` clip here. After an interrupt her telegraphs cannot be interrupted for `interrupt_cooldown` 3.0 s (`phase_two_interrupt_cooldown` 4.0 s in phase 2): a poise window an optional cue may show. ACTIVE and RECOVER are never interrupted.

Rule: **a clip never decides when a state ends.** The state machine ends the state; the clip is cut or held (last frame) to follow it.

---

## 3. Clip table

Defaults: fps 12 unless stated. "Suggested frames" = `round(duration x fps)` as a starting point; final speed is derived at play time (2.5), so the count is free. Durations are the **phase 1** values; phase 2 recoveries are x`phase_two_recover_scale` (0.85) except `dive_stuck`. Gravity (`Enemy.gravity`, 1400) is used for the airtime figures.

### 3.1 Locomotion and reactions

| Clip | Trigger | Duration source | Loop | Fps / frames | Key frames / events | The pose must convey |
|---|---|---|---|---|---|---|
| `idle` | `State.IDLE`; REPOSITION with `velocity.x == 0` | open-ended (`opening_delay` 0.6 before waking) | loop | 8 / 6 | none | Poised, bow lowered but ready, weight on back foot. Slight breathing and hair sway. |
| `walk_fwd` | REPOSITION, moving toward Luz (`kite_speed` 150) | open-ended | loop | 12 / 6 | Foot contacts on frames 0 and 3. 6 frames at 12 fps = 0.5 s = 75 px per cycle at 150 px/s, so stride about 37 px per step | Calm stalking, bow held ready. |
| `walk_back` | REPOSITION, moving away from Luz | open-ended | loop | 12 / 6 | Same stride, body still faces Luz (`Visual.scale.x`) | Retreating **while facing Luz**: backward steps, bow ready. Must read different from `walk_fwd` at a glance. |
| `backstep` | `BACKSTEP` from `_try_backstep` and `_try_chain_hop`: `backstep_time` 0.28, hop 240, speed 320 | `backstep_time` 0.28; airtime 2x240/1400 = 0.34 s | one-shot | 14 / 5 (0.34 s) | Take-off frame 0; apex about frame 2; land frame 4 (plays through to ground contact) | A quick, light hop away: legs gathered, torso leaning back, bow forward. Reads as evasion, not attack. |
| `dodge` | `DODGE` from `_try_dodge`: `dodge_time` 0.25, hop 200, speed 380 | `dodge_time` 0.25; airtime 0.29 s | one-shot | 14 / 4 | Lower and flatter than `backstep`: a sideways twist/roll away from Luz | Sharper than `backstep`: a reactive sidestep (it answers Luz's attack startup). Keep it visibly different from `backstep`. |
| `feint_dash` | `FEINT`: approach at `feint_speed` 360 until within `feint_stop_distance` 80 or `feint_max_time` 1.2 | variable | loop | 14 / 6 | none | Fast low forward run, head down, **no weapon raised**: it is a bluff, so it must not look like an attack wind-up. |
| `feint_stop` | `_feint_retreating` becomes true (one frame of zero speed) | at most 0.1 s, plays over the start of the retreat | one-shot | 20 / 2 | Skid with boots dragging | A hard brake just outside melee reach. Teaches "she stopped, she is not attacking". |
| `feint_retreat` | `feint_retreat_time` 0.35 at 300 px/s away | 0.35 s | one-shot | 14 / 5 | Ends in a ready stance | Smooth glide back, bow ready. |
| `interrupt_flinch` | `FLINCH` (`_try_interrupt`): a hit during any telegraph, the vault crouch included, cancels the attack. Emits `attack_interrupted(attack)` (`Attack`, or -1 for the vault crouch) | `interrupt_flinch_time` 0.25 s | one-shot | 20 / 5 | Frame 0 on the hit. Code shakes `Visual.position.x` by `interrupt_shake` and applies `FLINCH_TINT` to `Visual.modulate`; do not bake either. Ends into `backstep` (or `vault_crouch` when cornered), never into a lock | Caught mid-draw: the bow snaps off the string, shoulders jerk, eyes narrow. Must read as "her attack was cancelled", lighter than `stagger_in` (no free-hit window follows). Cut the clip from any telegraph pose, so it starts from the pose the cancelled clip was holding. |
| `stagger_in` | `STAGGER` entry (`_enter_stagger`) | 0.15 s | one-shot | 20 / 3 | Recoil frame 0 | Knocked off balance. |
| `stagger_loop` | `STAGGER`, rest of `stagger_time` 1.5 s | 1.35 s (the clip repeats until the state ends) | loop | 8 / 6 | Code already applies `STAGGER_TINT` to `Visual.modulate`; do not bake that tint | Dazed: bow arm low, head down, swaying. A clear "free hits" read. |
| `phase_transition` | `TRANSITION` (`_update_transition`) | `phase_two_transition_time` 1.0 s | one-shot | 12 / 12 | Skin swap to phase 2 at about 0.5 s (frame 6). She stays hittable throughout. Code pulses a silver glow at `TRANSITION_PULSE_RATE` 10 rad/s | Raises the bow to the moon, silver light rising through the body, ends in a ready stance with the halo. Reads as "she got serious", not as an attack: bow aimed up but **no aim line, no amber**. |
| `hurt` | Hit | `flash_time` 0.08 s | **no clip** | n/a | Code-driven white flash from the `Body` polygon clone | Nothing to draw. Keep `Body` accurate so the flash matches. |

### 3.2 Phase 1 attacks

Attack structure in code: TELEGRAPH (`_telegraph_time`, never under `MIN_TELEGRAPH` 0.35) -> ACTIVE (`_fire_attack` runs on its first frame) -> RECOVER. `Visual` stays on the floor; velocity is zero during all three (`_update_attack`).

| Clip | Trigger | Duration source | Loop | Fps / frames | Key frames / events | The pose must convey |
|---|---|---|---|---|---|---|
| `shot_draw` | AIMED_SHOT TELEGRAPH, tracking part | `shot_telegraph_time` 0.6 minus `shot_aim_lock_time` 0.15 = 0.45 s | one-shot | 12 / 5 | Ends at **full draw**. Aim follows Luz during this time | Side-on, feet planted, arrow nocked and string pulled back. One long horizontal line (arm, arrow, bow). Amber glow rises (code). |
| `shot_hold` | AIMED_SHOT, once `_state_left <= shot_aim_lock_time` | `shot_aim_lock_time` 0.15 s | hold | 8 / 2 | The aim is **frozen** here. The solid aim line appears (code). Pose must not change after this frame | A held, absolutely still full draw. The stillness is the cue "dash or jump now". |
| `shot_release` | AIMED_SHOT ACTIVE | `shot_active_time` 0.1 s | one-shot | 20 / 2 | **Frame 0 = release**; the arrow spawns at `Muzzle` on this frame (`_fire_attack`, end of telegraph) | String snaps forward, follow-through arm. |
| `shot_recover` | AIMED_SHOT RECOVER | `shot_recover_time` 0.5 s (p2 0.425) | one-shot | 10 / 5 | Punish window for Luz. Ends in `idle` pose | Lowers bow, exhale, slightly off balance. Must **look open**. |
| `fan_draw` | FAN TELEGRAPH, tracking part | `fan_telegraph_time` 0.45 minus `fan_aim_lock_time` 0.15 = 0.30 s | one-shot | 12 / 4 | Ends at full draw | Draw with **three arrows nocked between the fingers** (`fan_count` 3), bow tilted slightly. Silhouette must differ from `shot_draw` (wider hand, three shafts). |
| `fan_hold` | FAN, once locked | `fan_aim_lock_time` 0.15 s | hold | 8 / 2 | Aim frozen; 3 short lines at `fan_spread_degrees` 15 | Still, three shafts fanned. |
| `fan_release` | FAN ACTIVE | `fan_active_time` 0.1 s | one-shot | 20 / 2 | **Frame 0 = release** of all 3 arrows at once | Wide arm sweep. |
| `fan_recover` | FAN RECOVER | `fan_recover_time` 0.4 s (p2 0.34) | one-shot | 10 / 4 | Punish window | Lowers bow, shoulders drop. |
| `rain_draw` | RAIN TELEGRAPH | `rain_telegraph_time` 0.8 s | one-shot | 12 / 10 | Floor markers appear at 0.2 s (`RAIN_MARKER_DELAY`, frame 2). Bow reaches full skyward draw by frame 7 and holds | **Vertical**: bow pointed straight up (aim line is `Vector2.UP`, 140 px), body leaning back, head tilted skyward. Unmistakably different from a horizontal draw: it is the "look at the floor" cue. |
| `rain_release` | RAIN ACTIVE | `rain_active_time` 0.1 s | one-shot | 20 / 2 | **Frame 0 = release**; arrows spawn `rain_height` 260 above the floor and fall at `rain_arrow_speed` 520, so they land about 0.5 s after release (260 / 520) | Upward snap, string vibrates. |
| `rain_recover` | RAIN RECOVER | `rain_recover_time` 0.9 s (p2 0.765) | one-shot | 10 / 9 | Big punish window ("0.9 s on landing") | Head returns down, arm drops, weary stance. Looks open for a long time. |
| `dagger_windup` | DAGGER TELEGRAPH | `dagger_telegraph_time` 0.35 s | one-shot | 12 / 4 | Ends at fully coiled pose | **Melee, red.** Bow slung or dropped, dagger drawn from the belt, torso coiled low, lunge leg forward. It must NOT look like an archery draw: the bow disappears from the front, which is the key difference from every ranged cue. |
| `dagger_slash` | DAGGER ACTIVE (`_swing_dagger`) | `dagger_active_time` 0.12 s | one-shot | 24 / 3 | Frames 0 to 2 are the damaging sweep covering the `DaggerHitbox` (x 12 to 68, y -8 to -48). `Slash` arc VFX in section 4 | A wide horizontal slash with a clear arc. |
| `dagger_flip` | `BACKSTEP` after the slash (`_end_active`): `dagger_flip_time` 0.35, hop 300, speed 340 | `dagger_flip_time` 0.35 s; airtime 0.43 s | one-shot | 14 / 6 | No punish window; she leaves immediately. If the flip is blocked by a wall or ledge she only gets `dagger_recover_time` 0.15 s: add a 2-frame `dagger_recover` fallback | A full **backflip** with the dagger away. Distinct from `backstep`: rotates through the air. |

### 3.3 Phase 2 and shared moves

| Clip | Trigger | Duration source | Loop | Fps / frames | Key frames / events | The pose must convey |
|---|---|---|---|---|---|---|
| `dive_leap` | MOON_DIVE TELEGRAPH, first part (`_animate_moon_dive`) | `dive_leap_time` 0.4 s | one-shot | 12 / 5 | `Visual.position.y` rises by `-dive_height x rise^2` (code, up to -360 px). At 0.4 s code hides `Visual` and sets her unhittable and harmless | Spring straight up, moon glow rising; she **is still hittable** during the leap. |
| (off-screen) | MOON_DIVE, 0.4 to 1.4 s | `dive_track_time` 0.6 + `dive_lock_time` 0.4 | none | none | `Visual.visible = false`. Marker follows Luz (silver), locks at 1.0 s, held for `dive_lock_time` 0.4 s. A tall silver **column** (`get_dive_column()`, marker slot 1, `dive_marker_width` wide, from `dive_height` down to the floor) is drawn with it, so Luz on a platform in that x sees the dive coming | No clip. All readability comes from the floor marker and glow. |
| `dive_fall` | MOON_DIVE ACTIVE (`_begin_dive_fall`) | `dive_height / dive_speed` = 360 / 900 = 0.4 s fall + `dive_impact_time` 0.1 s = 0.5 s | fall: loop; impact: one-shot | 12 / 2 (fall) + 2 (impact) | `DiveHitbox` armed for the full 0.5 s. **Impact frame at t = 0.4 s** (feet reach `y = 0`); `Visual.position.y` is moved by code, not by the clip | Head-down vertical plunge, silver trail. (Design text says "diagonal"; the code drop is **vertical**, so draw vertical.) |
| `dive_stuck` | MOON_DIVE RECOVER (`_end_dive`) | `dive_stuck_time` 1.2 s (**never scaled**) | one-shot | 10 / 12 | She is hittable again. Frames 0 to 8 show her stuck (about 0.9 s); frames 9 to 11 show pulling free, so the last frame lands at 1.2 s. Body harmless | Kneeling, planted in the ground, struggling. The biggest punish window: it must look helpless for most of its length, with a clear "freeing herself" cue near the end. |
| `stag_cast` | STAG TELEGRAPH (`_plan_stag`, `_animate_stag`) | `stag_telegraph_time` 0.8 s | one-shot | 12 / 10 | Edge glow plus floor marker at the **far** wall (code). Summon happens at the start of ACTIVE | Both arms spread/raised, moon light gathering; stands still, **no bow aimed**. Reads as "summoning", not as "aiming". Silver, not amber. |
| `stag_summon` | STAG ACTIVE (`_summon_stag`) | `stag_active_time` 0.1 s | one-shot | 20 / 2 | **Frame 0 = summon**; `SpectralStag.launch` runs on this frame | Hand thrust toward the stag. |
| `stag_recover` | STAG RECOVER | `stag_recover_time` 0.6 s (p2 0.51) | one-shot | 10 / 6 | The stag is still crossing the arena during this time | Arms lower, light fades. |
| `vault_crouch` | `VAULT` / `VaultPhase.CROUCH` (`_start_vault`) | `vault_telegraph_time` 0.35 s (floor `MIN_TELEGRAPH`) | one-shot | 14 / 5 | White glow (`VAULT_COLOR`) rises (code) | Tight crouch, **white**, pinned against a wall: "she is about to jump over you". Differs from the red dagger and the amber draws: no weapon raised. |
| `vault_air` | `VaultPhase.AIR` (`_launch_vault`) | flight = 2 x sqrt(2 x 1400 x 130) / 1400 = **0.86 s** (apex `vault_apex_height` 130, rise about 0.43 s) | one-shot (holds on landing) | 12 / 8 | Apex at about frame 4. She is **not** `Visual`-offset: the arc is physical (`CharacterBody2D`), so the art must be drawn in place | Arc over Luz: tucked body, trailing hair, bow clear. Contact damage is off (`vault_contact_damage` false) so the pose must not look like an attack. |
| `vault_land` | `VaultPhase.LAND` | `vault_recover_time` 0.3 s | one-shot | 12 / 4 | Dust VFX at frame 0 | Soft landing, recovers to ready stance. |
| `defeat` | `DEFEATED` (`make_corpse_at`) | `defeat_time` 0.9 s | one-shot, **holds its last frame forever** | 10 / 9 | The killing blow first plays a screen flash, a freeze and a slow motion (code, `BossFeel`). Code then slumps `Visual` (rotation, squash, dim) and drops `Visual/Bow` on the ground over `defeat_time`; the node is NOT hidden: she stays as a corpse where she fell for the rest of the run. A boss restored as already dead skips the clip and shows the last frame at once | Kneels, bow drops, collapses forward and stays down. The last frame is the permanent corpse: it must read as clearly defeated, lie on the floor line, and not look like a pose she could get up from. It is dimmed by code (`Enemy.CORPSE_TINT`), do not bake the dimming |
| `intro` | Entry to the arena (BossArena T4) | **TBD** | one-shot | TBD | TBD. Must end in the `idle` pose and run before the first `opening_delay` | **TBD**: optional. Not part of the first integration. |

### 3.4 Spectral stag (`SpectralStag`, `Area2D`)

| Clip | Trigger | Duration source | Loop | Fps / frames | Key frames / events | The pose must convey |
|---|---|---|---|---|---|---|
| `stag_appear` | `launch` | 0.15 s | one-shot | 20 / 3 | Fade-in; the code makes it visible at once and arms the hitbox (`set_deferred monitoring`) | Silver stag materialises from the wall. Hitbox is live from frame 0, so keep the first frame already near full size. |
| `stag_run` | Charge (`stag_speed` 520 px/s) | until the far end (about 1.5 s for 800 px) | loop | 12 / 8 | 8 frames at 12 fps = 0.67 s = 347 px per gallop cycle at 520 px/s. Body fits the 60 x 48 box | Fast gallop, low and long, antlers back. Translucent silver (about 60% alpha) so Luz reads it as a spectral hazard: **jump or dash it**. |
| `stag_vanish` | `deactivate` | optional | one-shot | optional | The code hides the node instantly at the far end. A fade needs a one-line hook in `deactivate`; mark as optional | Dissolves into moonlight. |

Orientation: the stag is drawn facing right; `scale.x = dir` flips it.

---

## 4. VFX and props

| Item | Current placeholder | Contract |
|---|---|---|
| Arrow (`artemis_arrow.tscn`) | `Visual` polygon, about 31 px long (x -17 to 14), 8 px tall, amber `#FFC74D`-like | Sprite drawn pointing **+x** (the logic rotates by `direction.angle()`). Collision circle radius **5**, centred on the projectile origin (the sprite pivot, which sits 3 px behind the tip in the placeholder); keep the shaft about 31 px so aimed-shot readability is unchanged. Amber accent on the fletching/tip (ranged colour). Pixel scale per rule 0. |
| Rain arrows | Same scene, direction `Vector2.DOWN` | Packed every 10 px (`RAIN_ARROW_STEP`) across 56 px zones; each is the same sprite rotated 90 degrees. They fall at 520 px/s, so a 3-frame loop at most; keep the sprite narrow (about 6 px) so the zone reads as a dense curtain. |
| Aim line | `Line2D`, 3 px (`LINE_WIDTH`), amber; alpha 0.45 while tracking (`LINE_TRACKING_ALPHA`), 1.0 when locked | Keep both states: **dim and moving = still tracking, solid = locked**. Length 520 (shot), 300 (fan, one per arrow), 140 (rain, upward). May become a dotted pixel line; it must keep the dim/solid contrast. |
| Floor markers | `Polygon2D` unit rectangles, 8 px tall (`RAIN_MARKER_HEIGHT`), bright edges (`MARKER_EDGE_SHARE` 0.07), pulse faster as the hit nears. Rain markers sit on the surface the arrows will hit: on a one-way platform top when one covers the zone, split in two over a platform edge. The dive adds a vertical silver column (slot 1, about half the marker alpha) | Replace with a pixel-art ground glyph per zone; zone width 56 (rain), 56 (dive, `dive_marker_width`), 60 x 48 at the wall (stag). Keep the **edges brighter than the fill** and the **pulse that accelerates**. |
| Colour language (`BossTelegraph`) | amber `#FFB840`-ish (`RANGED_COLOR`), red (`MELEE_COLOR`), silver `(0.8,0.9,1.0)` (`MOON_COLOR`), white (`VAULT_COLOR`) | **Non-negotiable**: amber = ranged, red = melee, silver = moon (phase 2: dive, stag, transition), white = vault. Colour is the second cue; the pose silhouette is the first (section 5). |
| Body glow | Tinted clone of `Body` polygon, alpha up to 0.65 (`GLOW_MAX_ALPHA`) | Needs an accurate `Body` silhouette. Rises over the telegraph; at ACTIVE it clears. May be replaced by an outline or rim shader if the call API (`set_glow`) stays. |
| Dagger slash | `DaggerHitbox/Slash` polygon, red, shown only while the hitbox is armed | A crescent sweep covering x 12 to 68, y -8 to -48, visible exactly during `dagger_active_time` 0.12 s. |
| Dive impact | `DiveHitbox/Impact` polygon (silver), shown while armed | A vertical silver shaft/crater that follows `Visual` down for 0.4 s, then a flash at impact for 0.1 s. |
| Dust on landings | None | Small puff at: `backstep`/`dodge`/`dagger_flip` landing, `vault_land` frame 0, dive impact (larger). Pure VFX; must not extend past 0.3 s. |
| Stag effect | Translucent `Body`, alpha 0.6 | Silver spectral stag with a short trail; keep alpha about 0.6 and the 60 x 48 footprint. |
| Phase-2 aura | None (code glow only during the transition) | Optional persistent faint silver halo behind the head in the `p2` skin. Must be part of the sprite (no extra logic) and must not hide the telegraph colours. |

---

## 5. Telegraph readability rules (non-negotiable)

1. **Minimum 0.35 s.** `MIN_TELEGRAPH = 0.35` is enforced by `maxf` in `_telegraph_time` and by `@export_range(0.35, ...)`. No clip, skin or VFX may shorten the readable part below it. The dive's final lock is also `max(dive_lock_time, 0.35)`.
2. **Art follows timings, never the other way.** The exports in sections 2-3 are the source of truth. If the art needs more time, **raise the export** (and note it in the PR), do not change the logic or stretch the telegraph silently. Playback speed is derived from the exports (2.5); never hard-code a clip length that differs from a timer.
3. **Distinct anticipation per attack, readable by silhouette alone** (convert the frame to flat black: every row must still differ):

   | Attack | Silhouette cue |
   |---|---|
   | Aimed shot | Long horizontal line (arm + arrow + bow), side-on, still at lock |
   | Fan | Same line but with a wide three-shaft splay |
   | Rain | Bow **vertical**, body arched back, head up |
   | Dagger | **No bow in front**, low coiled lunge with a short blade |
   | Moon dive | Leap upward and disappear; floor marker and column only |
   | Stag | Both arms spread/raised, **no aimed weapon** |
   | Vault | Tight white crouch, no weapon |
   | Feint | Run with head down and bow **not** raised |

4. **Frozen aim is a pose, not an effect.** The last 0.15 s of the shot and fan (`*_aim_lock_time`) must be visibly still so the player learns "when she stops moving, dash".
5. **Mobile legibility.** The viewport is 720 x 1280 portrait. Check every clip at the real on-device size (Luz about 48 px tall): the key pose must read when the sprite is about 56 px tall, without zooming. Prefer chunky 2-3 px shapes over fine detail; keep the bow at least 3 px thick.
6. **Release and impact are exact.** The arrow release frame lands on the first frame of ACTIVE (end of TELEGRAPH). The dagger swing frames cover exactly `dagger_active_time`. The dive impact frame lands at 0.4 s of ACTIVE. If the art disagrees, move the key frame in the manifest, not the timer.
7. **Recoveries must look open.** Every recover and stuck clip needs a clearly vulnerable pose, because those are Luz's punish windows (0.4 to 1.2 s).

---

## 6. Integration checklist for Codex

1. Read `docs/ASSETS.md` rule 0 and `docs/GOTHIC_ART_DIRECTION.md`; fix the palette and outline.
2. Draw all clips facing right on one cell size and one foot row; write `animation_manifest.json` (grid, clips, `events`).
3. Create `p1` and `p2` sheets with identical layout; run the repack script so feet align.
4. Create `scripts/enemies/bosses/artemis_animation_catalog.gd` (2.5) and the stag equivalent.
5. In `artemis.tscn`: add `Visual/AnimatedSprite2D` as the first child of `Visual`, `texture_filter = 1`, scale to Luz's pixel grid. Set `Visual/Body` `visible = false` and fit its polygon to the art. Hide or delete the old polygons (keep `Visual/Bow/Muzzle`).
6. In `artemis_boss.gd`: add `_play` and `_set_skin` and the one-line hook calls from 2.6. **No other logic change.** Do not alter exports, enums, signals, timers, collision shapes or the public API.
7. Replace `BossTelegraph` visuals and `DaggerHitbox/Slash`, `DiveHitbox/Impact`, the stag `Body` and the arrow `Visual` with art, keeping the node paths, the colour language and the API.
8. Decide `CROUCH_SCALE` (2.2).
9. Check every clip in the test arena (`scenes/levels/test/artemis_arena.tscn`) at phone size.
10. Raise any export the art needs (rule 2 above) and list it in the PR.

### Acceptance criteria

- `tests/artemis_boss_test.gd` still passes unchanged (it reads `Visual/Body`, `Visual/Bow/Muzzle`, `Visual` visibility and the exported timings).
- The full headless suite and the headless boot (`--headless --path . --quit-after 120`) show no new script errors.
- The hit flash still works (white copy of `Body`, `flash_time` 0.08 s) and matches the art silhouette.
- Collision, `DaggerHitbox`, `DiveHitbox`, `SpectralStag` and arrow shapes are byte-for-byte unchanged.
- Every attack keeps its exported telegraph; no telegraph is under 0.35 s; telegraph colours match the colour language.
- Placeholders still work if the sprite is absent (`_play` is a no-op when there is no sprite).
- No `print()`, typed GDScript, no hand-edited `.uid` files (AGENTS.md).

---

## Unknowns (not determined from the code)

- Greece-specific palette swatches: `docs/ASSETS.md` and `docs/GOTHIC_ART_DIRECTION.md` describe the library and Luz; no Greece palette doc was found. Codex must confirm one before drawing.
- Whether `Enemy.gravity` is overridden in `artemis.tscn`: not set there, so the default 1400 is assumed for all airtime figures.
- Final on-screen height of Artemis relative to Luz (collision is 56 vs 48; the visual scale is a Codex decision).
- Aim-angle range of the shot: `_aim_dir` is free-angle; no angle limit exists in code. Optional `aim_up` / `aim_level` / `aim_down` draw variants are TBD.
- Stag travel duration: depends on the arena width found by the wall probe (up to `arena_half_width` 400 each side, so about 1.5 s at most with no wall).
- `intro` and `stag_vanish`: not defined in code; TBD.

---

## 7. Audio cues

Every cue is an empty `AudioStreamPlayer2D` under `Artemis/Sfx` (arena cues: `AudioStreamPlayer` under `BossArena/Sfx`). A sound designer only assigns a stream to the node; no code change. A slot with no stream is silent and never an error. Each cue also emits the `sfx_cue(cue)` signal (boss) or `BossArena.sfx_cue`, even when silent, so tools can follow the events. Cues share the Master bus (the project defines no other bus yet).

| Cue (node path) | Trigger event (code) | Intended feel | Supports telegraph |
|---|---|---|---|
| `Sfx/BowDraw` | Start of the aimed shot and the fan telegraph (`_begin_telegraph`) | Creak of a bow being drawn, rising tension, about 0.5 s | Aimed shot 0.6 s, fan 0.45 s |
| `Sfx/BowRelease` | The arrow(s) leave the bow: shot, fan and rain launch (`_fire_attack`) | Sharp string snap and whoosh | Closes the shot, fan and rain telegraphs |
| `Sfx/RainWhistle` | Start of the arrow rain telegraph (`_begin_telegraph`) | A rising whistle of arrows climbing the sky, about 0.8 s | Arrow rain 0.8 s |
| `Sfx/RainImpact` | The first rain arrow reaches a surface (`_rain_fall_time` after release) | Many thin thuds into the ground | Marks the end of the rain, start of the punish |
| `Sfx/DaggerSwish` | The dagger swing begins (`_swing_dagger`) | A short, close blade slash | Dagger 0.35 s |
| `Sfx/VaultCrouch` | The cornered vault crouch begins (`_start_vault`) | A quick gather and cloth rustle, subtle | Vault crouch 0.35 s |
| `Sfx/DiveLeap` | Start of the moon dive telegraph (`_begin_dive`) | A silvery rising leap, fading out as she leaves the screen | Moon dive leap and track |
| `Sfx/DiveImpact` | She lands in the ground (`_update_dive_fall`, same frame as the camera shake) | A heavy impact with a moonlit ring | Moon dive lock marker |
| `Sfx/StagHorn` | Start of the stag telegraph (`_begin_telegraph`) | A distant horn call, ominous, about 0.8 s | Spectral stag 0.8 s edge glow |
| `Sfx/StagCharge` | The stag is launched (`_summon_stag`, with the light camera shake) | Hooves and spectral rush crossing the arena | Closes the stag telegraph |
| `Sfx/Flinch` | A hit cancels a telegraph (`_try_interrupt`) | A short grunt and a snapped string | Any cancelled telegraph |
| `Sfx/Stagger` | She is staggered (`_enter_stagger`) | A dazed stumble and exhale | None (reaction) |
| `Sfx/PhaseTwo` | The phase-two transition starts (`_try_transition`, with the camera shake) | Moonlight swelling, a rising choir or chime | None (phase beat) |
| `Sfx/Defeat` | The killing blow (`_play_final_blow`, with the flash, freeze and shake) | A final, resonant impact fading into silence | None (defeat) |
| `BossArena/Sfx/DoorsClose` | The doors fall shut (`BossArena._set_doors(true)`, with a light camera shake) | Heavy stone doors slamming | Fight start |
| `BossArena/Sfx/DoorsOpen` | The doors rise (`BossArena._set_doors(false)`) | Stone grinding open, relief | Fight end |
| `BossArena/Sfx/BossIntro` | The name card shows (`BossArena._start_fight`) | A short sting or drum as the title appears | None (intro) |

Camera shakes (strengths are `@export`s on `Artemis`, group "Camera Shakes" and "Final Blow", and on `BossArena`, group "Camera Shake"): phase-two transition, moon dive impact, stag launch (light), doors closing (light), killing blow (strong).
