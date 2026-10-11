--[[
  yuyu_probe.lua — Sondea el sistema de colisiones de Yu Yu Hakusho:
  Makyou Toitsusen (Mega Drive) desde FBNeo / Fightcade.

  Uso:
    Game > Lua Scripting > New Lua Script Window > Browse > yuyu_probe.lua
    Arrancar el juego y entrar a un combate.

  Que hace:
    - Se engancha en $01EDAC (entrada del dispatcher de colisiones) para leer
      los 5 contadores de lista ANTES de que el juego los ponga a cero.
    - Dibuja un overlay de texto y las cajas por pantalla.
    - Imprime en consola SOLO cuando algo cambia de valor (eventos), para no
      inundar la consola de Fightcade.

  NO escribe nada en la memoria del juego: es 100% pasivo.

  Para el remake y para el script final, las conclusions estan en
  COLISIONES_Y_HITBOXES.md
--]]

local TARGET  = "md_yuyumte"
local HOOK_PC = 0x01EDAC

-- Slots de jugador. P1 en $FF8400, P2 en $FF8800, stride $400.
local P1 = 0xFF8400
local P2 = 0xFF8800

local rb  = memory.readbyte
local rw  = memory.readword
local rws = memory.readwordsigned

-- Offsets del struct del jugador (sobre la base del slot)
local OFF_SCREEN_X, OFF_SCREEN_Y = 0x08, 0x0C
local OFF_WX,       OFF_WY       = 0x40, 0x44
local OFF_PUSH_X,   OFF_PUSH_Y   = 0x54, 0x56
local OFF_VX,       OFF_VY       = 0x28, 0x2A
local OFF_FRAME,    OFF_DUR      = 0x59, 0x5A
local OFF_TICK                    = 0x5B
local OFF_MOVE                    = 0x5F
local OFF_SCALE                   = 0x3E
local OFF_FACING                  = 0x61
local OFF_HITPAUSE                = 0x69
local OFF_HP                      = 0x78   -- HP real, word SIGNED, max 255
local OFF_HP_BAR                  = 0x7A   -- valor visible: persigue a $78
local OFF_MP                       = 0xB8   -- energia/TA gastable, NO HP
local OFF_STUN, OFF_STUN_MAX     = 0x7E, 0x80
local OFF_GAUGE                  = 0x7C   -- se rellena 0->$FF y se usa como offset de puntero (0x1AA26)

-- Globales
local CAM_X, CAM_Y   = 0xFFF408, 0xFFF40A
local STAGE_X, STAGE_Y = 0xFFA014, 0xFFA016
local VSCROLL         = 0xFFF566

-- Listas: base, contador, stride, nombre
local LISTS = {
  { name = "hit", base = 0xFFA200, cnt = 0xFFA004, stride = 0x10 },
  { name = "clsh", base = 0xFFA300, cnt = 0xFFA006, stride = 0x10 },
  { name = "hurt", base = 0xFFA400, cnt = 0xFFA008, stride = 0x10 },
  { name = "push", base = 0xFFA500, cnt = 0xFFA00A, stride = 0x10 },
  { name = "grab", base = 0xFFA600, cnt = 0xFFA00C, stride = 0x20 },
}

-- Cuantas cajas se muerde de cada lista en el overlay
local MAX_SHOWN = 3

local COLOR = {
  hit  = { 0x40FF4040, 0xFFFF6060 },
  clsh = { 0x40C0C040, 0xFFC0C040 },
  hurt = { 0x4040C0FF, 0xFF80A0FF },
  push = { 0x4040E060, 0xFF60E060 },
  grab = { 0x50E040E0, 0xFFE040E0 },
}

--------------------------------------------------------------------------------
-- Utilidades
--------------------------------------------------------------------------------

local function hex(v, n)
  if not v then return "?" end
  return string.format("%0" .. (n or 4) .. "X", bit.band(v, 0xFFFFFFFF))
end

-- El owner NO se guarda completo. El builder hace "move.w a5" (0x01EC40,
-- 0x01EC9E, 0x01ECFC, 0x01ED5A y 0x0161BE), asi que el campo +$C solo
-- contiene el WORD BAJO de la base: $8400 para P1 y $8800 para P2.
local function own_lo(v)
  return bit.band(v, 0xFFFF)
end

local function owner_base(v)
  local lo = own_lo(v)
  if lo == own_lo(P1) then return P1 end
  if lo == own_lo(P2) then return P2 end
  return nil
end

-- Los contadores son offsets EN BYTES dentro de la lista, no cantidades.
-- El builder los satura en $F0, asi que el maximo real son 15 cajas.
local function box_count(counter, stride)
  if counter <= 0 then return 0 end
  return math.min(math.floor(counter / stride), 0xF0 / stride)
end

