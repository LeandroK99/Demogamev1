# PLAN — Hull-Down: demo jugable en 4 horas

## Objetivo

Validar una idea: **una IA que entiende el terreno se ve inteligente y hace interesante cada turno.**

Escaramuza WeGo de 4 tanques azules (jugador) contra 4 rojos (IA) en un terreno 3D procedural de 384 × 384 m. Cada turno: el juego se pausa, se calculan los mapas de exposición, das órdenes, apretás Espacio y se ejecutan 30 s simultáneos. La IA roja usa las mismas herramientas que vos: busca posiciones hull-down y avanza por rutas cubiertas.

## Criterios de éxito (al final de las 4 h)

- [ ] Con el overlay de exposición (tecla 1), los tanques rojos terminan detrás de las crestas, no en la cima ni en el llano.
- [ ] Un tanque que avanza por la ruta cubierta recibe menos disparos que uno que va en línea recta (probarlo 5 veces).
- [ ] La partida se puede ganar y perder, y perder se siente culpa tuya.
- [ ] Los tests pasan y existe una build ejecutable.

## Afuera del alcance

Infantería, edificios, CQB, sonido, menús, guardado, campaña, multijugador, modelos 3D (los tanques son cajas), balística real y penetración, rotación de torreta.

---

## Constantes iniciales (`sim/config.gd`)

| Constante | Valor | Uso |
|---|---|---|
| `GRID_SIZE` | 96 | celdas por lado |
| `CELL_SIZE` | 4.0 | metros por celda (mapa de 384 m) |
| `MAX_HEIGHT` | 28.0 | metros |
| `SEED` | 1337 | semilla del mapa y de la simulación |
| `TICK` | 0.1 | segundos por tick |
| `TURN_SECONDS` | 30.0 | duración de un turno (300 ticks) |
| `EYE_H` | 2.4 | altura del ojo y la óptica del tanque |
| `HULL_H` | 1.0 | altura del punto de casco (para "¿me ven el casco?") |
| `CENTER_H` | 1.6 | altura del centro de masa (para disparar) |
| `TANK_SPEED` | 6.0 | m/s en llano |
| `SLOPE_SPEED_PENALTY` | 0.5 | factor de velocidad en pendiente fuerte |
| `TANK_HP` | 3 | impactos para destruir |
| `RELOAD_SECONDS` | 7.0 | |
| `MAX_RANGE` | 350.0 | metros |
| `P_HIT_BASE` | 0.55 | |
| `HULLDOWN_HIT_FACTOR` | 0.35 | multiplicador si el casco del blanco no es visible |
| `MOVING_SHOOTER_FACTOR` | 0.4 | multiplicador si el que dispara se mueve |
| `EXPOSURE_WEIGHT_K` | 8.0 | peso de la exposición en el costo del A* |
| `HULLDOWN_RADIUS` | 15 | celdas de búsqueda de candidatos |
| `MAX_TURNS` | 12 | si se llega, gana el bando con más tanques vivos |

---

## Fase 0 — Setup (0:00–0:20)

**Lo hacés vos antes de lanzar a Claude Code:**

1. `git init hulldown && cd hulldown`, copiar `CLAUDE.md` y `docs/PLAN.md`.
2. Abrir Godot, crear un proyecto en esa carpeta con el renderer **Forward+** (o Mobile si tu GPU es débil), y cerrar Godot.
3. Verificar que `godot --version` funciona en la terminal.

**Le pedís a Claude Code:**

- `.gitignore` de Godot: ignorar `.godot/` y `export/` (los archivos `*.import` sí se versionan).
- Estructura `sim/`, `game/`, `tests/`.
- `sim/config.gd` con la tabla de constantes de arriba (como `const` en una clase `Config`).
- `tests/run_tests.gd`: `extends SceneTree`; descubre los archivos `tests/test_*.gd`, ejecuta todos los métodos `test_*`, imprime PASS/FAIL por test y termina con `quit(0)` o `quit(1)`. Helpers: `assert_true(cond, msg)`, `assert_eq(a, b, msg)`, `assert_lt(a, b, msg)`.
- `tests/test_smoke.gd` con un test trivial.
- `main.tscn` con un `Node3D` raíz y `game/main.gd` adjunto que imprime "Hull-Down OK".
- Configurar `main.tscn` como escena principal en `project.godot`.

