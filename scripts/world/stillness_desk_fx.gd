class_name StillnessDeskFx
extends Node2D

## Choreographs the altar's life on the desk's ritual signals: the light shaft
## and its dust, the vertical halo, flanking candelabras, rim light, beacon
## fireflies, flickering candle, a pendulum that stills while Luz rests (time
## stops), the peak bloom, orbiting papers and light that breathes on Luz's own
## `rest_sit` period. Runs while the tree is paused.

const IDLE_BREATH_PERIOD := 4.0
const SWING_PERIOD := 2.4
const SWING_STILL_TIME := 0.6
const SWING_RESUME_TIME := 1.0
const INTENSITY_DORMANT := 0.0
const INTENSITY_AWAKENED := 0.4
const INTENSITY_RITUAL := 1.0
const MOUNT_RAMP_TIME := 1.0
const FLICKER_SPEED := 9.0
## Light shaft base levels per altar state.
const SHAFT_DORMANT := 0.9
const SHAFT_AWAKENED := 1.3
const SHAFT_RESTING := 1.55
const SHAFT_RAMP_TIME := 0.8
## Rim light strength on the arch and desk edges, dormant to ritual.
const RIM_DORMANT := 0.35
const RIM_RITUAL := 1.0
## Ceiling for the nodes the FX layer animates every frame (mobile budget).
const FX_NODE_BUDGET := 60

@export_group("Pendulum")
@export_range(0.0, 0.3, 0.005) var swing_amplitude := 0.1

@export_group("Peak Bloom")
@export var bloom_scale_first := 1.5
@export var bloom_scale_repeat := 1.0
@export_range(0.0, 1.0, 0.05) var bloom_alpha_first := 0.7
@export_range(0.0, 1.0, 0.05) var bloom_alpha_repeat := 0.3
@export_range(0.1, 2.0, 0.05) var bloom_time := 0.5

@export_group("Breathing")
@export_range(0.0, 0.5, 0.01) var idle_glow_swing := 0.12
@export_range(0.0, 0.6, 0.01) var resting_glow_swing := 0.3

var intensity := 0.0
var swing := 1.0
var breath_weight := 0.0

var _desk: StillnessDesk
var _first := false
var _ritual_on := false
var _time := 0.0
var _swing_phase := 0.0
var _breath_clock := 0.0
var _breath := 0.5
var _tweens: Dictionary = {}
var _flicker := FastNoiseLite.new()
var _candle_glow_scale := Vector2.ONE
var _synced_once := false
var _candelabras: Array[GothicCandle] = []
var _rim: ShaderMaterial

@onready var _glow: Node2D = %Glow
@onready var _candle_glow: Node2D = %CandleGlow
@onready var _flame: Node2D = %Flame
@onready var _ink_glow: Node2D = %InkGlow
@onready var _pendulum: Node2D = %Pendulum
@onready var _papers: Node2D = %Papers
@onready var _halo: HaloSigil = %Halo
@onready var _shaft: AltarLightShaft = %LightShaft
@onready var _swarm: FireflySwarm = $Fireflies
@onready var _motes: AltarMotes = $DustMotes
@onready var _shaft_motes: AltarMotes = $ShaftMotes
@onready var _paper_orbit: PaperOrbit = $PaperOrbit
@onready var _drift: AltarDriftSheets = $DriftSheets
@onready var _pool: Sprite2D = $FloorPool
@onready var _bloom: Sprite2D = $PeakBloom


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_desk = get_parent() as StillnessDesk
	var seed_value := hash(String(_desk.checkpoint_id))
	_flicker.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_flicker.frequency = 1.0
	_flicker.seed = seed_value & 0x7fffffff
	_candle_glow_scale = _candle_glow.scale
	_swarm.setup(seed_value)
	_motes.setup(seed_value)
	_shaft_motes.setup(seed_value + 7)
	for candelabra: Node in [%CandelabraLeft, %CandelabraRight]:
		_candelabras.append(candelabra as GothicCandle)
	_rim = (%ArchFrame as Sprite2D).material as ShaderMaterial
	var sheets: Array[Node2D] = []
	for sheet: Node in _papers.get_children():
		sheets.append(sheet as Node2D)
	_paper_orbit.setup(sheets)
	_bloom.modulate.a = 0.0
	_desk.phase_changed.connect(_on_phase_changed)
	_desk.celebration_started.connect(_on_celebration_started)
	_desk.celebration_peak.connect(_on_celebration_peak)
	_desk.dismount_started.connect(_on_dismount_started)
	_desk.breath_cycle_started.connect(_on_breath_cycle_started)


func _process(delta: float) -> void:
	_time += delta
	_advance_breath(delta)
	_animate_pendulum(delta)
	_animate_lights()
	_swarm.brightness = 0.6 + 0.4 * intensity
	_swarm.step(delta, _time, _breath)
	_motes.resting_level = breath_weight
	_motes.step(delta)
	_shaft_motes.resting_level = breath_weight
	_shaft_motes.step(delta)
	_shaft.step(delta, _breath, breath_weight)
	_halo.step(delta, _breath, swing)
	_drift.step(_time)
	_paper_orbit.step(delta, _time)


## Nodes animated by this layer each frame: firefly glows and cores (extras
## included), both mote sets, paper sheets and drifting sheets, the peak bloom,
## the shaft, halo and floor pool and the candelabra glows. Must stay within
## FX_NODE_BUDGET.
func get_fx_node_count() -> int:
	var count := 1 + 3 + _candelabras.size() # bloom; shaft, halo, pool; candelabra glows
	for group: Node2D in [_swarm, _motes, _shaft_motes, _papers, _drift]:
		count += group.get_child_count()
	return count


