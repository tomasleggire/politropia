class_name SafeArea
extends RefCounted

## Convierte la zona insegura del dispositivo (notch, isla dinámica, indicador
## de inicio) a unidades del viewport lógico actual, para insetear UI anclada
## a los bordes de la pantalla. Usa el tamaño real que reporta el viewport en
## vez de recalcularlo, así funciona sea cual sea el modo de estiramiento.


static func top_inset(viewport: Viewport) -> float:
	return _edge_inset(viewport, true)


static func bottom_inset(viewport: Viewport) -> float:
	return _edge_inset(viewport, false)


static func _edge_inset(viewport: Viewport, top: bool) -> float:
	var window_size := DisplayServer.window_get_size()
	var visible_size := viewport.get_visible_rect().size
	if window_size.y <= 0 or visible_size.y <= 0.0:
		return 0.0
	var scale := float(window_size.y) / visible_size.y
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var unsafe := float(usable.position.y) if top else float(window_size.y) - float(usable.position.y + usable.size.y)
	return maxf(0.0, unsafe) / scale
