extends SceneTree
## Los textos medianos y largos del juego usan el formato pastel compartido de
## accesibilidad de DialogueColor: una pastilla por palabra, sin repetir el
## color anterior. Run: godot --headless --path . --script res://tests/dyslexia_text_test.gd

const SIGN_SCENE := preload("res://scenes/world/tutorial_sign.tscn")
const ZONE_1 := preload("res://scenes/levels/library/zone_1.tscn")
const GALLERY_SCENE := preload("res://scenes/ui/collectibles_gallery.tscn")
const POPUP_SCENE := preload("res://scenes/ui/ability_unlock_popup.tscn")
const PLAIN := "Hola mundo que sigue.\nOtra línea."
const PASTEL := ["#FFF2D6", "#FFD8B5", "#BEE3F8", "#FEFCBF"]
const DARK := "#241044"

var checks := 0
var failed: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	_case_helper()
	await _case_tutorial_sign()
	await _case_gallery()
	_case_ability_popup()
	paused = false
	var verdict := "PASS %d/%d" % [checks, checks] if failed.is_empty() else "FAIL %d/%d: %s" % [failed.size(), checks, ", ".join(failed)]
	print(verdict)
	quit(0 if failed.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed.append(label)


## Valida la paleta compartida sin asumir un orden de colores: la función de
## DialogueColor elige al azar entre los cuatro pasteles, excluyendo el anterior.
func check_pastel(text: String, label: String) -> void:
	var regex := RegEx.new()
	regex.compile("\\[bgcolor=(#[0-9A-Fa-f]{6})\\]")
	var matches := regex.search_all(text)
	check(not matches.is_empty(), "%s aplica pastillas" % label)
	var colors: Array[String] = []
	for match_result in matches:
		var color := match_result.get_string(1).to_upper()
		colors.append(color)
		check(PASTEL.has(color), "%s usa solo pasteles compartidos (%s)" % [label, color])
	var repeats := 0
	for i in range(1, colors.size()):
		if colors[i] == colors[i - 1]:
			repeats += 1
	check(repeats == 0, "%s no repite el color anterior" % label)
	check(text.count("[bgcolor=") == text.count("[/bgcolor]"), "%s cierra bgcolor" % label)
	check(text.count("[color=" + DARK + "]") == text.count("[/color]"), "%s cierra color" % label)


## Compara palabras, puntuación y saltos de línea ignorando los espacios extra
## que añade color_text al envolver cada palabra.
func normalized(text: String) -> String:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = text
	var plain := label.get_parsed_text()
	label.free()
	var lines := plain.split("\n", true)
	for i in lines.size():
		lines[i] = lines[i].strip_edges()
	return "\n".join(lines)


func _case_helper() -> void:
	check(DialogueColor.has_method(&"color_text"), "DialogueColor.color_text existe")
	check(DialogueColor.has_method(&"color_dialogue"), "DialogueColor.color_dialogue existe")
	var formatted: String = DialogueColor.color_text(PLAIN)
	check_pastel(formatted, "DialogueColor.color_text")
	check(normalized(formatted) == normalized(PLAIN), "color_text conserva el texto plano y los saltos de línea")

	var tagged := DialogueColor.color_text("[center]Hola[/center]")
	check(tagged.contains("[center]") and tagged.contains("[/center]"), "color_text conserva las etiquetas BBCode")

	var lines: Array[String] = ["Una línea.", "Otra línea."]
	var colored: Array[String] = DialogueColor.color_dialogue(lines)
	check(colored.size() == lines.size(), "color_dialogue conserva una salida por línea")
	check_pastel("\n".join(colored), "DialogueColor.color_dialogue")
	check(normalized("\n".join(colored)) == normalized("\n".join(lines)), "color_dialogue conserva el contenido por línea")


func _case_tutorial_sign() -> void:
	var sign := SIGN_SCENE.instantiate() as TutorialSign
	sign.text = "Mantené el dedo sobre la mitad izquierda."
	root.add_child(sign)
	await process_frame
	var body := sign.get_node("PanelLayer/Root/Panel/Margin/Box/Body") as RichTextLabel
	check_pastel(body.text, "cartel del tutorial")
	check(normalized(body.text) == "Mantené el dedo sobre la mitad izquierda.", "el cartel conserva su texto original")
	check(body.get_theme_constant("text_highlight_h_padding") == 1, "el cartel usa el padding horizontal de main")
	check(body.get_theme_constant("text_highlight_v_padding") == 3, "el cartel usa el padding vertical de main")
	sign.free()

	var state := ZONE_1.get_state()
	var found := 0
	for i in state.get_node_count():
		var instance := state.get_node_instance(i)
		if instance == null or not instance.resource_path.ends_with("tutorial_sign.tscn"):
			continue
		found += 1
		var plain := ""
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"text":
				plain = String(state.get_node_property_value(i, j))
		var real_sign := SIGN_SCENE.instantiate() as TutorialSign
		real_sign.text = plain
		root.add_child(real_sign)
		await process_frame
		var real_body := real_sign.get_node("PanelLayer/Root/Panel/Margin/Box/Body") as RichTextLabel
		check_pastel(real_body.text, "cartel real %s" % state.get_node_name(i))
		check(normalized(real_body.text) == normalized(plain), "%s conserva su texto original" % state.get_node_name(i))
		real_sign.free()
	check(found == 5, "la Zona 1 tiene cinco carteles (%d)" % found)


func _case_gallery() -> void:
	var manager := root.get_node_or_null("Collectibles")
	check(manager != null, "Collectibles autoload existe")
	if manager == null:
		return
	manager.call("clear")
	var holder := Control.new()
	root.add_child(holder)
	var gallery := GALLERY_SCENE.instantiate()
	holder.add_child(gallery)
	await process_frame
	await process_frame
	var detail := gallery.get_node("%DetailText") as RichTextLabel
	check(detail.bbcode_enabled, "el detalle del coleccionable habilita BBCode")
	check_pastel(String(detail.text), "texto bloqueado de la galería")
	var definitions: Array = manager.call("get_all_definitions")
	check(definitions.size() == 6, "el catálogo tiene seis coleccionables")
	for definition: CollectibleDefinition in definitions:
		check(bool(manager.call("try_collect", definition.id)), "se desbloquea %s" % definition.id)
	gallery.call("refresh")
	await process_frame
	for i in definitions.size():
		var definition: CollectibleDefinition = definitions[i]
		gallery.call("select_item", i)
		await process_frame
		check_pastel(String(detail.text), "texto del coleccionable %d" % i)
		check(normalized(String(gallery.call("get_selected_body"))) == normalized(definition.content), "%s conserva su contenido y sus párrafos" % definition.id)
	check(detail.get_theme_constant("text_highlight_h_padding") == 4, "la galería usa el padding horizontal de las pastillas")
	holder.free()
	manager.call("clear")


func _case_ability_popup() -> void:
	var popup := POPUP_SCENE.instantiate()
	root.add_child(popup)
	popup.call("show_ability", "Focus", "Luz aprendió a concentrar su energía para recuperar salud.", null)
	await process_frame
	var description := popup.get_node("Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/Description") as RichTextLabel
	check_pastel(String(description.text), "descripción de habilidad")
	check(normalized(String(description.text)) == "Luz aprendió a concentrar su energía para recuperar salud.", "la descripción conserva su texto")
	check(description.get_theme_constant("text_highlight_h_padding") == 4, "la descripción usa el padding horizontal de las pastillas")
	popup.call("close_popup")
	popup.free()
