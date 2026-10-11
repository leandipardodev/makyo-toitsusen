# -*- coding: utf-8 -*-
"""Muestra una muestra de los JSON generados, para revisarlos a ojo."""
import io
import json
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

WEB = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
p = json.load(open(os.path.join(WEB, "data", "personajes.json"), encoding="utf-8"))
mv = json.load(open(os.path.join(WEB, "data", "moves.json"), encoding="utf-8"))

for x in p:
    print("== %s (%s)  %s" % (x["nombre"], x["nombre_kana"], x["lema"]))
    print("   perfil :", x["perfil"])
    print("   stats  :", x["stats"])
    print("   rol    :", x["rol"], "| super:", x["super"])
    print("   ctx    :", x["ctx"], "| retrato:", x["retrato"])
    print("   normales:", len(x["normales"]), " especiales:", len(x["especiales"]),
          " frases:", len(x["frases"]))
    for e in x["especiales"][:2]:
        print("     *", e["nombre"], "|", e["cmd"], "| dmg", e["dmg"],
              "| mana", e["mana"], "| stun", e["stun"])
    print("   frases :", x["frases"][:2])
    print()

print("=== muestra de moves (ctx2 kuwabara) ===")
c = mv["ctx2"]
print("tabla $50:", c["tabla"], " moves:", len(c["lista"]))
con_dano = [m for m in c["lista"] if m["dmg"] > 0]
print("moves con dano:", len(con_dano))
for m in con_dano[:8]:
    print("   %-8s esp=%-5s tot=%-3d start=%-2d act=%-2d rec=%-2d dmg=%-3d stun=%-3d %s" % (
        m["hex"], m["especial"], m["total"], m["startup"], m["activo"],
        m["recovery"], m["dmg"], m["stun"], "MANTENER" if m["hold"] else ""))