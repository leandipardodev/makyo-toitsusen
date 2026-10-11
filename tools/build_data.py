# -*- coding: utf-8 -*-
"""
build_data.py - genera los JSON de la web a partir de los datos del proyecto.

Fuentes (todas locales, ninguna inventada):
  _disasm_tools/MOVELIST.txt        frame data del ROM (startup/activo/recuperacion)
  docs/FICHAS_DE_PERSONAJES.md      fichas: perfil, especiales, frases
  AGENTS.md / GUIA_TECNICA_UNIFICADA.md  constantes verificadas

Salida:
  ../data/personajes.json   fichas + especiales
  ../data/moves.json        frame data por contexto

Uso:  python build_data.py
"""
import json
import os
import re
import unicodedata

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.abspath(os.path.join(AQUI, "..", ".."))
DATA = os.path.join(AQUI, "..", "data")

# Contexto del ROM -> personaje. Verificado en AGENTS.md ("Mapeo contexto ->
# personaje"). Los contextos 1 y 7 son el mismo personaje (Itsuki/Kurama) y el 3
# y 9 tambien (Yusuke/Chui); el 12 no es un personaje jugable.
CTX_PERSONAJE = {
    1: "itsuki", 2: "kuwabara", 3: "yusuke", 4: "hiei", 5: "sensui",
    6: "jin", 7: "itsuki", 8: "toguro_mayor", 9: "yusuke",
    10: "toguro_menor", 11: "genkai", 12: None,
}

# Orden de seleccion en la pantalla de personajes (pos01..pos11)
ORDEN = ["sensui", "jin", "itsuki", "genkai", "kuwabara", "yusuke",
         "kurama", "hiei", "chui", "toguro_mayor", "toguro_menor"]

# El nombre del fichero del retrato de cada posicion (sprites/retrato_posNN_*.png)
FICHA_SLUG = {
    1: "sensui", 2: "jin", 3: "itsuki", 4: "genkai", 5: "kuwabara",
    6: "yusuke", 7: "kurama", 8: "hiei", 9: "chui",
    10: "toguromayor", 11: "toguromenor",
}

# Kurama y Itsuki son el mismo luchador en el ROM (ctx 1 y 7), y Chui y Yusuke
# tambien (ctx 3 y 9). Ver AGENTS.md.
ALIAS = {"kurama": "itsuki", "chui": "yusuke"}


def alias_nombre(clave):
    return ALIAS.get(clave, clave)


def limpiar(s):
    s = unicodedata.normalize("NFC", s)
    s = s.replace("\u00a0", " ")
    return re.sub(r"[ \t]+", " ", s).strip()


def quitar_guiones(s):
    return re.sub(r"[\u2013\u2014\u2500-\u257f\u25b6\u25b2\u2192\u2190\u2022]+",
                  "", s)


# ---------------------------------------------------------------- frame data

def leer_movelist():
    ruta = os.path.join(RAIZ, "_disasm_tools", "MOVELIST.txt")
    ctxs = {}
    ctx = None
    move = None
    with open(ruta, encoding="utf-8", errors="replace") as f:
        for linea in f:
            m = re.match(r"^ctx(\d+) move(\w+) addr=(\S+) off=(\S+) frames=\s*(\d+)",
                         linea)
            if m:
                ctx = int(m.group(1))
                move = {
                    "id": "move" + m.group(2).upper(),
                    "num": int(m.group(2), 16),
                    "addr": m.group(3),
                    "frames": int(m.group(5)),
                    "fr": [],
                }
                ctxs.setdefault(ctx, []).append(move)
                continue
            m = re.match(r"\s+fr(\d+) addr=(\S+) dur=\s*(\d+) slot=\s*(\d+) "
                         r"flg=(0x\S+) est=(0x\S+) snd=\s*(\d+) "
                         r"dx=\s*(-?\d+) dy=\s*(-?\d+) dmg=\s*(\d+) stun=\s*(\d+)",
                         linea)
            if m and move is not None:
                move["fr"].append({
                    "n": int(m.group(1)),
                    "dur": int(m.group(3)),
                    "slot": int(m.group(4)),
                    "est": int(m.group(6), 16),
                    "snd": int(m.group(7)),
                    "dx": int(m.group(8)),
                    "dy": int(m.group(9)),
                    "dmg": int(m.group(10)),
                    "stun": int(m.group(11)),
                })
    return ctxs


