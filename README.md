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
| Doble clic | Seleccionar el pelotón entero (4 tanques en dos secciones, A y B). Una orden de mover al pelotón pone las secciones lado a lado, con sus centros a 40 m |
| J y clic derecho | Avance por saltos (pelotón entero seleccionado): la sección más cercana al objetivo avanza primero y la otra espera quieta, cubriéndola, hasta que llegue. Después avanza la segunda |
| Clic derecho | Mover (solo al planificar) |
| Ctrl + clic derecho | Mover por la ruta directa (la más corta, sin importar la exposición; se dibuja en naranja) |
| Shift + clic derecho | Agregar un tramo al final de la ruta (waypoint). Ctrl + Shift: tramo directo |
| Clic derecho y arrastrar | Mover y elegir hacia dónde queda mirando el tanque al llegar |
| Clic derecho sobre un rojo | Atacar: avanza por la ruta cubierta hasta tener línea de tiro, frena y lo prioriza como blanco (solo rojos visibles o fantasmas) |
| H | Hull-down: cada tanque seleccionado busca una posición con el casco cubierto |
| V | Vigilancia: el tanque se queda quieto mirando hacia el cursor y solo dispara dentro de un sector de ±35°. Arranca cada turno con la recarga lista y su primer disparo contra un blanco en movimiento tiene ×1,5 |
| F y clic derecho | Disparar y replegarse: va a esa posición, hace un disparo y vuelve en reversa a donde estaba, mirando al blanco. Esc cancela |
| G y clic izquierdo | Humo: una nube de 12 m de radio que corta la línea de visión durante 2 turnos. 2 cargas por tanque, hasta 150 m y con línea de visión al punto. Aparece en el acto, así que tirala antes de planear la ruta. Esc cancela |
| T y clic derecho | Asaltar: ruta directa a ritmo rápido hasta ese punto, disparando en marcha y sin frenar. Esc cancela |
| B | Retirarse: en reversa por la ruta cubierta hasta la celda menos expuesta cercana, con el frente hacia las amenazas |
| K | Condición para arrancar el último tramo de la ruta: ninguna → a los 10 s del turno → a los 20 s → al haber contacto. El tanque espera quieto (y se lo detecta como quieto); el punto de paso se marca en violeta |
| X | Ritmo de los seleccionados: normal → rápido (×1,4 de velocidad, tira peor) → cauto (×0,5, tira mejor en marcha y se lo detecta como si estuviera quieto) |
| N | Formación de las escuadras seleccionadas: cuña → fila india → línea |
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
| L | Cambiar de escenario: tanques (la demo original) o la loma (infantería y un tanque por bando) |
| U y clic derecho | Suprimir: la unidad se queda quieta batiendo esa zona con fusiles o coaxial, aunque no vea a nadie. Casi no mata, pero suprime a todo lo que haya ahí. Esc cancela |

### Reglas de combate

- **Blindaje:** un tanque recibe menos impactos de frente (×0,6) que de flanco (×1) o por detrás (×1,4). Al ir a hull-down mira hacia las amenazas; con el clic derecho arrastrado elegís vos la orientación. El casco no gira solo.
- **Detección:** a un tanque en movimiento se lo detecta hasta 350 m; quieto, hasta 220 m, y quieto con el casco oculto, hasta 150 m. Disparar te delata: el enemigo sabe de dónde vino el tiro y durante 3 s te ve a 350 m.

- **Reglas de fuego:** con *fuego libre* el tanque tira solo a lo que ve. Con *solo si le disparan* espera a recibir un disparo y queda liberado 15 s. Con *retener fuego* no tira nunca, y como no dispara tampoco se delata. Las ROE y el área de enganche duran hasta que las cambies. La IA en vigilancia espera a que te acerques a 250 m, salvo que ya la hayas atacado.

- **Vista previa de riesgo:** con un tanque seleccionado, los tramos de su ruta que quedan a la vista de un enemigo conocido se pintan en rojo, y el panel muestra cuánto dura la ruta, cuántos segundos está expuesto, los impactos esperados (contra los enemigos conocidos, quietos y con la recarga lista), qué cara del blindaje muestra y un riesgo bajo, medio o alto. No cuenta las esperas de las condiciones.

### La loma

