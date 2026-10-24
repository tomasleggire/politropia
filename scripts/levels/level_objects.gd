extends Node2D

@onready var player = $Player2
@onready var cofre = $Cofre

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	player.hiperfocus_activated.connect(cofre.show)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
