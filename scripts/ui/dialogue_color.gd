class_name DialogueColor

# 1. Color de texto oscuro universal (reemplaza al negro puro para evitar deslumbramiento)
const TEXTO_OSCURO = "#241044"

# 2. Fondos pastel universales (British Dyslexia Association)
const CREMA    = "#FFF2D6" # Off-white / Hueso
const NARANJA  = "#FFD8B5" # Melocotón suave
const AZUL     = "#BEE3F8" # Aguamarina / Azul pastel
const AMARILLO = "#FEFCBF" # Amarillo pálido

# 3. Función auxiliar para envolver palabras en pastillas navegables
static func tag(palabra: String, fondo: String = CREMA, texto: String = TEXTO_OSCURO) -> String:
	return "[bgcolor=" + fondo + "][color=" + texto + "]" + palabra + "[/color][/bgcolor] "