**Aceptación:** tests en verde, el smoke test imprime "Hull-Down OK" sin errores. Commit `fase 0`.

---

## Fase 1 — Terreno + cámara (0:20–0:55)

### `sim/height_field.gd` (class_name `HeightField`)

- `heights: PackedFloat32Array` de `GRID_SIZE × GRID_SIZE`.
- `generate(seed: int)`: `FastNoiseLite` (Simplex, frecuencia ~0,02, 3 octavas), normalizado a 0..1, más **una cresta garantizada**: una loma sinusoidal que cruza el mapa en diagonal suave por el centro (altura de 0,5 a 0,7 en `MAX_HEIGHT`, ancho ~10 celdas), más 2–3 lomas menores. Así siempre existen contrapendientes para la demo. Multiplicar por `MAX_HEIGHT`.
- `height_at_cell(c: Vector2i) -> float`
- `height_at(p: Vector2) -> float`: interpolación bilineal en coordenadas de celda continuas.
- `slope_at(c: Vector2i) -> float`: diferencia máxima con los vecinos, en metros.
- `in_bounds(c: Vector2i) -> bool`
- `cell_to_world(c: Vector2i) -> Vector3` y `world_to_cell(p: Vector3) -> Vector2i`.

### `game/terrain_view.gd`

- `ArrayMesh` generado desde **el mismo** `HeightField`: un vértice por celda, normales calculadas y colores por vértice según la altura (verde oscuro abajo, ocre arriba).
- `MeshInstance3D` con un material que use los colores de vértice (`vertex_color_use_as_albedo = true`).
- `set_overlay_colors(colors: PackedColorArray)` y `clear_overlay()` para la fase 2: reemplaza o restaura los colores de vértice.
- `StaticBody3D` + `HeightMapShape3D` para que el mouse pueda hacer raycast al terreno (o, si es más simple, intersección rayo–heightfield hecha a mano en `game/`).

### `game/camera_rts.gd`

- Pivote con `Camera3D` a ~60° de inclinación. WASD/flechas mueven el pivote, la rueda hace zoom (40–300 m), el botón medio arrastrado rota. Límites del mapa.

### `game/main.gd`

- Crea `HeightField`, `TerrainView`, cámara y una `DirectionalLight3D` con sombras.

### Tests (`tests/test_height_field.gd`)

- Generar con la misma semilla dos veces → mismos `heights`.
- Altura mínima ≥ 0, máxima ≤ `MAX_HEIGHT`.
- La cresta central existe: la altura promedio de la franja central es mayor que la de los bordes.

**Aceptación:** el terreno se ve con lomas y una cresta clara; la cámara responde. **Mirá a mano:** que haya contrapendientes visibles. Commit `fase 1`.

**Si te pasás de tiempo:** sin sombras, sin `HeightMapShape3D` (raycast a mano contra un plano a altura media alcanza para esta demo).

---

## Fase 2 — Línea de visión + exposición (0:55–1:40)

### `sim/terrain_analysis.gd` (class_name `TerrainAnalysis`)

- `los(from_cell: Vector2i, from_h: float, to_cell: Vector2i, to_h: float) -> bool`
  - Punto A = (from, altura del terreno + from_h), punto B = (to, altura del terreno + to_h).
  - Muestrear la recta cada 0,5 celdas (excluyendo los extremos); en cada muestra, si `height_at(p) > altura de la recta - 0.05`, devolver false.
- `exposure_map(threats: Array[Vector2i]) -> PackedFloat32Array`
  - Para cada celda: fracción de amenazas que **ven el casco** (`los(threat, EYE_H, cell, HULL_H)`). 0 = cubierta; 1 = vista por todas.
  - Medir el tiempo con `Time.get_ticks_msec()` e imprimirlo. **Si pasa de 800 ms:** calcular solo dentro de un radio de 40 celdas alrededor de las unidades del bando que lo pide (el resto vale 1.0) o bajar la grilla a 64.