--------------------------------------------------------------------------------
-- Estado cacheado por el hook
--------------------------------------------------------------------------------

local snap = {
  counts = { 0, 0, 0, 0, 0 },
  bytes  = { 0, 0, 0, 0, 0 },
  seen   = false,
  via_wr = false,
  frame  = -1,
  last   = {},
}

local ROM = "(sin leer)"

local function on_dispatch()
  for i = 1, #LISTS do
    local c = rw(LISTS[i].cnt)
    snap.bytes[i] = c
    snap.counts[i] = box_count(c, LISTS[i].stride)
  end
  snap.seen   = true
  snap.via_wr = false
end

-- Fallback por escritura: el dispatcher borra los contadores al final del
-- frame, asi que si el exec hook no dispara solo queda interceptar la
-- escritura. Se ignoran las escrituras a 0 (son el borrado final) y se
-- sella con el numero de frame para no reutilizar datos viejos.
local function on_counter_write(addr, val)
  if val == nil or val <= 0 then return end
  for i = 1, #LISTS do
    local L = LISTS[i]
    if addr == L.cnt or addr == (L.cnt - 0xFF0000) then
      snap.bytes[i]  = val
      snap.counts[i] = box_count(val, L.stride)
      snap.via_wr    = true
      snap.frame     = emu.framecount()
      return
    end
  end
end

--------------------------------------------------------------------------------
-- Lectura de una caja
--------------------------------------------------------------------------------

local function read_box(list, idx)
  local a = list.base + idx * list.stride
  local b = {
    addr  = a,
    x     = rws(a + 0x00),
    y     = rws(a + 0x04),
    owner = rw(a + 0x0C),
  }
  if list.stride == 0x20 then
    -- Descriptor de grab / special hit (consumido por $01EEE2)
    b.rx     = rb(a + 0x04)
    b.ry     = rb(a + 0x05)
    b.moveid = rb(a + 0x06)
    b.param  = rb(a + 0x08)
    b.facing = rb(a + 0x0A)
    b.knockx = rws(a + 0x10)
    b.knocky = rws(a + 0x12)
  else
    -- Lista normal de 16 bytes
    b.rx    = rb(a + 0x08)
    b.ry    = rb(a + 0x09)
    b.last  = bit.band(b.rx, 0x80) ~= 0   -- bit 7 = terminador de lista
    b.rx    = bit.band(b.rx, 0x7F)
  end
  return b
end

--------------------------------------------------------------------------------
-- Overlay de texto
--------------------------------------------------------------------------------

-- Se declaran aqui porque build_overlay las usa y las funciones estan mas
-- abajo, en la seccion de conversion. Sin esto Lua las busca como globales.
local player_screen, to_screen

local lines = {}

local function build_overlay()
  local n = 0
  local function add(s)
    n = n + 1
    lines[n] = s
  end

  local cam_x, cam_y = rw(CAM_X), rw(CAM_Y)
  local stg_x, stg_y = rw(STAGE_X), rw(STAGE_Y)
  local vscr        = rws(VSCROLL)

  local hp   = rws(P1 + OFF_HP)
  local hpbar = rws(P1 + OFF_HP_BAR)
  local mp   = rw(P1 + OFF_MP)
  local stun = rw(P1 + OFF_STUN)
  local smax = rw(P1 + OFF_STUN_MAX)

  add(string.format("P1  hp=%d(bar %d)  mana=%d  stun=%s/%s  move=$%02X(%d)  face=%s  hitstop=%d",
    hp, hpbar, mp, tostring(stun), tostring(smax), rb(P1 + OFF_MOVE), rb(P1 + OFF_MOVE),
    rb(P1 + OFF_FACING) == 0 and "R" or "L", rb(P1 + OFF_HITPAUSE)))
  local sx, sy = player_screen(P1)
  add(string.format("    scr(clamp)=$%X,$%X  scr(calc)=$%d,$%d  world=$%X,$%X",
    rw(P1 + OFF_SCREEN_X), rw(P1 + OFF_SCREEN_Y), sx, sy,
    rw(P1 + OFF_WX), rw(P1 + OFF_WY)))
  add(string.format("    push=%d,%d  v=%d,%d  sc=%d  stage=$%X,$%X vscr=%d",
    rws(P1 + OFF_PUSH_X), rws(P1 + OFF_PUSH_Y),
    rws(P1 + OFF_VX), rws(P1 + OFF_VY),
    rw(P1 + OFF_SCALE), stg_x, stg_y, vscr))
  add(string.format("    anim frame=$%X dur=$%X tick=$%X",
    rb(P1 + OFF_FRAME), rb(P1 + OFF_DUR), rb(P1 + OFF_TICK)))
  add(string.format("cam=$%X,$%X  stage=$%X,$%X  vscroll=$%X",
    cam_x, cam_y, stg_x, stg_y, vscr))

  -- Estado del hook: si no fired, casi siempre es que no hay combate.
  if not snap.seen then
    add(string.format("hook $%06X %s | counters=%s | rom=%s",
      HOOK_PC, snap.via_wr and "exec NO, write OK" or "exec NO, write NO",
      snap.via_wr and "capturados" or "sin datos", tostring(ROM)))
  end

  for i = 1, #LISTS do
    local L = LISTS[i]
    add(string.format("%-4s cnt=$%X (%d)  disp(%d,%d)",
      L.name, snap.bytes[i], snap.counts[i], snap.counts[i], L.stride))
  end

  for i = 1, #LISTS do
    local L = LISTS[i]
    local cnt = snap.counts[i]
    if cnt > 0 then
      for k = 0, math.min(cnt, MAX_SHOWN) - 1 do
        local b = read_box(L, k)
        local ob = owner_base(b.owner) or P1
        local sx, sy = to_screen(ob, b.x, b.y)
        if L.stride == 0x20 then
          add(string.format("  %s[%d] scr=%d,%d r=%d,%d own=$%s mid=$%02X fc=%d k=%d,%d",
            L.name, k, sx, sy, b.rx, b.ry, hex(b.owner), b.moveid, b.facing,
            b.knockx, b.knocky))
        else
          add(string.format("  %s[%d] scr=%d,%d r=%d,%d own=$%X%s",
            L.name, k, sx, sy, b.rx, b.ry, hex(b.owner),
            b.last and " LAST" or ""))
        end
      end
    end
  end

  return n
