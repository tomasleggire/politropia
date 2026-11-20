class_name DialogueColor

# 1. Color de texto oscuro universal (reemplaza al negro puro para evitar deslumbramiento)
const TEXTO_OSCURO = "#241044"

# 2. Fondos pastel universales (British Dyslexia Association)
const CREMA    = "#FFF2D6" # Off-white / Hueso
const NARANJA  = "#FFD8B5" # Melocotón suave
const AZUL     = "#BEE3F8" # Aguamarina / Azul pastel
const AMARILLO = "#FEFCBF" # Amarillo pálido

# 3. Función auxiliar para envolver palabras en pastillas navegables
static func tag(
	palabra: String,
	fondo: String = CREMA,
	texto: String = TEXTO_OSCURO
) -> String:
	return "[bgcolor=" + fondo + "][color=" + texto + "]" + palabra + "[/color][/bgcolor]"

static func color_dialogue(lines: Array[String]) -> Array[String]:
	var colors = [CREMA, NARANJA, AZUL, AMARILLO]
	var result: Array[String] = []
	var previous_color = null

	var regex := RegEx.new()
	# Match BBCode tags, whitespace, or regular words.
	regex.compile("\\[[^\\]]+\\]|\\s+|[^\\s\\[]+|\\[")

	for line in lines:
		var colored_line := ""

		for match_result in regex.search_all(line):
			var part := match_result.get_string()

			# Preserve BBCode tags.
			if part.begins_with("[") and part.ends_with("]"):
				colored_line += part
				continue

			# Preserve whitespace.
			if part.strip_edges().is_empty():
				colored_line += part
				continue

			var available_colors = colors.duplicate()

			if previous_color != null:
				available_colors.erase(previous_color)

			var selected_color = available_colors.pick_random()

			colored_line += tag(part, selected_color) + " "
			previous_color = selected_color

		result.append(colored_line)

	return result

static func color_text(text: String) -> String:
	return color_dialogue([text])[0]