- `hulldown_candidates(origin: Vector2i, threats: Array[Vector2i], radius: int) -> Array[Dictionary]`
  - Para cada celda en el radio, transitable y con pendiente < 3 m:
    - `can_fire` = ve el centro de al menos una amenaza: `los(cell, EYE_H, threat, CENTER_H)`.
    - `hull_hidden` = ninguna amenaza le ve el casco: `!los(threat, EYE_H, cell, HULL_H)` para todas.
    - `score = 3.0 * float(hull_hidden) + 2.0 * float(can_fire) - dist(origin, cell) / 10.0`
  - Devolver ordenado por score descendente, con `{cell, score, can_fire, hull_hidden}`.

### `game/overlay.gd`

- Tecla **1**: alterna el heatmap de exposición del bando azul (verde = 0, amarillo = 0,5, rojo = 1) sobre el terreno, usando `set_overlay_colors`.
- Tecla **2**: alterna marcadores (pequeños cilindros) en los 10 mejores candidatos hull-down de la unidad seleccionada.
- Tecla **3**: alterna líneas de LOS (`ImmediateMesh`) desde la unidad seleccionada a cada enemigo conocido: verde si lo ve, rojo si no.

### Tests (`tests/test_terrain_analysis.gd`)

Usar `HeightField` sintéticos armados a mano (no el procedural):

- **Llano:** LOS verdadera entre dos celdas a 50 celdas de distancia.
- **Loma en el medio** (pared de 10 m): LOS falsa.
- **Contrapendiente:** loma de 6 m; el observador del otro lado ve la celda de la cresta pero no una celda 5 celdas detrás de ella.
- **Hull-down:** con una loma de 1,8 m entre la amenaza y el origen, existe al menos un candidato con `hull_hidden == true` y `can_fire == true`.
- **Exposición:** en el llano sin obstáculos, todas las celdas a menos de `MAX_RANGE` valen 1.0.

**Aceptación:** tests en verde; con el overlay se distinguen zonas cubiertas detrás de la cresta. **Mirá a mano:** que el verde caiga detrás de las lomas respecto de dónde están los rojos. Commit `fase 2`.

---

## Fase 3 — Unidades, selección y movimiento cubierto (1:40–2:20)

### `sim/unit.gd` (class_name `Unit`)

- `id: int`, `side: int` (0 azul, 1 rojo), `pos: Vector2` (en celdas, continua), `hp: int`, `reload_left: float`, `path: Array[Vector2i]`, `order: int` (enum: NONE, MOVE, HULLDOWN, HOLD), `moving: bool`, `alive: bool`.
- `cell() -> Vector2i`.

### `sim/pathfinder.gd` (class_name `Pathfinder`)

- Envuelve `AStarGrid2D` (`diagonal_mode = DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`).
- Celdas con pendiente > 4 m → sólidas.
- `set_exposure(exposure: PackedFloat32Array)`: `weight_scale = 1.0 + EXPOSURE_WEIGHT_K * exposure[cell] + slope_penalty`.
- `find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]`.

### `sim/sim_world.gd` (class_name `SimWorld`)

- Contiene `HeightField`, `TerrainAnalysis`, `Pathfinder`, `units`, `rng` (con semilla), `turn: int`, `tick_in_turn: int`.
- Despliegue inicial: azules en el borde sur, rojos en el norte, separados ~8 celdas entre sí.
- `order_move(unit_id, target_cell)`: calcula la ruta con la exposición del bando de la unidad y la guarda.
- `step()`: avanza un tick: mover cada unidad por su ruta a `TANK_SPEED` (penalizada por pendiente), convirtiendo metros a celdas.

### `game/unit_view.gd` + `game/input_controller.gd`

- Tanque = `BoxMesh` de 3,5 × 2,2 × 7 m (azul o rojo) más una caja chica arriba como torreta. Orientado hacia la dirección de movimiento.
- Clic izquierdo: seleccionar. Arrastrar con el izquierdo: selección por recuadro. Clic derecho: orden de mover (**solo en la fase PLAN**). Mostrar la ruta planificada como una línea.
- Anillo bajo la unidad seleccionada.

### Tests (`tests/test_pathfinder.gd`)

- En un mapa con una franja expuesta (exposición 1) y un desvío cubierto (exposición 0) de largo 1,5×, la ruta elegida pasa por el desvío.
- Con `EXPOSURE_WEIGHT_K = 0`, la ruta va recta.

