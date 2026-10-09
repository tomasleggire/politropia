@tool
class_name BookFlyer
extends Flyer

## Book-shaped Vengefly variant. It keeps the existing Flyer behaviour and
## builds its short flight loop from the first row of the supplied atlas.

const SHEET := preload("res://assets/art/greece/enemies/book_vengefly_sheet.png")
const ATLAS_COLUMNS := 10.0
const ATLAS_ROWS := 6.0
const FLIGHT_FRAMES := 8


func _ready() -> void:
	super._ready()
	var sprite := $Visual/AnimatedSprite2D as AnimatedSprite2D
	sprite.sprite_frames = _make_flight_frames()
	sprite.animation = &"fly"
	sprite.play()


func _make_flight_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"fly")
	frames.set_animation_speed(&"fly", 9.0)
	frames.set_animation_loop(&"fly", true)
	var frame_size := Vector2(SHEET.get_width() / ATLAS_COLUMNS, SHEET.get_height() / ATLAS_ROWS)
	for column in FLIGHT_FRAMES:
		var atlas := AtlasTexture.new()
		atlas.atlas = SHEET
		atlas.region = Rect2(Vector2(float(column) * frame_size.x, 0.0), frame_size)
		frames.add_frame(&"fly", atlas)
	return frames