func get_swing_angle() -> float:
	return _pendulum.rotation


func get_halo() -> HaloSigil:
	return _halo


func get_shaft() -> AltarLightShaft:
	return _shaft


# -- Ritual beats --------------------------------------------------------------

func _on_phase_changed(phase: StillnessDesk.Phase) -> void:
	match phase:
		StillnessDesk.Phase.DORMANT:
			_reset_to_idle(INTENSITY_DORMANT)
		StillnessDesk.Phase.AWAKENED:
			_reset_to_idle(INTENSITY_AWAKENED)
		StillnessDesk.Phase.MOUNT:
			_ease(&"intensity", INTENSITY_RITUAL, MOUNT_RAMP_TIME)
			_shaft.set_shaft_intensity(SHAFT_RESTING, MOUNT_RAMP_TIME)
		StillnessDesk.Phase.RESTING:
			_ease(&"breath_weight", 1.0, 1.0)
			_swarm.settle_into_rest()
			_paper_orbit.settle_into_rest()
			_halo.settle_into_rest()


func _on_celebration_started(first: bool) -> void:
	_first = first
	_ritual_on = true
	_ease(&"swing", 0.0, SWING_STILL_TIME, Tween.EASE_OUT)
	_halo.celebrate(first)
	_swarm.gather(first)


func _on_celebration_peak() -> void:
	_halo.peak()
	_paper_orbit.lift_off()
	_play_bloom()


func _on_dismount_started() -> void:
	if _ritual_on:
		_reset_to_idle(INTENSITY_AWAKENED)


func _on_breath_cycle_started() -> void:
	_breath_clock = 0.0


## Deterministic return to the idle look. Covers a normal dismount and an
## abort (respawn, freed player) at any phase, including MOUNT, without
## depending on whether the celebration ever started.
func _reset_to_idle(target_intensity: float) -> void:
	var awakened := target_intensity > INTENSITY_DORMANT
	# The first sync at scene start snaps, so a reloaded desk never fades in.
	var ramp := SHAFT_RAMP_TIME if _synced_once else 0.0
	_synced_once = true
	_shaft.set_shaft_intensity(SHAFT_AWAKENED if awakened else SHAFT_DORMANT, ramp)
	_halo.set_idle(awakened, ramp)
	_ritual_on = false
	_ease(&"swing", 1.0, SWING_RESUME_TIME, Tween.EASE_IN)
	_ease(&"breath_weight", 0.0, 0.8)
	_ease(&"intensity", target_intensity, 0.6)
	_swarm.disperse()
	_paper_orbit.glide_home()


func _play_bloom() -> void:
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	var end_scale := bloom_scale_first if _first else bloom_scale_repeat
	_bloom.scale = Vector2.ONE * end_scale * 0.35
	_bloom.modulate.a = bloom_alpha_first if _first else bloom_alpha_repeat
	tween.tween_property(_bloom, "scale", Vector2.ONE * end_scale, bloom_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_bloom, "modulate:a", 0.0, bloom_time).set_ease(Tween.EASE_IN)


# -- Per-frame animation -------------------------------------------------------

## `_breath` is 0..1; slow and free while waiting, locked to `breath_period`
## and the `rest_sit` loop while resting.
func _advance_breath(delta: float) -> void:
	_breath_clock = fposmod(_breath_clock + delta, maxf(_desk.breath_period, 0.1))
	var sit := 0.5 - 0.5 * cos(TAU * _breath_clock / maxf(_desk.breath_period, 0.1))
	var idle := 0.5 - 0.5 * cos(TAU * _time / IDLE_BREATH_PERIOD)
	_breath = lerpf(idle, sit, breath_weight)


func _animate_pendulum(delta: float) -> void:
	_swing_phase = fposmod(_swing_phase + delta * TAU / SWING_PERIOD, TAU)
	_pendulum.rotation = sin(_swing_phase) * swing_amplitude * swing


func _animate_lights() -> void:
	var flicker := _flicker.get_noise_1d(_time * FLICKER_SPEED)
	_flame.scale = Vector2(1.0, 1.0 + flicker * 0.08)
	_candle_glow.modulate.a = clampf(0.75 + flicker * 0.2 + intensity * 0.5, 0.0, 1.5)
	_candle_glow.scale = _candle_glow_scale * (1.0 + flicker * 0.06)
	_ink_glow.modulate.a = 0.5 + sin(_time * 1.5) * 0.18 + intensity * 0.5
	var swing_amount := lerpf(idle_glow_swing, resting_glow_swing, breath_weight)
	var lift := (_breath - 0.5) * swing_amount
	_glow.modulate.a = clampf(0.3 + intensity * 0.7 + lift, 0.0, 1.5)
	_glow.scale = Vector2.ONE * (0.92 + intensity * 0.25 + lift * 0.3)
	_pool.modulate.a = clampf(0.3 + intensity * 0.7 + lift, 0.0, 1.3)
	_rim.set_shader_parameter(&"strength", lerpf(RIM_DORMANT, RIM_RITUAL, intensity) * (1.0 + lift))
	for candelabra: GothicCandle in _candelabras:
		candelabra.energy = lerpf(0.8, 1.4, intensity)


func _ease(property: StringName, value: float, duration: float, easing := Tween.EASE_IN_OUT) -> void:
	AltarFxKit.ease_property(self, _tweens, self, property, value, duration, easing)
