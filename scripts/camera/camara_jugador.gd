extends Camera2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_to_group(&"player_camera")
	pass # Replace with function body.


func cambiar_region(
	izquierda: int,
	arriba: int,
	derecha: int,
	abajo: int
) -> void:
	limit_left=izquierda
	limit_right=derecha
	limit_bottom=abajo
	limit_top=arriba
	
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
