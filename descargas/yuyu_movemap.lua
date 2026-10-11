--[[
  yuyu_movemap.lua — MAPEO BOTON -> MOVE ID  (Yu Yu Hakusho: Makyou Toitsusen)

  Para que sirve:
    Saber que golpe es cada entrada. Ej: A parado = move ID $xx, ->+A = $yy,
    A en el aire = $zz. El movimiento que EJECUTA el juego va en $FF8400+$5F.

  Como se usa:
    1. Fightcade: carga el ROM y entra a un combate (entrenador si podes).
       Selecciona el personaje que quieras mapear.
    2. Game > Lua Scripting > New Lua Script Window > Browse > yuyu_movemap.lua
    3. MODE  -> arranca a registrar en consola  (imprime "[map] grabando...").
    4. Hace la entrada que quieras: A, ->+A, A en el aire, agachado+A, etc.
    5. MODE de nuevo -> para y vuelca el resumen final.
    En todo momento la pantalla muestra (overlay) el move ID actual y los
    botones que estan apretados, asi ves en vivo que entrada produjo que move.

  Salida:
    - Por cada cambio de move ID, una linea con: contexto (personaje), move ID
      (hex+dec), direccion + botones que habia apretados, si es nuevo boton
      (flamco), frame de animacion, Y de mundo, flag aire, y la velocidad Y.
    - Las lineas marcadas "auto" son cambios SIN entrada del jugador
      (transiciones de estado: caer, pararse, hitstun). Ignorarlas cuando
      estes sacando el mapeo de botones.

  ESTE SCRIPT ES PASIVO: NO ESCRIBE NI UN SOLO BYTE EN LA MEMORIA DEL JUEGO.
  Solo lee (memory.read*) y escribe por print / gui.text.
--]]

local TARGET  = "md_yuyumte"

-- Slot de P1. P2 en $FF9000 (stride $C00); este script solo mapea P1.
local P1 = 0xFF8400

local rb  = memory.readbyte
local rw  = memory.readword
local rws = memory.readwordsigned
local rl  = memory.readdword

-- Offsets del struct (verificado en game_68000.asm / yuyu_probe.lua)
local O = {
  FRAME  = 0x59,   -- indice de frame de animacion
  DUR    = 0x5A,   -- duracion del frame actual
  MOVE   = 0x5F,   -- id de move (lo que queremos mapear)
  FACING = 0x61,
  VY     = 0x2A,   -- velocidad Y (word signed) -> 0xA0 es stand
  WX     = 0x40,   -- X mundo (word bajo del long)
  WY     = 0x44,   -- Y mundo
  T50    = 0x50,   -- puntero a la tabla de frames  (identifica contexto)
  T8C    = 0x8C,   -- puntero a la tabla de moves/hit (identifica contexto)
}

-- Bases de la tabla $50 por contexto (GUIA_TECNICA seccion 7). Sirve para
-- saber QUE personaje esta en pantalla comparando el puntero que tiene $50.
local CTX50 = {
  [0x00BF75A] = 1,  [0x0C229A] = 2,  [0x0C4EEA] = 3,  [0x0C7C9A] = 4,
  [0x0CA6DA] = 5,  [0x0CCC7A] = 6,  [0x0CF99A] = 7,  [0x0D1E5A] = 8,
  [0x0D4A9A] = 9,  [0x0D777A] = 10, [0x0BCAAA] = 11, [0x0D92CA] = 12,
}

-- Botones de P1 (Fightcade mapea a "P1 Button X/Y/Z")
local KEYS = {
  { name = "A", key = "P1 Button A" },
  { name = "B", key = "P1 Button B" },
  { name = "C", key = "P1 Button C" },
  { name = "X", key = "P1 Button X" },
  { name = "Y", key = "P1 Button Y" },
  { name = "Z", key = "P1 Button Z" },
}

-------------------------------------------------------------------------------
-- Estado
-------------------------------------------------------------------------------

local recording  = false
local prev_mode  = false
local prev_move  = nil
local prev_pad   = {}
local gnd_ref    = nil     -- Y de mundo del suelo (se calibra solo)
local logrows    = {}      -- {line, ...} para el resumen final
local auto_count = 0
local man_count  = 0

-------------------------------------------------------------------------------
-- Entrada
-------------------------------------------------------------------------------

local function is_pressed(pad, key)
  local v = pad[key]
  return v and true or false
end

-- Direccion como simbolo (prioriza vertical igual que yuyu_combo_rec)
local function read_dir(pad)
  local u = is_pressed(pad, "P1 Up")
  local d = is_pressed(pad, "P1 Down")
  local l = is_pressed(pad, "P1 Left")
  local r = is_pressed(pad, "P1 Right")
  if u and d then return "v" end
  if l and r then return "h" end
  if u and l then return "UL" end
  if u and r then return "UR" end
  if d and l then return "DL" end
  if d and r then return "DR" end
  if u then return "U" end
  if d then return "D" end
  if l then return "L" end
  if r then return "R" end
  return "."
end