def resumen_mov(m):
    """startup / activo / recuperacion en frames.

    Definicion (y la que se explica en la web):
      activo     = frames que tienen dano (dmg > 0), que es cuando la hitbox
                   hace dano de verdad
      startup    = frames hasta el primero activo
      recovery   = frames despues del ultimo activo
    dur = 255 significa "mantener pulsado", no son 255 frames: se cuenta como
    0 y el move se marca como cargable.
    """
    frs = m["fr"]
    hold = any(f["dur"] >= 255 for f in frs)
    total = sum(f["dur"] for f in frs if f["dur"] < 255)

    activos = [i for i, f in enumerate(frs) if f["dmg"] > 0]
    if activos:
        ini, fin = activos[0], activos[-1]
        startup = sum(f["dur"] for f in frs[:ini] if f["dur"] < 255)
        activo = sum(f["dur"] for f in frs[ini:fin + 1] if f["dur"] < 255)
        recovery = sum(f["dur"] for f in frs[fin + 1:] if f["dur"] < 255)
    else:
        startup = activo = 0
        recovery = total

    dmg = sum(f["dmg"] for f in frs)
    stun = sum(f["stun"] for f in frs)
    hits = len(activos)

    return {
        "id": m["id"],
        "hex": "$%02X" % m["num"],
        "dir": m["addr"],
        "frames": m["frames"],
        "total": total,
        "startup": startup,
        "activo": activo,
        "recovery": recovery,
        "dmg": dmg,
        "dmg1": frs[activos[0]]["dmg"] if activos else 0,
        "stun": stun,
        "hits": hits,
        "hold": hold,
        "especial": m["num"] >= 0x80,
    }


# ---------------------------------------------------------------- fichas

def leer_fichas():
    ruta = os.path.join(RAIZ, "docs", "FICHAS_DE_PERSONAJES.md")
    with open(ruta, encoding="utf-8", errors="replace") as f:
        texto = f.read()

    # Ojo: el archivo usa raya (—), no guion, en "# ID 1 — SENSUI"
    bloques = re.split(r"^# ID (\d+)\s*[-–—]\s*(.+)$", texto, flags=re.M)
    out = {}
    # bloques[0] = cabecera; luego de tres en tres
    for i in range(1, len(bloques), 3):
        pid = int(bloques[i])
        cab = bloques[i + 1].strip()
        cuerpo = bloques[i + 2]

        nombre = re.split(r"\s*\(", cab)[0].strip()
        kana = ""
        m = re.search(r"\((.+?)\)\s*$", cab)
        if m:
            kana = m.group(1)

        lema = ""
        m = re.search(r'^###\s*[""\u201c](.+?)[""\u201d]\s*$', cuerpo, flags=re.M)
        if m:
            lema = m.group(1)

        perfil = {}
        m = re.search(r"\*\*Perfil\*\*\s*\|\s*(.+?)\s*\|", cuerpo)
        if m:
            for par in m.group(1).split("·"):
                par = par.strip().replace("**", "")
                k, _, v = par.partition(" ")
                if k and v:
                    perfil[limpiar(k)] = limpiar(v)

        # La fila es: | **Stun** | 54 | **Dash** 83 | **Backdash** 70 |
        #              Walk D | Regen. maná E |
        # o sea que cada etiqueta puede o no llevar "|" delante. Y el valor
        # puede ser un numero (stun, dash) o una nota (S, A, B...).
        nums = {}
        for clave in ("Stun", "Dash", "Backdash", "Walk", "Regen"):
            # la etiqueta puede venir en negrita o no, y con o sin "|"
            m = re.search(r"\*?\*?%s\*?\*?\s*\|?\s*\|?\s*([\d]+(?:\.[\d]+)?)"
                          % clave, cuerpo)
            if m:
                nums[clave.lower()] = float(m.group(1))
                continue
            m = re.search(r"\*?\*?%s\*?\*?\s*\|?\s*\|?\s*([SABCDEF])\b" % clave, cuerpo)
            if m:
                nums[clave.lower()] = m.group(1)

        rol = ""
        m = re.search(r"\*\*Rol\*\*\s*\|\s*(.+?)\s*\|", cuerpo)
        if m:
            rol = limpiar(m.group(1))

        super_cmd = ""
        m = re.search(r"\*\*Super\*\*\s*\|\s*`([^`]+)`", cuerpo)
        if m:
            super_cmd = limpiar(quitar_guiones(m.group(1)))

        normales = []
        m = re.search(r"### Golpes normales(.*?)(###|$)", cuerpo, flags=re.S)
        if m:
            for fila in re.findall(r"^\|(.+)\|$", m.group(1), flags=re.M):
                c = [limpiar(x) for x in fila.split("|")]
                if len(c) >= 6 and c[0] not in ("Golpe",) and "---" not in c[0]:
                    normales.append({
                        "golpe": c[0], "altura": c[1], "efecto": c[2],
                        "dmg": c[3], "stun": c[4], "cancel": c[5],
                    })

        especiales = []
        m = re.search(r"### Especiales(.*?)(###|\n---|\Z)", cuerpo, flags=re.S)
        nota = ""
        if m:
            bloque = m.group(1)
            for fila in re.findall(r"^\|(.+)\|$", bloque, flags=re.M):
                c = [limpiar(x) for x in fila.split("|")]
                if len(c) >= 5 and c[0] not in ("T\u00e9cnica",) and "---" not in c[0]:
                    especiales.append({
                        "nombre": c[0], "cmd": limpiar(quitar_guiones(c[1])),
                        "dmg": c[2], "mana": c[3], "stun": c[4],
                        "super": c[0].upper().startswith("SUPER"),
                    })
            mn = re.search(r"^>\s*(.+)$", bloque, flags=re.M)
            if mn:
                nota = limpiar(mn.group(1))

        frases = []
        m = re.search(r"\*\*Frases[^\n]*\*\*:?\s*(.+?)(?:\n\n|\Z)", cuerpo, flags=re.S)
        if m:
            frases = []
            for x in re.findall(r"[\u201c\"](.+?)[\u201d\"]", m.group(1)):
                # el fichero original tiene texto japones/chino corrupto
                # dentro de frases que son en castellano: se descarta
                if re.search(r"[\u4e00-\u9fff\u3040-\u30ff]", x):
                    continue
                if len(x) < 8 or not re.search(r"[A-Za-z]", x):
                    continue
                frases.append(limpiar(x))

        out[pid] = {
            "nombre": nombre, "kana": kana, "lema": lema, "perfil": perfil,
            "stats": nums, "rol": rol, "super": super_cmd,
            "normales": normales, "especiales": especiales,
            "nota": nota, "frases": frases,
        }
    return out


