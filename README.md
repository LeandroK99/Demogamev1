# Hull-Down

Demo táctica en Godot: escaramuza **WeGo** de 4 tanques azules (vos) contra 4 rojos (IA) sobre un terreno 3D procedural de 384 × 384 m.

Cada turno el juego se pausa: das órdenes, apretás **Espacio** y se ejecutan 30 s simultáneos. La gracia está en el terreno: un tanque con el casco detrás de una cresta (*hull-down*) es mucho más difícil de impactar, y las rutas cubiertas te acercan sin que te vean. La IA roja usa las mismas herramientas que vos.

## Cómo correrlo

1. Instalá **Godot 4.4 o superior** (versión estándar, no .NET). Probado con 4.4.1 y 4.7.2.
2. En el Gestor de proyectos: **Importar** y elegí el `project.godot` de esta carpeta.
3. **F5** para jugar.

## Controles

| Tecla | Acción |
|---|---|
| Clic izquierdo / arrastrar | Seleccionar un tanque / selección por recuadro |
| Clic derecho | Mover (solo al planificar) |
| Ctrl + clic derecho | Mover por la ruta directa (la más corta, sin importar la exposición; se dibuja en naranja) |
| Shift + clic derecho | Agregar un tramo al final de la ruta (waypoint). Ctrl + Shift: tramo directo |
| Clic derecho y arrastrar | Mover y elegir hacia dónde queda mirando el tanque al llegar |
| Clic derecho sobre un rojo | Atacar: avanza por la ruta cubierta hasta tener línea de tiro, frena y lo prioriza como blanco (solo rojos visibles o fantasmas) |
| H | Hull-down: cada tanque seleccionado busca una posición con el casco cubierto |
| V | Vigilancia: el tanque se queda quieto mirando hacia el cursor y solo dispara dentro de un sector de ±35°. Arranca cada turno con la recarga lista y su primer disparo contra un blanco en movimiento tiene ×1,5 |
| F y clic derecho | Disparar y replegarse: va a esa posición, hace un disparo y vuelve en reversa a donde estaba, mirando al blanco. Esc cancela |
| G y clic izquierdo | Humo: una nube de 12 m de radio que corta la línea de visión durante 2 turnos. 2 cargas por tanque, hasta 150 m y con línea de visión al punto. Aparece en el acto, así que tirala antes de planear la ruta. Esc cancela |
| Z | Reglas de fuego (ROE) de los seleccionados: fuego libre → solo si le disparan → retener fuego |
| C | Área de enganche: solo dispara dentro de un arco de ±45° hacia el cursor y hasta la distancia del cursor. Shift+C la quita |
| Espacio | Ejecutar el turno |
| 1 | Overlay de exposición azul (verde = cubierto, rojo = visto por todos los enemigos conocidos) |
| 2 | Mejores posiciones hull-down de la unidad seleccionada |
| 3 | Líneas de visión de la unidad seleccionada a los enemigos conocidos |
| + / - | Velocidad ×1 / ×2 / ×4 |
| WASD o flechas | Mover la cámara |
| Rueda | Zoom |
| Q / E o botón medio | Rotar la cámara |
| R / Shift+R | Reiniciar con la misma semilla / con un mapa nuevo |

### Reglas de combate

- **Blindaje:** un tanque recibe menos impactos de frente (×0,6) que de flanco (×1) o por detrás (×1,4). Al ir a hull-down mira hacia las amenazas; con el clic derecho arrastrado elegís vos la orientación. El casco no gira solo.
- **Detección:** a un tanque en movimiento se lo detecta hasta 350 m; quieto, hasta 220 m, y quieto con el casco oculto, hasta 150 m. Disparar te delata: el enemigo sabe de dónde vino el tiro y durante 3 s te ve a 350 m.

- **Reglas de fuego:** con *fuego libre* el tanque tira solo a lo que ve. Con *solo si le disparan* espera a recibir un disparo y queda liberado 15 s. Con *retener fuego* no tira nunca, y como no dispara tampoco se delata. Las ROE y el área de enganche duran hasta que las cambies. La IA en vigilancia espera a que te acerques a 250 m, salvo que ya la hayas atacado.

Ganás si destruís a los 4 rojos. Si se llega al turno 12, gana el bando con más tanques vivos.

## Tests

```bash
# Solo la primera vez en un clon limpio (registra los class_name)
godot --headless --path . --import

# Tests de la simulación (exit code 0 = todo bien)
godot --headless --path . --script res://tests/run_tests.gd

# Smoke test: arranca el juego unos segundos sin ventana
godot --headless --path . --quit-after 300
```

## Estructura

- `sim/`: lógica pura y determinista (terreno, línea de visión, A*, combate, IA). Ticks fijos de 0,1 s, aleatoriedad con semilla.
- `game/`: presentación (malla del terreno, cámara, vistas de tanques, input, overlays, HUD).
- `tests/`: tests headless de `sim/`.
- Constantes ajustables en `sim/config.gd`. El plan completo está en `docs/PLAN.md`.