end

--------------------------------------------------------------------------------
-- Conversion caja -> pantalla
--
-- NO usar "box - camara": loc_0156F0 calcula $08 = world_x - $A014 + $80, con
-- $A014 = $360. Falta un termino de ~736 pixeles, y las cajas se dibujan
-- muy lejos de la pantalla. Como el builder escribe box.x = world_x + vel_x +
-- (offset - $80), la conversion correcta es un anclaje sobre el personaje:
--   screen = $08 + (box.x - world_x)
--------------------------------------------------------------------------------

local OFF_WX_LO, OFF_WY_LO = 0x40, 0x44

-- $08/$0C son la posicion en pantalla PERO CLAMPADA (loc_0156F0, 0x15700 y
-- 0x15730: X a [0x40..0x1FF], Y a [0x40..0x1C0] menos 8). En cuanto el
-- personaje se sale de esa caja -- un doble salto abajo a la derecha -- el
-- valor se satura y todo lo que se ancle a el se queda corrido arriba a la
-- izquierda mientras el sprite sigue de largo. Por eso NO se usan $08/$0C:
-- se recalcula la misma formula SIN clamp y sin el offset de empuje.
function player_screen(base)
  local wx = rw(base + OFF_WX_LO)
  local wy = rw(base + OFF_WY_LO)
  return wx - rw(STAGE_X) + 0x80,
         wy - rw(STAGE_Y) + rws(VSCROLL) + 0x20 - 8
end

function to_screen(owner, bx, by)
  local base = owner_base(owner) or P1
  local ax, ay = player_screen(base)
  return ax + (bx - rw(base + OFF_WX_LO)), ay + (by - rw(base + OFF_WY_LO))
end

--------------------------------------------------------------------------------
-- Cuadricula de referencia
--
-- Sirve para posicionar el HUD y las cajas con numeros, no a ojo. Cada interseccion
-- tiene su coordenada escrita, en pixeles DE PANTALLA de FBNeo.
--
-- Para lo que esta en coordenadas de JUEGO (cajas, cruz, posicion del
-- personaje) el overlay de texto imprime los valores: son esos los que hay que
-- mirar, porque la cuadricula esta en coordenadas de pantalla.
--------------------------------------------------------------------------------

local GRID_STEP = 16
local SHOW_GRID = false    -- hay que ponerlo en true para posicionar el HUD
local GRID_COL  = 0x30FFFFFF
local GRID_COL_M = 0x80FF4040
local GRID_TXT  = 0xFF60FF60

local function draw_grid()
  if not SHOW_GRID then return end
  local sw, sh = emu.screenwidth(), emu.screenheight()
  for x = 0, sw, GRID_STEP do
    local major = (x % 64) == 0
    gui.drawline(x, 0, x, sh, major and GRID_COL_M or GRID_COL)
    if major then gui.text(x + 1, 1, tostring(x), GRID_TXT) end
  end
  for y = 0, sh, GRID_STEP do
    local major = (y % 64) == 0
    gui.drawline(0, y, sw, y, major and GRID_COL_M or GRID_COL)
    if major then gui.text(1, y + 1, tostring(y), GRID_TXT) end
  end
end