**Aceptación:** podés seleccionar y mandar a mover tanques; la ruta esquiva crestas visibles para el enemigo. Commit `fase 3`.

**Si te pasás de tiempo:** sin selección por recuadro; sin orientación de la torreta.

---

## Fase 4 — Ciclo WeGo + combate + niebla (2:20–3:05)

### Ciclo de turno (`SimWorld` + `game/turn_controller.gd`)

- Estados: `PLAN` → (Espacio) → `EXECUTE` (300 ticks) → `PLAN` …
- Al entrar en `PLAN`: recalcular la exposición de cada bando según sus **amenazas conocidas** y actualizar el pathfinder; la IA roja da sus órdenes (fase 5).
- En `EXECUTE`: `SimWorld.step()` a 10 ticks por segundo de juego, con interpolación visual entre ticks. Velocidad ×1 / ×2 / ×4 con las teclas `+` y `-`.
- Las órdenes solo se aceptan en `PLAN`.

### Detección y niebla (versión liviana de detección relativa)

- Cada tick: un enemigo es **visible para un bando** si alguna unidad viva de ese bando lo ve (`los(eye, EYE_H, target, CENTER_H)`) a ≤ `MAX_RANGE`.
- Cada bando guarda `known_enemies: Dictionary` id → `{cell, last_seen_turn}`.
- Render: los enemigos visibles se ven normales; los conocidos pero no visibles, como un "fantasma" semitransparente en su última posición; los nunca vistos, ocultos.
- Las amenazas de la exposición son las posiciones conocidas (visibles + fantasmas del último turno).
- Para no cargar la CPU: calcular la detección cada 5 ticks, no cada tick.

### Combate

- Cada tick, para cada unidad viva con `reload_left <= 0`: elegir el enemigo visible más cercano dentro de `MAX_RANGE`.
- `p = P_HIT_BASE × factor_distancia × factor_casco × factor_movimiento`
  - `factor_distancia = clamp(1.0 - dist_m / MAX_RANGE, 0.2, 1.0)`
  - `factor_casco = HULLDOWN_HIT_FACTOR` si el que dispara NO ve el casco del blanco; si no, 1.0
  - `factor_movimiento = MOVING_SHOOTER_FACTOR` si el que dispara se está moviendo; si no, 1.0
- Tirada con `rng.randf()`. Si impacta, `hp -= 1`; con `hp <= 0` la unidad muere (la vista la oscurece y la deja como restos).
- Visual: línea trazadora de 0,15 s y un destello en el impacto.
- Registrar en la simulación los disparos recibidos por unidad (para el criterio de éxito 2).

### Victoria

- Un bando sin tanques vivos pierde. Si se llega a `MAX_TURNS`, gana el bando con más vivos (empate posible). Mostrarlo en el HUD.

### Tests (`tests/test_sim_world.gd`)

- **Determinismo:** dos `SimWorld` con la misma semilla y las mismas órdenes → misma posición y hp de cada unidad después de 300 ticks.
- Un tanque detrás de una pared de 10 m no es detectado.
- Con `P_HIT_BASE = 1` y factores en 1, un blanco visible pierde hp al recargarse el tirador.

**Aceptación:** se juega un turno completo y los tanques se disparan; el fog funciona. Commit `fase 4`.

**Si te pasás de tiempo:** sin fantasmas (solo visibles/ocultos), sin velocidades ×2/×4, sin destello.

---

## Fase 5 — IA hull-down + IA roja (3:05–3:40)

### Orden HULLDOWN (jugador)

- Tecla **H** en `PLAN` con unidades seleccionadas: para cada una, tomar el mejor candidato de `hulldown_candidates` contra las amenazas conocidas, evitando que dos unidades elijan la misma celda o celdas a menos de 3 de distancia. Ruta cubierta hasta ahí.
- Sin amenazas conocidas: avanzar 20 celdas hacia el centro del mapa por la ruta más cubierta y quedarse.

### `sim/ai_commander.gd` (IA roja; se ejecuta al entrar en `PLAN`)

