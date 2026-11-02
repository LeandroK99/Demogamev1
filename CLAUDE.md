# CLAUDE.md — Hull-Down (demo táctica en Godot)

Demo de 4 horas: escaramuza WeGo de 4 vs 4 tanques en terreno 3D procedural, donde la IA busca defilade (hull-down) y avanza por rutas cubiertas. El plan completo, con fases y criterios de aceptación, está en `docs/PLAN.md`. **Leelo antes de cada fase.**

## Stack

- Godot 4.4 o superior (estable), **GDScript con tipado estático** (`var x: int`, `func f(a: Vector2i) -> bool`).
- Sin plugins ni assets externos. Sin C#.
- Ejecutable de Godot disponible como `godot` en el PATH (en Windows, la versión `_console.exe` renombrada o con alias).

## Arquitectura (obligatoria)

```
res://
  sim/        # lógica pura: extends RefCounted, SIN Nodes, SIN escenas, SIN Input
  game/       # presentación: Nodes, vistas, cámara, input, HUD, overlays
  tests/      # tests headless de sim/
  main.tscn   # escena mínima: un Node3D con game/main.gd
docs/PLAN.md
```

- `sim/` no conoce a `game/`. `game/` lee el estado de `sim/` y le envía órdenes.
- La simulación avanza en **ticks fijos de 0,1 s**. Toda aleatoriedad pasa por un `RandomNumberGenerator` con semilla, guardado en `SimWorld`. Misma semilla + mismas órdenes = mismo resultado.
- Las escenas `.tscn` se mantienen mínimas. **Todo se construye por código** desde `game/main.gd`. No edites `.tscn` salvo `main.tscn`.

## Comandos

```bash
# Solo la primera vez en un clon limpio (registra los class_name en .godot/)
godot --headless --path . --import

# Tests de la simulación (deben terminar con exit code 0)
godot --headless --path . --script res://tests/run_tests.gd

# Smoke test: arranca el juego ~5 s sin ventana y muestra errores de script
godot --headless --path . --quit-after 300
```

Después de cada cambio: corré los tests y el smoke test. Si hay errores o warnings de parseo, corregilos antes de seguir.

## Forma de trabajo

1. Una fase de `docs/PLAN.md` por vez. No adelantes fases.
2. Al terminar una fase: tests en verde, smoke test limpio, después **commit**: `git commit -m "fase N: <resumen>"`.
3. Si una fase se pasa de su tiempo, aplicá los recortes que lista el PLAN para esa fase. No agregues alcance.
4. Al final de cada fase, decí en 3–5 líneas qué tengo que mirar a mano en el juego (por ejemplo: "apretá 1 y verificá que la contrapendiente se vea verde").
5. Constantes ajustables (pesos, radios, probabilidades) en `sim/config.gd`, nunca hardcodeadas en la lógica.

## Convenciones

- Identificadores en inglés; comentarios y mensajes de HUD en español.
- Coordenadas: la grilla usa `Vector2i (x, y)`; el mundo 3D usa `Vector3 (x, altura, z)` con `z = y * CELL_SIZE`.
- Una clase por archivo, con `class_name`.
- Nada de `await` dentro de `sim/`.
