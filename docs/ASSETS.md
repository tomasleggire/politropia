# Politropia — guía de assets finales

Specs para generar en **Pixel Lab** (y audio) de forma que entren al repo **sin retrabajo**.  
Norte: jugabilidad Jump King + metáfora de dislexia (claridad visual, no lección).

---

## 1. Canvas del juego (no negociable)

| Constante | Valor |
|-----------|--------|
| Viewport / habitación | **720 × 1280** (portrait) |
| Paredes típicas | **56 px** de ancho |
| Plataformas típicas | **24 px** de alto (a veces 28) |
| Piso inferior | **40 px** de alto |
| Tile visual en código | `TILE_PX = 28` ([`level_geometry.gd`](scripts/world/level_geometry.gd)) |

Todo asset debe pensarse en **píxeles enteros**, filtro **Nearest** (sin blur).

---

## 2. Paleta base (usar siempre la misma)

Copiá estos hex a Pixel Lab / Aseprite como **palette fija**.  
Si generás con IA, pegá: *“restricted to this exact palette, no extra colors”*.

### Mundo — Sala 1 “Umbral” (cálida)
| Uso | Hex | RGB approx |
|-----|-----|------------|
| Fondo arriba | `#9E7A5C` | 158, 122, 92 |
| Fondo abajo | `#6B4D3D` | 107, 77, 61 |
| Silueta lejana | `#402E24` | 64, 46, 36 |
| Plataforma / dirt | `#66854D` | 102, 133, 77 |
| Piso | `#475738` | 71, 87, 56 |
| Pared / stone | `#54473D` | 84, 71, 61 |
| Marcas (glyphs) | `#F2D19E` | 242, 209, 158 |

### Mundo — Sala 2 “Se aclara” (fría)
| Uso | Hex |
|-----|-----|
| Fondo arriba | `#575C7A` |
| Fondo abajo | `#383D57` |
| Acento lejano | `#292447` |
| Marcas resueltas | `#D9E6FF` |
| Fragmento / sello | `#FFEB73` |

### Personaje / UI
| Uso | Hex |
|-----|-----|
| Contorno fuerte | `#1A1410` |
| Piel / tela clara | `#E8D4B8` |
| Acento salto UI | `#F2C738` |
| Texto narrativo | `#FFFFFF` + outline negro |

**Máximo ~16–32 colores totales** en el juego. Si Pixel Lab inventa colores, reducí en Aseprite (`Indexed` / same palette).

---

## 3. Tamaños por tipo de asset

### Personaje (prioridad)
| Frame | Tamaño canvas | Notas |
|-------|---------------|--------|
| idle, walk, charge, jump, fall, land | **64 × 96** (recomendado final) | O mantener **80 × 110** si ya hay pipeline; **no mezclar** |
| Transparent background | sí | PNG |
| Pivot | pies al centro-abajo del canvas | |

Animaciones mínimas (nombres exactos de archivo abajo):
- `idle` (1–2 frames)
- `walk` (2–4 frames)
- `charge` (1–2)
- `jump` (1)
- `fall` (1)
- `land` (1–2)

En Pixel Lab: generá **un** personaje con referencia de estilo, después animá walk/jump desde ese mismo base. Side-view, mirando a la **derecha** (el juego hace `flip_h`).

### Tiles / texturas (tileables)
| Asset | Tamaño | Repeat |
|-------|--------|--------|
| `tex_dirt` (plataformas) | **64 × 64** | sí, seamless |
| `tex_stone` (paredes) | **64 × 64** | sí; patrón **vertical** legible en franjas de 56 px |
| `tex_floor` (opcional) | **64 × 64** | sí |

En Pixel Lab usá **tileset sidescroller** / texture seamless. Probá mentalmente: una pared de 56×200 debe mostrar **varias** juntas de ladrillo/tabla.

### Props / decor
| Asset | Tamaño guía |
|-------|-------------|
| Fragmento / hook item | **32 × 32** o **48 × 48** |
| Marca / glyph (opcional sprite) | **32 × 48** |
| Roca, raíz, grieta | **32–96** de ancho |
| Silueta fondo (triángulo/roca) | **64–128** ancho |

Fondo transparente. Sin sombra baked gigante (el juego ya tiene atmósfera).

### Fondos de habitación (cómo armarlos)
**No** generes un JPG 720×1280 único como única solución (cuesta iterar y se ve genérico).

Capas (de atrás hacia adelante), todas 720 de ancho o tileables:

| Capa | Alto útil | Archivo ejemplo |
|------|-----------|-----------------|
| `bg_sky` / gradiente | 720×1280 o bandas | color sólido en Godot OK |
| `bg_far` siluetas | ~720×400 strip | `room01_far.png` |
| `bg_mid` | opcional | `room01_mid.png` |
| Solids (colisión) | tiles | dirt/stone |

En Godot: `z_index` −20 / −18 / −10 como ahora.