- Por cada tanque rojo vivo:
  1. Si tiene amenazas conocidas y su celda actual NO es hull-down respecto de ellas → orden HULLDOWN.
  2. Si ya está en hull-down y ve a un enemigo → HOLD (se queda y dispara).
  3. Si no tiene amenazas conocidas → avanzar hacia la cresta central por la ruta más cubierta (objetivo: la celda de la cresta más cercana con un candidato hull-down mirando al sur).
  4. Si hp == 1 → retroceder a la celda de menor exposición dentro de un radio de 10.
- La IA usa **solo información conocida por su bando** (nada de trampas).

### Tests (`tests/test_ai.gd`)

- En un mapa sintético con una cresta entre los bandos y un azul conocido, la IA roja elige una celda con `hull_hidden == true`.
- Con amenaza conocida y hp == 1, la IA elige retroceder.

**Aceptación:** al jugar, los rojos se acomodan detrás de las crestas y te esperan. **Mirá a mano:** con el overlay 1 activado (exposición azul), los rojos están en zonas que los azules no cubren bien. Commit `fase 5`.

---

## Fase 6 — HUD, ajuste y build (3:40–4:00)

- **HUD** (`CanvasLayer` + `Label`s): turno N / `MAX_TURNS`, fase (PLANIFICAR / EJECUTANDO), tanques vivos por bando, datos de la unidad seleccionada (hp, recarga, orden), disparos recibidos por unidad, y la ayuda de teclas:
  `Clic izq: seleccionar · Clic der: mover · H: hull-down · Espacio: ejecutar turno · 1/2/3: overlays · +/-: velocidad · R: reiniciar`
- **R** reinicia la partida con la misma semilla; **Shift+R**, con una semilla nueva.
- Banner de victoria o derrota.
- **Export:** `export_presets.cfg` para tu plataforma (Windows Desktop o Linux) con salida en `export/`. Si faltan las export templates, avisá en lugar de inventar la configuración.
- README.md corto: qué es, cómo correr, controles, cómo correr los tests.

**Ajuste (lo hacés vos jugando 3–4 partidas):** si la IA es demasiado fuerte, bajá `HULLDOWN_HIT_FACTOR` a 0,5; si los tanques cruzan expuestos, subí `EXPOSURE_WEIGHT_K` a 12; si los combates terminan en 1 turno, bajá `P_HIT_BASE` a 0,4.

**Aceptación:** criterios de éxito arriba. Commit `fase 6` y `git tag v0.1-demo`.

---

## Si sobra tiempo (en este orden)

1. **Repetición del turno:** grabar las posiciones por tick y reproducir el último turno con la tecla `T`, con el overlay activable.
2. **Orden de "ruta recta"** (Shift + clic derecho) para comparar contra la cubierta y verificar el criterio de éxito 2.
3. **Comunicación con demora:** los contactos de una unidad recién llegan al resto del bando al turno siguiente.

---

## Fases 14–18 — Órdenes (lógica)

Salen de la evaluación del brief de órdenes e interfaz. Todo con tanques; la infantería se decide después de jugarlas. Las teclas son provisorias hasta el menú radial (fase 19).

- **14 — ROE.** `Unit.roe` (fuego libre, solo si le disparan, retener), `fire_arc_dir` y `max_engage_m`, filtradas en `_pick_target`. Duran hasta que se cambien. La IA en vigilancia no tira a más de `AI_AMBUSH_RANGE` salvo que la hayan atacado. Teclas Z y C.
- **15 — Ritmo y verbos.** `Unit.pace` (normal, rápido, cauto); cauto se detecta como quieto. `order_assault` (directo, rápido, no frena) y `order_withdraw` (reversa a la celda menos expuesta, frente a las amenazas). Teclas X, T, B.
- **16 — Condiciones.** Cada tramo (`waypoints[i]`) puede tener `gate` (tiempo del turno, contacto, señal, esperar a otra unidad) y `signal` que emite al llegar. La unidad espera quieta (`waiting`). Tecla K.
- **17 — Pelotón.** `Platoon` con dos secciones por bando; `order_platoon_move` reparte las secciones lado a lado y `order_platoon_bound` hace avance por saltos con señales. Doble clic y J.
- **18 — Vista previa de riesgo.** `route_risk`: duración, segundos expuestos, impactos esperados contra amenazas conocidas, peor cara del blindaje y nivel. La ruta expuesta se pinta en rojo.

