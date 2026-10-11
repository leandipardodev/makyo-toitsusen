# Makyou Toitsusen — guía y comunidad

Web estática sobre *Yu Yu Hakusho: Makyou Toitsusen* (Mega Drive, 1994): fichas de
los 11 luchadores, frame data extraída del ROM, guías, matchup editable, circuito
competitivo y las herramientas de análisis.

Sin dependencias, sin build: HTML, CSS y JavaScript plano.

**En vivo:** <https://makyo-toitsusen.vercel.app>

## Cómo se ve

```
python -m http.server 8099
```

y abrir <http://127.0.0.1:8099>.

## Qué hay

| Ruta | Contenido |
|---|---|
| `#/` | portada |
| `#/personajes` | los once luchadores |
| `#/persona/<id>` | ficha completa: golpes, especiales, árbol de aprendizaje, combos, frame data |
| `#/guias` | guías generales |
| `#/matchup` | matriz 11×11 con calificación 1-10 |
| `#/circuito` | torneo, 2v2, liga, ranking e historial |
| `#/descargas` | herramientas para Fightcade + FBNeo |

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

## Sobre el resto del proyecto

Esta carpeta (`web/`) es la parte pública. El proyecto completo incluye el
desensamblado del ROM, la documentación técnica y las herramientas de análisis,
que no se publican.