# Makyou Toitsusen — guía y comunidad

Web estática sobre *Yu Yu Hakusho: Makyou Toitsusen* (Mega Drive, 1994): fichas de
los 11 luchadores, frame data extraída del ROM, guías, matchup editable, circuito
competitivo y las herramientas de análisis.

Sin dependencias, sin build: HTML, CSS y JavaScript plano.

**En vivo:** <https://makyo-toitsusen.vercel.app>

**Código:** <https://github.com/leandipardodev/makyo-toitsusen>

## Publicar un cambio

Vercel está conectado al repo: **cada `git push` a `main` despliega solo**, sin
ejecutar nada. El build tarda unos 30 segundos.

```
git add -A
git commit -m "lo que cambié"
git push
```

Después de unos 30 segundos está arriba. Para verlo antes, el despliegue se puede
revisar en la pestaña Deployments del proyecto en Vercel.

Un collaborator con acceso de escritura al repo puede hacer exactamente lo mismo:
no hace falta ser dueño de Vercel para que su push llegue a producción.

## Cómo se ve

```
python -m http.server 8099
```

y abrir <http://127.0.0.1:8099>.

## Qué hay

| Ruta | Contenido |
|---|---|
| `#/` | portada |
| `#/torneos` | todos los torneos, con miniatura y video completo |
| `#/torneo/<id>` | un torneo: video, podio, rondas y sus clips |
| `#/highlights` | galería de clips, con filtro por personaje y origen |
| `#/reglas` | reglas del circuito |
| `#/personajes` | los once luchadores |
| `#/persona/<id>` | ficha completa: golpes, especiales, árbol de aprendizaje, combos, frame data |
| `#/guias` | guías generales |
| `#/matchup` | matriz 11×11 con calificación 1-10 |
| `#/circuito` | torneo, 2v2, liga, ranking e historial |
| `#/descargas` | herramientas para Fightcade + FBNeo |

## Torneos, clips y reglas

Tres secciones y tres ficheros para llenarlas. Los esquemas están documentados
dentro de cada JSON, en el campo `_notas`.

**`data/torneos.json`** — lista `torneos`. Cada torneo lleva `video` (el video
completo), `podio`, `rondas`, `personajes` permitidos y `highlights` (los clips
que salieron de él). El `id` es lo que va en la URL: `#/torneo/<id>`.

**`data/highlights.json`** — lista `clips` para los clips sueltos, los que no
pertenecen a un torneo o que merece la pena destacar igual. La galería de
`#/highlights` junta los dos tipos y filtra por personaje y por origen.

**`data/reglas.json`** — `intro` y `bloques`. Cada bloque es un tema (inscripción,
formato, personajes, reglamento, conducta, premios) con una lista de reglas. Acepta
texto plano o `{ t, d }` para regla con título y detalle. Los bloques vacíos
muestran un aviso.

Los vídeos se ponen como link de YouTube: valen tanto `watch?v=ID` como
`youtu.be/ID`, la web los convierte sola al formato `/embed/`. Si no hay vídeo se
muestra un marco de espera, así que se puede cargar el torneo antes de tenerlo.

## Idiomas

Español, inglés, chino y japonés, autodetectados. El orden para elegir el idioma
es `?idioma=xx` en la URL, después lo que el visitante haya elegido con el
selector (se guarda en `localStorage`), y por último lo que diga el navegador.
Si falta un texto en el idioma elegido cae al español.

Se revisa con:

```
python tools/check_i18n.py
```

## Los datos salen del ROM

La frame data y las constantes no salen de internet: salen de leer el código del
68000 y la tabla de animación de cada contexto. En cada bloque de la web está
marcado el origen:

- `ROM` — verificado en el código
- `MEDIDO` — medido corriendo el juego en el emulador
- `WEB` — sin verificar

El juego tiene derechos de autor y **no** se distribuye desde acá. Lo que se
publica son las herramientas.

## Herramientas

```
python tools/build_data.py   -> regenera personajes.json y moves.json
python tools/recortar.py     -> recortes de imagen por personaje
python tools/duotono.py      -> paleta común de las imágenes
python tools/check_i18n.py   -> revisa las traducciones
python tools/ver_json.py     -> los JSON parsean y están completos
```

## Lo que falta y hay que llenar

1. **Torneos** — `data/torneos.json`: nombre, fecha, formato, lugar, entradas,
   premio, podio, rondas y el link del video completo.
2. **Clips** — `data/highlights.json` para los sueltos, o el campo `highlights`
   de cada torneo.
3. **Reglas** — `data/reglas.json`, los seis bloques están creados y vacíos.
4. **Vídeos por personaje** — `data/extras.json`, campo `video` de cada uno.
5. **Lore** — `data/extras.json`, campo `lore`.
6. **Ranking del circuito** — `data/circuito.json`, lista `jugadores`, o cargarlo
   desde la propia web (se guarda en el navegador y se exporta el JSON).
7. **Matchups reales** — se escriben a mano en `#/matchup` y se exportan.
8. **Premiación concreta** — porcentajes de premio por puesto, fechas y
   requisitos de inscripción.
9. **Hackroom y emulador** — `data/descargas.json`: subir los archivos.
10. **Combos reales** — en cada ficha hay un formulario para cargarlos. Los que
    hay por defecto son propuestas generadas, no están verificados.
11. **Fichas en otros idiomas** — `personajes.json` está en castellano. Para
    traducir `lema`, `rol`, `nota` y `frases`, la forma limpia es un
    `personajes.<idioma>.json` por idioma y que la web elija según `IDIOMA`.

## Sobre el resto del proyecto

Esta carpeta (`web/`) es la parte pública. El proyecto completo incluye el
desensamblado del ROM, la documentación técnica y las herramientas de análisis,
que no se publican.