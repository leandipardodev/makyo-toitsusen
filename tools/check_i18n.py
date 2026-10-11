# -*- coding: utf-8 -*-
"""Revisa que las traducciones no tengan texto de otro idioma colado.

Solo mira las traducciones donde tiene sentido: en chino no puede haber kana ni
palabras latinas sueltas, y en japones no puede haber han simplificado.
El castellano y el ingles se dan por buenos.
"""
import io
import json
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

WEB = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
d = json.load(open(os.path.join(WEB, "data", "i18n.json"), encoding="utf-8"))

# Han simplificado (no existe en japones) - los mas frecuentes.
# OJO: 会 y 来 SI son kanji japoneses legitimos (大会, 来る): no van aqui.
HAN_SIMP = set("谁电记输开关战术个么这还说过块对时没样动产众头长门马鸟鱼龙买卖东车见头")

# Palabras latinas permitidas dentro de zh/ja: comandos, rutas, nombres de campo
PERMITIDAS = {
    "rom", "med", "web", "es", "en", "zh", "ja", "ta", "md", "youtube", "embed",
    "json", "html", "code", "iframe", "src", "http", "https", "span", "class",
    "chip", "options", "startup", "active", "recovery", "hit", "time", "block",
    "stun", "debug", "notes", "note", "start", "stop", "run", "set", "id",
    "sensui", "jin", "itsuki", "genkai", "kuwabara", "yusuke", "kurama",
    "hiei", "chui", "toguro", "yuyu", "new", "win", "wins",
    "matchup", "circuito", "history", "list", "add", "clear", "load", "export",
    "download", "video", "lore", "combo", "combos", "move", "moves", "type",
    "total", "damage", "level", "tier", "learn", "write", "player", "players",
    "name", "league", "circuit", "tournament", "season", "gold", "silver",
    "bronze", "star", "stars", "rank", "ranking", "data",
    # nombres propios, comandos de juego y rutas de archivo
    "extras", "handicap", "fightcade", "fbneo", "super", "backstep", "line",
}


def recorrer(v, ruta=""):
    if isinstance(v, dict):
        for k, x in v.items():
            yield from recorrer(x, ruta + "." + str(k))
    elif isinstance(v, list):
        for i, x in enumerate(v):
            yield from recorrer(x, ruta + "[%d]" % i)
    elif isinstance(v, str):
        yield ruta, v


problemas = 0

for idioma in ("zh", "ja"):
    for ruta, txt in recorrer(d[idioma], idioma):
        limpio = re.sub(r"<[^>]+>", " ", txt)
        limpio = re.sub(r"[↑↓↘←→›«»↔×·　,.:;!?()\[\]/|-]", " ", limpio)

        # 1. palabras latinas sueltas
        for w in re.findall(r"[A-Za-z]{3,}", limpio):
            if w.lower() in PERMITIDAS:
                continue
            print("[%s] palabra latina en %s -> %r" % (idioma, ruta, w))
            problemas += 1

        # 2. kana en chino
        if idioma == "zh":
            kana = re.findall(r"[\u3040-\u30ff]", limpio)
            if kana:
                print("[zh] kana en %s -> %s" % (ruta, "".join(kana[:12])))
                problemas += 1

        # 3. han simplificado en japones
        if idioma == "ja":
            malos = sorted({c for c in limpio if c in HAN_SIMP})
            if malos:
                print("[ja] han simplificado en %s -> %s" % (ruta, "".join(malos)))
                problemas += 1

print("\nproblemas: %d" % problemas)