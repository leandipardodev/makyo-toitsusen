#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Decodificador de streams de graficos del Mega Drive codec `loc_0007be`.

El juego no guarda los tiles lineales en el caso general: los pinta a VRAM con
un mini-codec.

    word bit15=0          -> literal, va a un staging buffer.
    word bit15=1, !=$FFFF -> SET: vuelca a VRAM lo acumulado (DMA hacia la
                             direccion d4, un word literal = 2 bytes BE,
                             avanzando `auto` bytes entre word y word) y luego
                             d4 = base + (word & $7FFF); el word SIGUIENTE del
                             stream es el autoincremento VDP (registro $8F).
    word == $FFFF         -> flush final + fin de stream.

El autoincremento decide la forma de dibujar:
  * auto=2    -> words contiguos = data de tile 4bpp plano (32B por tile 8x8).
  * auto=$80  -> un word por fila de nametable (la fila estandar son 128B):
                 son entradas de NAMETABLE (tile index + atributos), no pixels.
  * auto=$100 -> igual, planos de 32 tiles por fila.

Ademas hay un SEGUNDO codec, `loc_000fe0`, usado sobre todo en el char select:
la tabla de bloques de 128 bytes apuntada por $f5a0 (en el char select
$24B9E0). Los words del stream son INDICES de bloque; cada indice d7 copia
128 bytes desde $f5a0 + d7*128 a VRAM (4 tiles 8x8 4bpp lineales), y la rutina
$1054 escribe ademas entradas de nametable en un buffer ($d200) que se vuelca
en bloque al final ($f5aa). Fin de stream: $FFFF.

Uso (ejemplos):
    python rom_streams.py <rom> <offset>                 # listar operaciones
    python rom_streams.py <rom> <offset> --vram out.bin  # reproduccion VRAM
    python rom_streams.py <rom> <offset> --nametable out.png --cram cram.bin
    python rom_streams.py <rom> <offset> --tiles out.png --cram cram.bin
    python rom_streams.py <rom> --scan                   # buscar todos los 7be
    python rom_streams.py <rom> --scan7                  # idem (alias)
    python rom_streams.py <rom> fe0 <stream_off> --blocks 0x24B9E0 --tiles out.png