Siguen (interfaz): mockups de los 7 estados, 19 menú radial, 20 HUD fijo con minimapa y símbolos OTAN, 21 contactos inciertos y dificultad.

---

## Fases 22–28 — Infantería y "La loma"

Plan completo en el doc "Hull-Down: plan de infantería". La demo de tanques queda igual (escenario `TANKS`); la infantería vive en el escenario `LOMA` (tecla L).

- **22 — Tipos de unidad.** `Unit.kind` y alturas por unidad (`eye_h`, `profile_h`, `center_h`); un `Pathfinder` y un mapa de exposición por tipo.
- **23 — Escuadra.** 9 hombres, 1,5 m/s, pendiente máxima 8 m, cuerpo a tierra a los 3 s quieta; detección 250 / 120 / 60 m. Hull-down = tomar posición.
- **24 — Armas.** Dos slots por unidad: cañón + coaxial, fusiles + antitanque (150 m, 2 cargas). Un impacto = un hombre.
- **25 — Cobertura.** `CoverMap` (bosque, muro, pozo). El bosque corta la LOS tras 2 celdas y frena al tanque; la cobertura baja impactos y detección contra infantería.
- **26 — Supresión y moral.** Supresión 0..100 por fuego recibido (50 suprimida, 85 inmovilizada; tanque abotonado). Moral; quebrada se retira sola. Orden SUPPRESS (zona) y condición "suprimida".
- **27 — La loma.** 3 escuadras + 1 tanque por bando, turnos de 45 s, rojo detrás de la cresta con bosque en la contrapendiente. Pelotón mixto: el tanque se queda atrás cubriendo. Objetivo en la cresta.
- **28 — IA de infantería.** Cobertura con vista, emboscada a 150 m, suprime la última posición conocida, repliega diezmadas. No contraataca.

## Fases 29–35 — Soldados individuales

Plan completo en el doc "Hull-Down: soldados individuales y microcobertura". Reemplaza el modelo de escuadra de las fases 23, 24 y 26: la escuadra (`Unit` de infantería) conserva la orden, la ruta, el pelotón y la moral; cada `Soldier` tiene posición en metros, postura, estado y supresión. La lógica de los soldados vive en `sim/infantry_sim.gd`, para no agrandar `sim_world.gd`.

- **29 — Microcobertura.** `MicroCover` a 1 m (roca 0,6 m, muro 1 m, arbusto 1,2 m que no protege, tronco, cráter) generada desde el `CoverMap` más rocas y cráteres sueltos. `TerrainAnalysis.los_m` en metros: mira la microcobertura solo a 15 m de cada extremo.
- **30 — Soldados y formaciones.** 9 soldados con rol; cuña, fila y línea a 3 m. El ancla sigue la ruta y espera a los que quedan a más de 6 m. Un impacto hiere (50 %) o mata; el herido se queda. `hp` = soldados en condiciones.
- **31 — Cobertura por soldado.** Al detenerse, cada uno puntúa las micro-celdas a 6 m de su lugar: protegido (obstáculo hacia la amenaza a menos de 2,5 m, o el terreno), con tiro, oculto, cerca; 2 m de separación. Agachado o cuerpo a tierra según el obstáculo.
- **32 — Visión por soldado.** Observadores por escuadra: el jefe y dos que rotan. LOS a la cabeza. Alcance según lo que hace cada uno. `visible_soldiers` por bando.
- **33 — Fuego por soldado.** Fusil (p 0,05), ráfaga de ametralladora y de coaxial (radio 3 m), antitanque. El fuego se reparte entre los 5 blancos más cercanos. Protegido: ×0,2.
- **34 — Supresión por soldado.** 8 por tiro de fusil, 15 por ráfaga; la mitad a 5 m; ×0,6 protegido. Clavado (85): no tira ni se mueve. La escuadra frena si más de la mitad está suprimida. Moral: bajas (+10 si cae el jefe) y drenaje por la parte suprimida.
- **35 — Vistas, HUD y rendimiento.** Un muñeco por soldado con su postura (de los enemigos, solo los que se ven); rocas, arbustos y cráteres; HUD con posturas, cubiertos, clavados y heridos; tecla N. Detección escalonada en la ejecución (cada escuadra enemiga cada 1 s). `tests/bench_loma.gd`: unos 2 ms por tick de promedio en la loma.


