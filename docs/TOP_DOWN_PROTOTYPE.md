# Prototipo top-down

Esta rama reemplaza el prototipo de plataformas lateral por un juego 2D visto
desde arriba, pensado primero para mobile.

## Dirección jugable

- Tres habitaciones fijas conectadas por puertas cardinales.
- Cámara por habitaciones con transición corta y suave.
- Movimiento analógico con aceleración, frenado y cambio de dirección rápidos.
- Joystick virtual fijo en la esquina inferior derecha.
- Teclado de desarrollo: WASD o flechas.
- Tres destellos coleccionables para probar exploración y feedback.

## Arte

El mundo, los obstáculos, las puertas, los pickups y la interfaz se construyen
con geometría y colores planos en Godot. No hay texturas de escenario.

El único asset visual de juego es:

- `assets/player/top_down_hero_sheet.png`: sprite-sheet original de 4 × 4,
  generado para este prototipo. Filas: abajo, izquierda, derecha, arriba.

La ilustración se generó con la herramienta integrada de generación de imágenes
de Codex usando un prompt de personaje original y fondo transparente. No está
basada en personajes ni arte de otros juegos.

## Exportar a iOS

Después de exportar el preset `iOS` desde Godot, ejecutar:

```sh
ruby tools/ios/prepare_xcode.rb
```

El paso agrega automáticamente el stub de compatibilidad que necesita Godot
4.7.2 al compilar con Xcode 16.2 y el SDK de iOS 18.2.
