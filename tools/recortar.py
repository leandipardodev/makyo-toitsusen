# -*- coding: utf-8 -*-
"""
recortar.py - una imagen por personaje, sacada de la pantalla de seleccion.

Los ficheros "retrato_posNN" que hay en sprites/ son recortes de esa pantalla
con la paleta corrida y no se entiende nada, asi que aqui se recorta la fila
de luchadores del render grande (charselect_4x_mejor.png), que si se ve.

Los centros de cada luchador se sacan a ojo de la pantalla de 320 px y se
pasan a la imagen de 1280 multiplicando por 4.
"""
import os

from PIL import Image, ImageDraw

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(RAIZ, "sprites", "charselect_4x_mejor.png")
DST = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "img"))

NOMBRES = ["sensui", "jin", "itsuki", "genkai", "kuwabara", "yusuke",
           "kurama", "hiei", "chui", "toguromayor", "toguromenor"]

ESC = 4          # la imagen grande es 4x la de 320x224
Y0, Y1 = 190, 588        # banda vertical de la fila de luchadores

# centro (en pixeles de la pantalla de 320) y ancho de cada luchador.
# El ancho es angosto a proposito: en la pantalla los luchadores se pisan unos
# con otros, y un caja ancha se comia al vecino de al lado.
CAJAS = [
    (30, 24), (54, 24), (78, 24), (100, 22), (122, 22),
    (146, 22), (167, 24), (189, 24), (211, 26), (239, 30), (287, 34),
]


def main():
    im = Image.open(SRC).convert("RGB")
    os.makedirs(DST, exist_ok=True)

    hojas = []
    for i, ((cx, ancho), nombre) in enumerate(zip(CAJAS, NOMBRES), start=1):
        x0 = (cx - ancho // 2) * ESC
        x1 = (cx + ancho // 2) * ESC
        caja = im.crop((x0, Y0, x1, Y1))
        ruta = os.path.join(DST, "pj_%02d_%s.png" % (i, nombre))
        caja.save(ruta)
        hojas.append((i, nombre, caja))
        print("%2d %-14s x %4d..%4d  ->  %s" % (i, nombre, x0, x1, os.path.basename(ruta)))

    # hoja de contactos para revisarlo de un vistazo
    alto = max(c.size[1] for _, _, c in hojas)
    hoja = Image.new("RGB", (sum(c.size[0] for _, _, c in hojas) + 120, alto + 24), (10, 10, 16))
    d = ImageDraw.Draw(hoja)
    x = 0
    for i, nombre, c in hojas:
        hoja.paste(c, (x, 24))
        d.text((x + 4, 6), "%d %s" % (i, nombre[:8]), fill=(255, 200, 60))
        x += c.size[0] + 10
    hoja.save(os.path.join(DST, "_hoja_contacto.png"))
    print("\nhoja de contactos: img/_hoja_contacto.png")


if __name__ == "__main__":
    main()