## Fases 36–47 — Autonomía de la infantería y sistema médico

Plan completo en el doc "Hull-Down: autonomía, sistema médico y 10 mecánicas de infantería". Cada escuadra tiene una cabeza (`SquadMind`, estado) y la lógica vive en `sim/mind_sim.gd` (`MindSim`, de `SimWorld` como `minds`). La orden del jugador se guarda al decidir por su cuenta y se retoma al volver a `FOLLOW`. El azar de la autonomía usa `SimWorld.mind_rng` (con semilla, aparte del de combate).

- **36 — Base.** Opciones puntuadas (seguir la orden, drill, reubicarse, emboscada, romper el contacto, saltos, flanqueo, rescate) con histéresis: la nueva tiene que superar a la actual por `MIND_SWITCH_MARGIN` y una decisión propia dura al menos 10 s. Autonomía por escuadra: estricta (solo la orden), normal (reacciona) y alta (maniobra); el jugador arranca en normal y la IA roja en alta. Radio (`SimWorld.radio_log`). Una orden nueva del jugador resetea la cabeza.
- **37 — Reflejos.** Al suelo 2 s si le tiran en marcha y al descubierto; cubierta inválida si le tiran desde donde no lo protege; asomar y tirar desde un punto cercano si su cobertura no tiene tiro; humo de mano si la escuadra lleva 15 s frenada por la supresión.
- **38 — Drill de contacto.** En marcha, si le tiran o ve a un enemigo nuevo a 200 m: alto, cobertura a 4 m, fuego; retoma con la supresión media bajo 25 durante 5 s. El asalto, la retirada y los saltos no frenan.
- **39 — Conocimiento.** Cada escuadra tiene sus contactos: lo que se ve a 150 m, exacto y al momento; el fogonazo de un tirador que no ve, con 10 % de error; lo demás llega por radio en 3 a 5 s. Se olvidan a los 60 s. La cobertura se elige contra lo que sabe la escuadra.
- **40 — Reubicarse, emboscar, romper el contacto.** Quieta bajo fuego con la mitad al descubierto: a una celda tapada a 20 m. Sin ser vista, con enemigos acercándose: retiene el fuego hasta 100 m. Diezmada, con la moral baja o frenada 20 s (solo alta): humo y repliegue.
- **41 — Equipos de fuego.** A (ametralladora, 2, 4, 6) y B (jefe, AT, 5, 7, 8). Con un contacto a 250 m, avance por saltos de 25 m: A queda de base de fuego y bate el contacto. Flanqueo (solo alta, solo la que avanza): si otra escuadra propia está tirando al contacto, va a 60 m de su costado.
- **42 — Mando.** Jefe veterano, regular o novato: piensa cada 0,5, 1 o 2 s y se equivoca ±0, 0,1 o 0,25 al puntuar. Si cae, la escuadra queda desorganizada 20 a 30 s y el segundo toma el mando un escalón peor.
- **43 — IA roja de pelotón.** En la loma: adelantada en la cresta, principal en la contrapendiente y reserva atrás. Durante la ejecución, cada 2 s: la adelantada apretada se repliega, la reserva refuerza a la que está en contacto y, si los azules del objetivo quedan débiles, contraataca.
- **44 — Interfaz y ajuste.** Radio en el HUD (abajo a la izquierda), lo que decide cada escuadra sobre su número, autonomía y jefe en el panel, tecla Y para la autonomía. `tests/harness_loma.gd`: IA contra IA en la loma por semillas.
- **45 — Sangrado.** Un herido sin atender se desangra en 90 a 240 s; mientras tanto le baja la moral a la escuadra. Estabilizado, deja de desangrarse.
- **46 — Médico.** El soldado 9 es el médico (en lugar de un fusilero): con la escuadra detenida va al herido que se desangra más rápido y lo estabiliza en 15 s. Sin médico, un compañero tarda 40 s. El que atiende no tira.
- **47 — Rescate y evacuación.** Bajo fuego, con un herido al descubierto (autonomía normal o alta): humo de mano entre el herido y la amenaza, el equipo A bate la amenaza y el médico (o un fusilero) lo arrastra a cubierto a 0,6 m/s; ahí lo atienden. Tecla P (en PLAN): cada herido sale hacia el borde propio con un camillero y a los 60 s dejan el campo; la escuadra recupera moral.


