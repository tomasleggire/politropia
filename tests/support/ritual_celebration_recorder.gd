extends RefCounted
## Samples every frame from a celebration's start until 0.6s into RESTING and
## records when each beat first showed (seconds on the game clock since the
## celebration started), so their order can be asserted.

const Harness := preload("res://tests/support/ritual_harness.gd")
const REST_TAIL := 0.6
const GIVE_UP := 8.0

var vig_t := -1.0
var fill_t := -1.0
var wave_t := -1.0
var spark_t := -1.0
var peak_t := -1.0
var monotonic := true
var max_fill_pre := 0.0
var flare_pre := 0.0
var flare_post := 0.0
var wave_pre := false
var sparks_pre := 0
var max_sparks := 0
var max_swell := 0.0
var max_zoom := 1.0

var _h: Harness
var _halo: HaloSigil
var _shaft: AltarLightShaft
var _vig: AltarVignette
var _wave: AltarShockwave
var _sparks: AltarSparks
var _base := 0.0
var _peaks_before := 0
var _last_fill := 0.0
var _rest_clock := -1.0


func _init(harness: Harness) -> void:
	_h = harness
	_halo = _h.fx.get_halo()
	_shaft = _h.fx.get_shaft()
	_vig = _h.fx.get_vignette()
	_wave = _h.fx.get_shockwave()
	_sparks = _h.fx.get_sparks()


func run() -> void:
	_h.open_window()
	_peaks_before = _h.count_events("peak")
	_base = _h.last_event("start")["t"]
	var t := 0.0
	while t <= GIVE_UP and not _rested_long_enough():
		await _h.tree.process_frame
		t = _h.clock - _base
		_sample(t)


func _rested_long_enough() -> bool:
	return _rest_clock >= 0.0 and _h.clock - _rest_clock > REST_TAIL


func _sample(t: float) -> void:
	var peaked := _h.count_events("peak") > _peaks_before
	if peaked and peak_t < 0.0:
		peak_t = _h.last_event("peak")["t"] - _base
	_note_first_times(t)
	if peaked:
		flare_post = maxf(flare_post, _halo.flare)
	else:
		_note_pre_peak()
	_note_extremes()
	if _h.desk.get_phase() == Harness.PHASE_RESTING and _rest_clock < 0.0:
		_rest_clock = _h.clock


func _note_first_times(t: float) -> void:
	if _vig.level > 0.05 and vig_t < 0.0:
		vig_t = t
	if _halo.fill > 0.02 and fill_t < 0.0:
		fill_t = t
	if _wave.is_active() and wave_t < 0.0:
		wave_t = t
	if _sparks.get_live_count() > 0 and spark_t < 0.0:
		spark_t = t


func _note_pre_peak() -> void:
	if _halo.fill < _last_fill - 0.0001:
		monotonic = false
	_last_fill = _halo.fill
	max_fill_pre = maxf(max_fill_pre, _halo.fill)
	flare_pre = maxf(flare_pre, _halo.flare)
	if _wave.is_active():
		wave_pre = true
	sparks_pre = maxi(sparks_pre, _sparks.get_live_count())


func _note_extremes() -> void:
	max_sparks = maxi(max_sparks, _sparks.get_live_count())
	max_swell = maxf(max_swell, _shaft.swell)
	max_zoom = maxf(max_zoom, _h.cam.get_zoom_ratio())