"""
import sys
import os
import struct
import zlib

TILE = 32
VRAM_SZ = 0x10000
MASK_BUS = 0xFFFFFF


def words_be(rom, off, max_words=(1 << 30)):
    n = min(max_words, (len(rom) - off) // 2)
    return [(rom[i] << 8) | rom[i + 1] for i in range(off, off + n * 2, 2)]


# ------------------------------------------------------------------ 7be ----
def decode7be(rom, off, base=0, max_words=0x4000):
    """Algoritmo exacto de loc_0007be.

    (ops, n_words, end_pos): ops = lista de (dest_abs, auto, literales);
    n_words = palabras consumidas; end_pos = indice del $FFFF, o -1.
    Los streams reales son cortos: con 0x4000 words de tope no se pierde nada
    y no se lee medio ROM por cada llamada.
    """
    w = words_be(rom, off, max_words)
    ops = []
    stash, d1 = [], 0
    d4, d3 = 0, 0
    i = 0
    end = -1
    while i < len(w) and i < max_words:
        d7 = w[i]
        i += 1
        if not (d7 & 0x8000):
            stash.append(d7)
            d1 += 1
            continue
        if d7 == 0xFFFF:
            end = i - 1
            break
        if d1:
            ops.append((d4, d3, list(stash)))
        d4 = (d7 & 0x7FFF) + base
        if i >= len(w):
            break
        d3 = w[i]
        i += 1
        stash, d1 = [], 0
    if d1:
        ops.append((d4, d3, list(stash)))
    return ops, i, end


def apply_ops(ops, size=VRAM_SZ):
    v = bytearray(size)
    for dest, auto, lit in ops:
        addr = dest & (size - 1)
        for word in lit:
            if addr + 2 > size:
                break
            v[addr] = (word >> 8) & 0xFF
            v[addr + 1] = word & 0xFF
            addr = (addr + auto) & (size - 1)
    return v


# ------------------------------------------------------------------ fe0 ----
def decode_fe0(rom, off, blocks_base=0x24B9E0, max_words=(1 << 30)):
    """Codec loc_000fe0: words = indices de bloques de 128B.

    Devuelve (indices, n_words, end_pos) con fin en $FFFF.
    """
    w = words_be(rom, off)
    idx = []
    i = 0
    while i < len(w) and i < max_words:
        d7 = w[i]
        i += 1
        if not (d7 & 0x8000):
            idx.append(d7)
        elif d7 == 0xFFFF:
            break
        else:
            # $FFFC then andi #$7fff -> el juego trata el indice igual
            idx.append(d7 & 0x7FFF)
    return idx, i, i


def blocks_to_vram(rom, indices, blocks_base):
    """Copia los bloques de 128B consecutivos a una VRAM virtual (4 tiles c/u)."""
    v = bytearray(VRAM_SZ)
    pos = 0
    for k, idx in enumerate(indices):
        o = blocks_base + idx * 128
        if o + 128 > len(rom):
            break
        chunk = rom[o:o + 128]
        for t in range(4):
            a = pos + t * TILE
            v[a:a + TILE] = chunk[t * TILE:(t + 1) * TILE]
        pos += 128
    return v


# ---------------------------------------------------------------- render ----
def bgr555(c):
    if c == 0:
        return (0, 0, 0, 0)
    r = ((c & 0x000E) >> 1) * 255 // 7
    g = ((c & 0x00E0) >> 5) * 255 // 7
    b = ((c & 0x0E00) >> 9) * 255 // 7
    return (r, g, b, 255)


def write_png(path, rows):
    h = len(rows)
    w = len(rows[0]) if h else 0
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b, a = rows[y][x]
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)


def read_cram(path):
    d = open(path, "rb").read()
    raw = []
    for i in range(0, min(len(d), 128), 2):
        raw.append(struct.unpack(">H", d[i:i + 2])[0] & 0x0EEE)
    while len(raw) < 64:
        raw.append(0)
    return [bgr555(c) for c in raw]


def std_gray_pal():
    """64 colores (4 paletas de 16) para cuando no hay CRAM."""
    p = [(0, 0, 0, 0)]
    for i in range(1, 64):
        v = int(20 + i * 220 / 63)
        p.append((v, v, v, 255))
    return p


def tile_at(v, addr):
    filas = []
    for y in range(8):
        base = addr + y * 4
        px = []
        for b in v[base:base + 4]:
            px.append((b >> 4) & 0xF)
            px.append(b & 0xF)
        filas.append(px)
    return filas


def render_tile_sheet(v, pal, cols=16, zoom=2, min_t=0, max_t=None):
    nt = len(v) // TILE
    if max_t is None:
        max_t = nt
    w = cols * 8 * zoom
    rows_n = (max_t - min_t + cols - 1) // cols
    h = rows_n * 8 * zoom
    img = [[(0, 0, 0, 0)] * w for _ in range(h)]
    for i in range(min_t, min(max_t, nt)):
        t = tile_at(v, i * TILE)
        tx = ((i - min_t) % cols) * 8 * zoom
        ty = ((i - min_t) // cols) * 8 * zoom
        for y in range(8):
            for x in range(8):
                idx = t[y][x]
                if idx == 0:
                    continue
                r, g, b, a = pal[idx]
                for dy in range(zoom):
                    for dx in range(zoom):
                        img[ty + y * zoom + dy][tx + x * zoom + dx] = (r, g, b, a)
    return w, h, img


def render_nametable(v, pal, npx=64, npy=32, zoom=1):
    w = npx * 8 * zoom
    h = npy * 8 * zoom
    img = [[(0, 0, 0, 0)] * w for _ in range(h)]
    for ny in range(npy):
        for nx in range(npx):
            addr = (ny * npx + nx) * 2
            entry = (v[addr] << 8) | v[addr + 1]
            idx = entry & 0x7FF
            hflip = entry & 0x800
            vflip = entry & 0x1000
            pal_sel = (entry >> 13) & 3
            if idx >= len(v) // TILE:
                continue
            t = tile_at(v, idx * TILE)
            for y in range(8):
                for x in range(8):
                    sx, sy = x, y
                    if hflip:
                        sx = 7 - x
                    if vflip:
                        sy = 7 - y
                    ip = t[sy][sx]
                    if ip == 0:
                        continue
                    r, g, b, a = pal[pal_sel * 16 + ip]
                    for dy in range(zoom):
                        for dx in range(zoom):
                            img[ny * 8 * zoom + y * zoom + dy][nx * 8 * zoom + x * zoom + dx] = (r, g, b, a)
    return w, h, img


def fe0_layout(rom, indices, blocks_base, dest0, attr=0, cols_nt=64):
    """Reconstruye (vram, nt) tal como lo haria loc_000fe0 para `indices`.

    $1016 copia 128B (4 tiles lineales) desde $f5a0+idx*128 a VRAM en $f5a8 y
    $f5a8 avanza $80; $1054 escribe 4 words de nametable en el buffer $d200: dos
    arriba (offset 0 y +2) y dos abajo (offset $7e y $80), o sea cada bloque es
    una celda de 2x2 tiles (16x16 px).
    """
    v = bytearray(VRAM_SZ)
    dest = dest0
    nt = {}
    col = 0
    for idx in indices:
        o = blocks_base + idx * 128
        if o + 128 > len(rom):
            break
        v[dest:dest + 128] = rom[o:o + 128]
        t = (dest >> 5) & 0x7FF
        nt[0 * cols_nt + col * 2] = t | attr
        nt[0 * cols_nt + col * 2 + 1] = (t + 1) | attr
        nt[1 * cols_nt + col * 2] = (t + 2) | attr
        nt[1 * cols_nt + col * 2 + 1] = (t + 3) | attr
        col += 1
        dest = (dest + 0x80) & (VRAM_SZ - 1)
    return v, nt


def render_plano(v, nt, pal, cols_nt=64, ncells=5, zoom=1):
    """Renderiza una fila de `ncells` celdas 16x16 leidas del plano de nametable."""
    cw = 16 * ncells
    ch = 16
    img = [[(0, 0, 0, 0)] * cw for _ in range(ch)]
    for cell in range(ncells):
        cx = cell * 16
        for y in range(ch):
            for x in range(16):
                ntx = cell * 2 + (x // 8)
                nty = (y // 8)
                entry = nt.get(nty * cols_nt + ntx)
                if entry is None:
                    continue
                tile = entry & 0x7FF
                sel = (entry >> 13) & 3
                hflip = entry & 0x800
                vflip = entry & 0x1000
                tx, ty = x % 8, y % 8
                if hflip:
                    tx = 7 - tx
                if vflip:
                    ty = 7 - ty
                t = tile_at(v, tile * TILE)
                ip = t[ty][tx]
                if ip == 0:
                    continue
                r, g, b, a = pal[sel * 16 + ip]
                img[y][cx + x] = (r, g, b, a)
    return cw, ch, img
def autos_validos():
    return (2, 4, 8, 0x40, 0x80, 0x100, 0x200, 0x400)


def scan7be(rom, max_words=0x2000, min_lits=4, base=0, strict=True):
    """Busca streams 7be en todo el ROM.

    Criterio: inicio par con SET (bit15=1, !=$FFFF) seguido de un autoincremento
    plausible, y terminacion en $FFFF.

    `strict` (por defecto) exige ademas que TODOS los autoincrementos del stream
    sean plausibles. Sin eso el escaner se comia codigo 68000: los bytes de una
    instruccion como `RTS` ($4E75) caen en el filtro y dan streams falsos. Con
    el filtro laxo salen 944 candidatos; con el estricto, 221 reales.
    """
    found = []
    n = len(rom) - 2

    def w_be(pos):
        return (rom[pos] << 8) | rom[pos + 1]

    ok_auto = autos_validos()
    for pos in range(0, n, 2):
        a = w_be(pos)
        if not (a & 0x8000) or a == 0xFFFF:
            continue
        if pos + 3 >= len(rom):
            break
        if w_be(pos + 2) not in ok_auto:
            continue
        ops, nw, end = decode7be(rom, pos, base, max_words)
        lits = sum(len(w) for _, _, w in ops)
        if end < 0 or lits < min_lits:
            continue
        if strict and any(au not in ok_auto and au != 0 for _, au, _ in ops):
            continue
        found.append((pos, end, lits, ops[0][1] if ops else 0, lits))
    return found


def stream_tipo(ops):
    """Clasifica un stream: 'nametable', 'tiles' o 'mixto'.

    Medido sobre los 225 streams reales, no inventado. Hacen falta LAS DOS
    señales, y por separado ninguna basta:

    1) Autoincremento grande (> 8) = un word por fila de plano -> nametable.
       $100 = 256 B = una fila de 32 tiles; $80 = una fila de 64.
       Ej: $03A458 tiene auto $100 con 28 words: son 28 ENTRADAS往下 una
       columna, no pixeles. Renderizarlo como tiles sale vacio.

    2) Todos los literales con bits de atributo ($7800) y spread de indices
       < $400 -> tambien nametable, aunque el autoincremento sea 2.
       Ej: $34A00 (auto 2, spread 11, attr 1.00).

    Para pixels hace falta auto pequeno (contiguo) Y sin atributos:
       $004E66 (auto 2, spread 83, attr 0.00) -> 9 words = 18 bytes = casi un tile.
    """
    lits = [x for _, _, l in ops for x in l]
    if not lits:
        return "vacio"
    autos = [a for _, a, l in ops if l and a]
    lo11 = [x & 0x7FF for x in lits]
    spread = max(lo11) - min(lo11)
    attr = sum(1 for x in lits if x & 0x7800) / float(len(lits))
    if autos and max(autos) > 8:
        return "nametable"
    if attr == 1.0 and spread < 0x400:
        return "nametable"
    if attr <= 0.9:
        return "tiles"
    return "mixto"


def show_ops(ops, limit=12):
    tot = 0
    for k, (dest, auto, lit) in enumerate(ops[:limit]):
        tot += len(lit)
        print("  D%02d  dest=$%05X  auto=$%X  words=%d  ej=%s"
              % (k, dest, auto, len(lit), [hex(x) for x in lit[:6]]))
    if len(ops) > limit:
        print("  ... (%d ops mas)" % (len(ops) - limit))
    tot = sum(len(w) for _, _, w in ops)
    return tot


def usage():
    sys.exit(__doc__)


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        usage()
    rom_path = a[0]
    rom = open(rom_path, "rb").read()

    args = a[2:]

    def getval(flag, default=None):
        if flag in args:
            return args[args.index(flag) + 1]
        return default

    if a[1] == "fe0layout":
        off = int(args[0], 0)
        blocks = int(getval("--blocks", "0x24B9E0"), 0)
        dest = int(getval("--dest", "0xA000"), 0)
        attr = int(getval("--attr", "0"), 0)
        out_png = getval("--out")
        cram = getval("--cram")
        ncells = int(getval("--cells", "5"), 0)
        idx, nw, end = decode_fe0(rom, off, blocks)
        v, nt = fe0_layout(rom, idx, blocks, dest, attr)
        print("fe0 @$%X: %d bloques, dest $%04X" % (off, len(idx), dest))
        print("  indices: %s" % [hex(x) for x in idx])
        pal = read_cram(cram) if cram else std_gray_pal()
        w, h, img = render_plano(v, nt, pal, ncells=ncells)
        if out_png:
            write_png(out_png, img)
            print("  plano -> %s (%dx%d)" % (out_png, w, h))
        return 0

    if a[1] in ("--scan", "--scan7"):
        print("scan7be sobre %d bytes..." % len(rom))
        found = scan7be(rom)
        print("streams: %d  (filtro estricto: solo los que ademas tienen TODOS "
              "los autoincrementos plausibles)" % len(found))
        cuentas = {}
        for f in found:
            pos = f[0]
            ops, _, _ = decode7be(rom, pos, 0)
            t = stream_tipo(ops)
            cuentas[t] = cuentas.get(t, 0) + 1
        print("clasificacion: %s" % cuentas)
        print()
        for pos, end, lits, auto, _n in found[:100]:
            ops, _, _ = decode7be(rom, pos, 0)
            print("  $%06X  end+$%04X  lits=%4d auto=%-5s  %s"
                  % (pos, end, lits, hex(auto), stream_tipo(ops)))
        return 0

    if a[1] == "fe0":
        if len(args) < 1:
            usage()
        off = int(args[0], 0)
        blocks = int(getval("--blocks", "0x24B9E0"), 0)
        out_tiles = getval("--tiles")
        out_vram = getval("--vram")
        cram = getval("--cram")
        idx, nw, end = decode_fe0(rom, off, blocks)
        print("fe0 stream $%X: %d indices (n=%d)" % (off, len(idx), nw))
        print("  indices ej: %s" % [hex(x) for x in idx[:24]])
        v = blocks_to_vram(rom, idx, blocks)
        pal = read_cram(cram) if cram else std_gray_pal()
        if out_vram:
            open(out_vram, "wb").write(v)
            print("  VRAM -> %s" % out_vram)
        if out_tiles:
            w, h, img = render_tile_sheet(v, pal)
            write_png(out_tiles, img)
            print("  tiles -> %s (%dx%d)" % (out_tiles, w, h))
        return 0

    off = int(a[1], 0)
    base = int(getval("--base", "0"), 0)
    out_vram = getval("--vram")
    out_tiles = getval("--tiles")
    out_nam = getval("--nametable")
    cram = getval("--cram")

    ops, nw, end = decode7be(rom, off, base)
    print("stream %s @$%X  base=$%X" % (os.path.basename(rom_path), off, base))
    print("  %d operaciones DMA, %d palabras ROM, fin=%s"
          % (len(ops), nw, "$FFFF" if end >= 0 else "? (sin fin)"))
    tot = show_ops(ops)
    print("  literales totales: %d words (%.1f tiles 8x8 4bpp)"
          % (tot, tot * 2.0 / TILE))

    pal = read_cram(cram) if cram else std_gray_pal()
    v = apply_ops(ops)
    if out_vram:
        open(out_vram, "wb").write(v)
        print("  VRAM -> %s" % out_vram)
    if out_nam:
        w, h, img = render_nametable(v, pal)
        write_png(out_nam, img)
        print("  nametable -> %s (%dx%d)" % (out_nam, w, h))
    if out_tiles:
        w, h, img = render_tile_sheet(v, pal)
        write_png(out_tiles, img)
        print("  tiles -> %s (%dx%d)" % (out_tiles, w, h))
    return 0


if __name__ == "__main__":
    sys.exit(main())