-- Botones apretados en este frame, y cuales son nuevos (flamco de subida)
local function read_btns(pad, prev)
  local held, fresh = {}, {}
  for i = 1, #KEYS do
    local K = KEYS[i]
    if is_pressed(pad, K.key) then
      held[#held + 1] = K.name
      if not is_pressed(prev or {}, K.key) then
        fresh[#fresh + 1] = K.name
      end
    end
  end
  return table.concat(held, ""), table.concat(fresh, "")
end

-------------------------------------------------------------------------------
-- Contexto (personaje) desde el puntero de $50
-------------------------------------------------------------------------------

local function context()
  local p = rl(P1 + O.T50)
  -- el puntero puede venir como $00BF75A o $FF8250; normalizar a 24 bits
  p = bit.band(p, 0xFFFFFF)
  return CTX50[p] or "?"
end

-------------------------------------------------------------------------------
-- Deteccion de aire
--
-- Se calibra solo: el suelo es el Y de mundo mas grande observado con el
-- personaje quieto (vy ~ 0). Air = Y claramente por encima de ese suelo.
-------------------------------------------------------------------------------

local function in_air(wy, vy)
  if gnd_ref and wy < gnd_ref - 6 then return true end
  return false
end

local function calibrate(wy, vy)
  if not gnd_ref then
    gnd_ref = wy
  elseif vy == 0 and wy > gnd_ref then
    gnd_ref = wy
  end
end

-------------------------------------------------------------------------------
-- Reporte por cambio de move
-------------------------------------------------------------------------------

local function on_move_change(move)
  local pad = joypad.get()
  local held, fresh = read_btns(pad, prev_pad)
  local dir = read_dir(pad)
  local wy  = rws(P1 + O.WY)
  local vy  = rws(P1 + O.VY)
  local fr  = rb(P1 + O.FRAME)
  local du  = rb(P1 + O.DUR)
  local ctx = context()
  local air = in_air(wy, vy)
  calibrate(wy, vy)

  -- Sin direccion y sin botones = transicion automatica (ej: hitstun)
  local is_auto = (dir == ".") and (#held == 0)
  if is_auto then auto_count = auto_count + 1 else man_count = man_count + 1 end

  local tag = ""
  if #fresh > 0 then tag = "  new=" .. fresh end
  local airs = air and "AIR" or "grnd"
  if recording then
    local line = string.format(
      "[map] ctx=%s mv=$%02X(%d) in=%s%s%s  y=%d  vy=%3d  f%02d/%02d  %s%s",
      tostring(ctx), move, move, dir, held:len() > 0 and "+" .. held or "",
      tag, wy, vy, fr, du, airs, is_auto and "  auto" or "")
    logrows[#logrows + 1] = line
    print(line)
  end
end

-------------------------------------------------------------------------------
-- Overlay en pantalla (siempre vivo, aunque no se este grabando)
-------------------------------------------------------------------------------

local function overlay()
  local move = rb(P1 + O.MOVE)
  local pad  = joypad.get()
  local held, _ = read_btns(pad, {})
  local dir  = read_dir(pad)
  local wy   = rws(P1 + O.WY)
  local vy   = rws(P1 + O.VY)
  local air  = in_air(wy, vy)
  local ctx  = context()
  local fr   = rb(P1 + O.FRAME)

  gui.text(4, 2,
    string.format("[movemap] ctx=%s  move=$%02X(%d)  f%02d",
      tostring(ctx), move, move, fr), 0xFFFFFFFF)
  gui.text(4, 12,
    string.format("  in=%s%s  y=%d  %s%s",
      dir, held:len() > 0 and "+" .. held or "", wy,
      air and "AIR" or "grnd", recording and "  <GRABANDO>" or ""),
    0xFFFFFFFF)
end

-------------------------------------------------------------------------------
-- Cada frame
-------------------------------------------------------------------------------

local function tick()
  local pad = joypad.get()
  local mode = is_pressed(pad, "P1 Mode")

  if mode and not prev_mode then
    recording = not recording
    if recording then
      logrows = {}
      auto_count, man_count = 0, 0
      print("[map] grabando...  MODE de nuevo para parar")
    else
      print(string.format("[map] detenido. %d eventos (%d manuales, %d auto).",
            #logrows, man_count, auto_count))
      for i = 1, #logrows do
        print(logrows[i])
      end
      print("[map] fin del resumen")
    end
  end
  prev_mode = mode

  local mv = rb(P1 + O.MOVE)
  if mv ~= prev_move then
    if prev_move ~= nil then
      on_move_change(mv)
    end
    prev_move = mv
  end

  -- guardar estado de botones para el flamco del proximo frame
  prev_pad = pad
end

-------------------------------------------------------------------------------
-- Arranque
-------------------------------------------------------------------------------

local rom = emu.romname()
if tostring(rom) ~= TARGET then
  print(string.format("[map] aviso: rom actual '%s', esperado '%s'.",
        tostring(rom), TARGET))
end

emu.registerafter(function()
  tick()
  overlay()
end)

print("[map] movemap listo. MODE = grabar/parar. Mapea P1 en $FF8400.")