Con **L** cambiás al escenario de infantería. Cada bando tiene 3 escuadras de infantería y 1 tanque, los turnos duran 45 s y el mapa tiene bosques, muros y pozos. El rojo defiende detrás de la cresta central, con bosque en la contrapendiente.

- **Soldados:** cada escuadra son 9 soldados que se ven uno por uno: el jefe y la ametralladora (más anchos), un proveedor, un tirador antitanque y cinco fusileros. Marchan juntos en formación (**N**: cuña, fila india o línea, a 3 m) a 1,5 m/s y suben pendientes que el tanque no. Si alguno queda a más de 6 m de su lugar, la escuadra lo espera.
- **Cobertura de cada soldado:** al detenerse, cada uno busca a menos de 6 m de su lugar una roca, un tramo de muro, un tronco, un cráter o la contrapendiente, a 2 m o más de los demás, y toma la postura que le sirve: agachado detrás de un muro (tira por encima), cuerpo a tierra detrás de una roca (asoma por el costado). Sin nada cerca, cuerpo a tierra. La ametralladora prioriza tener tiro. Si la amenaza se corre, vuelven a buscar.
- **Microcobertura:** además de bosques, muros y pozos, el mapa tiene rocas (60 cm), arbustos (ocultan pero no frenan balas) y cráteres, a 1 m de resolución.
- **Visión:** se detecta a cada soldado por separado: hasta 250 m si camina de pie o acaba de disparar, 120 m quieto y 60 m cuerpo a tierra, menos en el bosque o detrás de algo que lo protege. Una roca tapa a uno cuerpo a tierra; un muro, a uno agachado. Ver a un soldado delata a su escuadra, pero solo se le puede tirar a los que se ven.
- **Armas:** cada soldado tira con la suya: fusil (un tiro), ametralladora (ráfaga que afecta a todos los que estén a 3 m del punto) y antitanque (150 m, 2 cargas por escuadra, mejor por el flanco o la cola). La coaxial del tanque tira ráfagas a soldados. Pegarle a uno protegido cuesta 5 veces más. Un impacto hiere o mata; el herido queda tirado donde cayó y no combate.
- **Supresión y moral:** cada soldado tiene su supresión: el tiro le suma al que apuntaron y la mitad a los que están a 5 m (menos si está protegido). Desde 50 se tira al suelo y tira peor; desde 85 queda clavado: no tira ni se mueve. Si más de la mitad está suprimida, la escuadra no avanza. Un tanque suprimido se abotona y ve a la mitad de distancia. Las bajas (más si cae el jefe) y la parte de soldados suprimidos bajan la moral de la escuadra; con menos de 25 se quiebra, se retira sola e ignora órdenes hasta recuperarse.
- **Objetivo:** el círculo blanco sobre la cresta. Al llegar al turno 12, ganás si tenés infantería sin quebrar adentro y el rojo no; si los dos tienen, es empate; si no, gana el rojo. Destruir a todo el bando contrario también gana.
- **IA roja:** sus escuadras buscan cobertura con vista a las rutas de acercamiento y no abren fuego a más de 150 m salvo que las ataquen. Suprimen la última posición conocida de tu infantería y se repliegan cuando quedan diezmadas. Defienden, no contraatacan.
- **Pelotón mixto:** con el pelotón seleccionado (doble clic), la infantería va al objetivo y el tanque se queda 48 m detrás, cubriéndola.

Ganás si destruís a los 4 rojos. Si se llega al turno 12, gana el bando con más tanques vivos.

## Tests

```bash
# Solo la primera vez en un clon limpio (registra los class_name)
godot --headless --path . --import

# Tests de la simulación (exit code 0 = todo bien)
godot --headless --path . --script res://tests/run_tests.gd

# Smoke test: arranca el juego unos segundos sin ventana
godot --headless --path . --quit-after 300

# Smoke test de la loma, jugando los turnos solo
godot --headless --path . --quit-after 3000 -- --loma --autoplay

# Rendimiento de la loma (ms por tick)
godot --headless --path . --script res://tests/bench_loma.gd
```

## Estructura

- `sim/`: lógica pura y determinista (terreno, línea de visión, A*, combate, IA). Ticks fijos de 0,1 s, aleatoriedad con semilla.
- `game/`: presentación (malla del terreno, cámara, vistas de tanques, input, overlays, HUD).
- `tests/`: tests headless de `sim/`.
- Constantes ajustables en `sim/config.gd`. El plan completo está en `docs/PLAN.md`.