# ---------------------------------------------------------------- armazon

def main():
    ctxs = leer_movelist()
    fichas = leer_fichas()

    # personajes: orden de la pantalla de seleccion (pos01..pos11)
    # El ID de la ficha coincide con la posicion en la pantalla de personajes.
    nombres_ficha = {k: v for k, v in fichas.items()}

    personajes = []
    for pos, clave in enumerate(ORDEN, start=1):
        f = nombres_ficha.get(pos, {})
        p = {
            "id": clave,
            "pos": pos,
            "nombre": clave.replace("_", " ").title(),
            "nombre_ficha": f.get("nombre", ""),
            "nombre_kana": f.get("kana", ""),
            "lema": f.get("lema", ""),
            "perfil": f.get("perfil", {}),
            "stats": f.get("stats", {}),
            "rol": f.get("rol", ""),
            "super": f.get("super", ""),
            "normales": f.get("normales", []),
            "especiales": f.get("especiales", []),
            "nota": f.get("nota", ""),
            "frases": f.get("frases", []),
            "retrato": "img/retrato_pos%02d_%s.png" % (pos, f.get("slug", clave)),
            "ctx": [c for c, pj in CTX_PERSONAJE.items() if pj == alias_nombre(clave)],
            "video": "",
            "lore": "",
        }
        p["retrato"] = "img/retrato_pos%02d_%s.png" % (pos, FICHA_SLUG[pos])
        personajes.append(p)

    moves = {}
    for ctx, lista in ctxs.items():
        pj = CTX_PERSONAJE.get(ctx)
        if not pj:
            continue
        moves["ctx%d" % ctx] = {
            "personaje": pj,
            "tabla": "$%04X" % 0xBF75A,  # se sustituye abajo
            "lista": [resumen_mov(m) for m in lista],
        }
    # direcciones reales de la tabla $50 por contexto (AGENTS.md)
    bases50 = {
        1: "BF75A", 2: "C229A", 3: "C4EEA", 4: "C7C9A", 5: "CA6DA",
        6: "CCC7A", 7: "CF99A", 8: "D1E5A", 9: "D4A9A", 10: "D777A",
        11: "BCAAA",
    }
    for ctx in moves:
        moves[ctx]["tabla"] = "$" + bases50[int(ctx[3:])]

    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, "personajes.json"), "w", encoding="utf-8") as f:
        json.dump(personajes, f, ensure_ascii=False, indent=1)
    with open(os.path.join(DATA, "moves.json"), "w", encoding="utf-8") as f:
        json.dump(moves, f, ensure_ascii=False, separators=(",", ":"))

    nmov = sum(len(v["lista"]) for v in moves.values())
    print("personajes: %d" % len(personajes))
    print("contextos  : %d" % len(moves))
    print("moves      : %d" % nmov)
    for p in personajes:
        print("  %-14s %-12s ctx %-6s especiales %-3d frases %d" % (
            p["id"], p["nombre"], ",".join(map(str, p["ctx"])),
            len(p["especiales"]), len(p["frases"])))


if __name__ == "__main__":
    main()