--------------------------------------------------------------------------------
-- Dibujo
--------------------------------------------------------------------------------

local function draw()
  -- Fuente de datos por prioridad:
  --   1) exec hook  ($01EDAC)
  --   2) write hook (contadores), solo si es de este frame
  --   3) lectura directa (solo sirve si el dispatcher todavia no borro)
  if not snap.seen then
    if snap.via_wr and snap.frame == emu.framecount() then
      snap.seen = true          -- dato write de este frame: es tan bueno
    else
      for i = 1, #LISTS do
        local c = rw(LISTS[i].cnt)
        snap.bytes[i] = c
        snap.counts[i] = box_count(c, LISTS[i].stride)
      end
      snap.via_wr = false
      snap.frame  = -1
    end
  end

  for i = 1, #LISTS do
    local L = LISTS[i]
    local col = COLOR[L.name]
    local cnt = snap.counts[i]
    for k = 0, cnt - 1 do
      local b = read_box(L, k)
      local ob = owner_base(b.owner)
      if ob == P1 then
        local sx, sy = to_screen(P1, b.x, b.y)
        gui.box(sx - b.rx, sy - b.ry, sx + b.rx, sy + b.ry, col[1], col[2])
      end
    end
  end

  -- Cruz de la altura del personaje: posicion SIN clamp (ver player_screen).
  local px, py = player_screen(P1)
  gui.drawline(px - 10, py, px + 10, py, 0xFFFFFFFF)
  gui.drawline(px, py - 10, px, py + 10, 0xFFFFFFFF)
  -- Esquina de la caja logica del jugador, para ver de cuanto se separa.
  local bw, bh = 24, 48
  gui.box(px - bw, py - bh, px + bw, py, 0x00000000, 0xFF60FF60)
  gui.text(px + bw + 2, py - 1, string.format("%d,%d", px, py), 0xFFFFFFFF)
  draw_grid()

  local n = build_overlay()
  for i = 1, n do
    gui.text(4, 2 + (i - 1) * 9, lines[i], 0xFFFFFFFF)
  end
end

--------------------------------------------------------------------------------
-- Consola: solo cuando algo cambia
--------------------------------------------------------------------------------

local function check_changes()
  local cur = string.format("%d|%d|%d|%d|%d|%d|%d|%d",
    rws(P1 + OFF_HP), rw(P1 + OFF_MP), rb(P1 + OFF_MOVE),
    snap.bytes[1], snap.bytes[2], snap.bytes[3], snap.bytes[4],
    rw(P1 + OFF_GAUGE))
  if cur ~= snap.last then
    if snap.last ~= nil then
      print(string.format(
        "[yuyu] hp=%d(bar %d) mana=%d stun=%d/%d mv=$%02X $7c=%d | bytes hit=$%X clsh=$%X hurt=$%X push=$%X grab=$%X",
        rws(P1 + OFF_HP), rws(P1 + OFF_HP_BAR), rw(P1 + OFF_MP),
        rw(P1 + OFF_STUN), rw(P1 + OFF_STUN_MAX),
        rb(P1 + OFF_MOVE), rw(P1 + OFF_GAUGE),
        snap.bytes[1], snap.bytes[2], snap.bytes[3], snap.bytes[4], snap.bytes[5]))
    end
    snap.last = cur
  end
end

--------------------------------------------------------------------------------
-- Arranque
--------------------------------------------------------------------------------

local rom = emu.romname()
ROM = tostring(rom)
if rom ~= TARGET then
  print(string.format("[yuyu] aviso: rom actual '%s', esperado '%s'. Las direcciones pueden no aplicar.", tostring(rom), TARGET))
end

-- FBNeo borra los hooks exec en cada reset: hay que re-armarlo cada frame.
-- Los write hooks se registran en las DOS direcciones: la que usa el 68000
-- ($00A0xx) y el espejo de FBNeo ($FFA0xx). Registrar solo el espejo es
-- lo que fallaba antes.
local function arm_hook()
  if memory.registerexec then
    memory.registerexec(HOOK_PC, on_dispatch)
  else
    print("[yuyu] aviso: este build de FBNeo no expone memory.registerexec")
  end
  if memory.registerwrite then
    for i = 1, #LISTS do
      local c = LISTS[i].cnt
      memory.registerwrite(c, 2, on_counter_write)
      memory.registerwrite(c - 0xFF0000, 2, on_counter_write)
    end
  end
end

arm_hook()
if emu.registerstart then emu.registerstart(arm_hook) end

emu.registerafter(function()
  arm_hook()
  draw()
  -- El snapshot es de UN frame: se invalida para que el proximo frame
  -- capture sus propios contadores.
  snap.seen = false
  check_changes()
end)

print(string.format("[yuyu] probe listo. rom=%s hook=$%06X", tostring(rom), HOOK_PC))