Si Pixel Lab da “scene” chica (≤400 px): generá **por franjas**, escalá ×2 o ×3 con nearest, y recortá.

---

## 4. Carpetas y naming (obligatorio)

```
assets/
  player/
    hero/                 # reemplazo final del adventurer
      idle.png
      walk_1.png
      walk_2.png          # walk_3… si hay más
      charge.png
      jump.png
      fall.png
      land.png
      ATTRIBUTION.txt
  world/
    tiles/
      tex_dirt.png
      tex_stone.png
      tex_floor.png       # opcional
    rooms/
      room01_far.png      # umbral
      room02_far.png      # se aclara
    props/
      fragment.png
      mark_twisted.png    # opcional
      mark_aligned.png
    ATTRIBUTION.txt
  audio/
    sfx_*.wav
    amb_room01.wav
    amb_room02.wav
    ATTRIBUTION.txt
  ui/                     # futuro
    jump_btn.png          # opcional; hoy es StyleBox
```

### Reglas de nombre
- `snake_case`, solo `a-z 0-9 _`
- Prefijo por sala: `room01_`, `room02_`
- Animaciones: `walk_1`, `walk_2` (no `Walk01`)
- Nada de `final_v3_NEW.png`

### Import Godot (al meter PNG)
- Filter: **Nearest**
- Repeat: **Enabled** en tiles (`tex_*`)
- Compress: Lossless / VRAM uncompressed si se ve mal en mobile
- Sin mipmaps en pixel art

---

## 5. Prompts base Pixel Lab (copiar/adaptar)

**Personaje**
> Side-view pixel art platformer hero, facing right, simple silhouette readable at small size, Jump King vibe, limited warm earth palette [#E8D4B8 #54473D #1A1410 #66854D], clean outline, transparent background, 64x96, no text, no UI

**Tile dirt**
> Seamless 64x64 pixel art dirt/grass platform tile, top edge slightly grassy, earth tones [#66854D #475738 #54473D], sidescroller, no characters, tileable

**Tile stone wall**
> Seamless 64x64 pixel art stone brick wall texture, vertical mortar lines readable when cropped to 56px width, colors [#54473D #402E24 #6B4D3D], tileable, no snow, no trees

**Fragmento**
> Small glowing diamond relic fragment, pixel art, 32x32, gold [#FFEB73] with dark outline, transparent background, simple, readable

**Silueta far (sala 1)**
> Distant rocky silhouettes strip for vertical tower background, warm brown [#402E24], flat shapes, 720x320, no characters, sparse, Jump King mood

Siempre agregá: *same palette, no anti-alias soft blur, crunchy pixels*.

---

## 6. Audio — specs finales

| Tipo | Formato | Sample rate | Loop | Loudness |
|------|---------|-------------|------|----------|
| SFX one-shot | WAV mono | **22050** o 44100 | no | pico ~−3 dB |
| Ambiente por sala | WAV mono/stereo | 22050 | **sí**, sin click | pico ~−18 a −14 dB |

### Naming audio
| Archivo | Uso |
|---------|-----|
| `sfx_jump.wav` | lanzamiento |
| `sfx_land.wav` | aterrizaje suave |
| `sfx_fall.wav` | knockdown |
| `sfx_wall.wav` | rebote |
| `sfx_foot.wav` | paso |
| `sfx_charge.wav` | empieza carga |
| `sfx_pickup.wav` | fragmento |
| `sfx_mark.wav` | marca |
| `sfx_room_enter.wav` | cambia sala |
| `amb_room01.wav` | umbral |
| `amb_room02.wav` | se aclara |

Herramientas: **jsfxr / ChipTone** (SFX), **BeepBox / Bosca Ceoil** (ambience).  
Exportá WAV; si sale MP3, convertí antes de meter al repo.

Duración ambiente: **4–8 s** loopables. Sin viento agresivo ni ruido blanco alto.

---

## 7. Checklist antes de pegar al repo

- [ ] Misma paleta (sin neones nuevos)
- [ ] Tamaño de la tabla de la sección 3
- [ ] Fondo transparente donde corresponde
- [ ] Nombre `snake_case` en la carpeta correcta
- [ ] Tile: se ve bien repetido (probá 3×3 en Aseprite)
- [ ] Personaje: pies abajo, mira a la derecha
- [ ] Sin texto dentro del PNG (la narrativa va en UI del juego)
- [ ] ATTRIBUTION.txt actualizado (Pixel Lab + licencia del plan)

---

## 8. Orden de producción sugerido

1. Paleta + `tex_dirt` + `tex_stone`  
2. `fragment` + 1 prop de decor por sala  
3. `room01_far` / `room02_far`  
4. Hero frames (idle → walk → jump/fall/charge/land)  
5. Reemplazar placeholders en escenas/scripts  
6. Audio `amb_room01/02` + SFX clave  

Cuando tengas el primer pack (tiles + fragment), lo integramos en una pasada al celu.
