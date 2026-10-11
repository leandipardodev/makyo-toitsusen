# -*- coding: utf-8 -*-
"""
duotono.py - le da una paleta comun a las capturas del juego.

Las capturas del ROM salen con la paleta corrida (todo azul y carne), que es un
problema conocido del proyecto. Aqui se pasan por un duotono: se saca el gris
y se mapea por una rampa de color fija. Asi todas las imagenes de la web
parecen del mismo juego y del mismo sitio, y de paso el problema de la paleta
desaparece.

Rampa: noche -> indigo -> ambar -> oro
"""
import os

from PIL import Image

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ORIGEN = os.path.join(RAIZ, "sprites")
DST = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "img"))

# rampa de 5 paradas
RAMPA = [
    (10, 12, 26),
    (28, 42, 92),
    (92, 74, 150),
    (216, 132, 66),
    (255, 226, 160),
]


def lut():
    """PIL aplica una lista de 768 sobre una imagen RGB: 3 tablas de 256,
    una por canal. Si se pasa una sola tabla, los tres canales salen iguales
    (todo azul), que es lo que pasaba antes."""
    r, g, b = [], [], []
    for i in range(256):
        t = i / 255.0 * (len(RAMPA) - 1)
        i0 = min(int(t), len(RAMPA) - 1)
        i1 = min(i0 + 1, len(RAMPA) - 1)
        f = t - i0
        for canal, destino in ((0, r), (1, g), (2, b)):
            destino.append(round(RAMPA[i0][canal] +
                                 (RAMPA[i1][canal] - RAMPA[i0][canal]) * f))
    return r + g + b


L = lut()


def aplicar(ruta):
    im = Image.open(ruta).convert("L").convert("RGB")
    return im.point(L)


def main():
    os.makedirs(DST, exist_ok=True)

    trabajos = [
        ("charselect_4x_mejor.png", "seleccion.png"),
        ("fight_4x.png", "combate.png"),
        ("charselect_11personajes_3x.png", "seleccion_strip.png"),
    ]
    for src, dst in trabajos:
        p = os.path.join(ORIGEN, src)
        if not os.path.exists(p):
            print("no existe:", src)
            continue
        im = aplicar(p)
        im.save(os.path.join(DST, dst))
        print("%-32s -> %-22s %s" % (src, dst, im.size))

    # los recortes por personaje que se sacaron de la pantalla de seleccion
    carpeta = os.path.join(DST)
    n = 0
    for f in sorted(os.listdir(carpeta)):
        if f.startswith("pj_") and f.endswith(".png"):
            im = aplicar(os.path.join(carpeta, f))
            im.save(os.path.join(carpeta, f))
            n += 1
    print("recortes con duotono:", n)


if __name__ == "__main__":
    main()