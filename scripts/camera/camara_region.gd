extends Area2D

@export var limite_izquierdo: int
@export var limite_superior: int
@export var limite_derecho: int
@export var limite_inferior: int


# Called when the node enters the scene tree for the first time.
func _ready():
	body_entered.connect(_cuando_entra)

func _cuando_entra(body):
	if body.is_in_group("player"):

		var camara = get_tree().get_first_node_in_group("player_camera")

		if camara:
			camara.cambiar_region(
				limite_izquierdo,
				limite_superior,
				limite_derecho,
				limite_inferior
			)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