## Fases 48–72 — Campo abierto, edificios y CQB

Plan completo en el doc "Hull-Down: plan de las fases 48 a 72" (cuatro PR: A fuego 48–53, B pelotón 54–59, C edificios 60–65, D CQB 66–72). Las mecánicas salen del doc "Hull-Down: 30 mecánicas de infantería".

- **48 — Munición.** Tiros por fusilero (120), ráfagas de la ametralladora (150) y cintas extra del proveedor (150), que se las pasa si está a 6 m y le queda menos de la mitad. Fuego rápido (asalto, suprimir, ritmo rápido) acorta el tiempo entre tiros a ×0,6; con menos del 25 % dosifica (×1,5). Sin munición no tira; avisa por radio.
- **49 — Granadas.** Dos de mano por soldado (no la ametralladora), a 8–30 m contra un enemigo visible protegido de su fusil: radio 5 m que ignora rocas y muros, menos cuerpo a tierra; suprime al doble del radio. El soldado 5 es granadero: 8 granadas de fusil a 30–150 m. No se tira si un propio queda a 7 m de donde cae.
- **50 — Formación según terreno.** En marcha con la cuña elegida: se abre de a poco hasta ×2 en terreno limpio, se cierra en el bosque, cerca de él o en terreno quebrado, línea a 60 m del objetivo de un asalto y escalón hacia un contacto de costado. Fila o línea elegidas por el jugador solo se abren o se cierran.
- **51 — Técnicas de movimiento.** Simple sin contactos; con vigilancia si hay un contacto conocido a 600 m (el equipo A va 20 m detrás); por saltos si se espera (la opción BOUND). Saltos alternados (el que estaba quieto pasa adelante) sin fuego encima; sucesivos bajo fuego.
- **52 — Emboscadas.** En marcha, si le tiran desde menos de 35 m: asalta al emboscador a la carrera sin tirarse al suelo, y retoma la orden al llegar o si cae. Más lejos: drill de contacto y después fuego y movimiento.
- **53 — Reptar.** Ritmo nuevo (X) a 0,3 m/s, cuerpo a tierra; no se lo detecta como en marcha. Una escuadra con autonomía, clavada en marcha 3 s, sigue reptando hacia su destino.
- **54 — Tirador selecto.** El soldado 7: siempre observa y quieto ve al doble; tira a 500 m con 0,2 (×0,4 en marcha), cada 4 s, y prefiere al jefe, la ametralladora y el antitanque.
- **55 — Sectores.** Quieta, la escuadra reparte 120° de frente entre los soldados (con 10° de solape) y prefiere blancos en su sector; la ametralladora tira oblicua (línea final, 25°) y suprime rasante a lo largo. Tras 3 ráfagas desde el mismo lugar bajo fuego, cambia de posición. El reconocimiento por fuego (mecánica 15) quedó recortado.
- **56 — Zona de peligro.** Un claro de 4 a 15 celdas entre bosques, sin fuego encima: el equipo A asegura del lado cercano, el B cruza a la carrera y después cruza el A.
- **57 — Pozos y consolidar.** Quieto 45 s en su cobertura y poco suprimido, el soldado cava un pozo (un cráter, para siempre). Al terminar un asalto o llegar al objetivo, la escuadra redistribuye la munición.
- **58 — Pelotón como un cuerpo.** Misión (M): punta y las demás 10 celdas detrás; la primera en contacto a 300 m queda de base y bate el contacto, las demás flanquean; asaltan al llegar (o a los 90 s), la base corre el fuego 50 m más allá cuando el asalto está a 60 m, y todos al objetivo. Banco: modo `peloton`.
- **59 — Contraataque y rendición.** El rojo contraataca con todas sus frescas si el azul llega al objetivo sin pozos (menos de la mitad) y no lo supera en número. Quebrada hace 8 s, sin ruta (clavada o sin camino) y con un enemigo conocido a 50 m: se rinde.
