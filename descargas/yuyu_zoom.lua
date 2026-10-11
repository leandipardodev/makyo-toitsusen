--[[
  yuyu_zoom.lua - ZOOM OUT  (Yu Yu Hakusho: Makyou Toitsusen)

  PARA QUE SIRVE
  --------------
  Hacer zoom out de verdad, porque el juego TIENE un campo de escala: `$3E`.

      $100 = 1.0 (normal)
      $D8  = 0.84, $C8 = 0.78  (los usa el juego en sus efectos)
      (x - $40) * $3E >> 8     (0x1ED8 X, 0x1EFC Y, 0x1646, 0x1686)

  El juego lo vuelve a poner en $100 constantemente, asi que hay que
  re-imponerlo igual que la camara: con un write hook sobre cada $3E.
  Cada vez que el juego escribe el zoom de un objeto, se lo reescribimos.

  OJO, QUE NO ES UN REESCALADO DE PIXELES: los tiles siguen igual de
  grandes, solo se juntan mas. A $80 las piezas se solapan. Es el mismo
  truco que usa el juego para sus efectos de zoom, asi que se ve raro pero
  no roto. Ademas, mientras este armado, se pisan los zoom de los efectos
  del juego.

  COMO SE USA
  -----------
  1. Fightcade, en un combate.
  2. Game > Lua Scripting > New Lua Script Window > Browse > este fichero.
  3. Teclas (de P2, para no chocar con el juego):
       P2 Button A     armar / desarmar  (tambien P1 Mode)
       P2 Left / Right zoom mas pequeno / mas grande (pasos de $20)
       P2 Button B     volver a $100 y desarmar
       P2 Button C     ver / ocultar la lista de objetos detectados

  QUE SON LOS "OBJETOS"
  ---------------------
  Las bases no son un array: el codigo las crea una a una con
  `lea.l $XXXX.w,a0` en 19 sitios distintos. Por eso este script NO las
  busca en el codigo, sino que **rastrea la RAM**: recorre
  $FF8000..$FFFC0 en pasos de $40 y se queda con las que parece un objeto
  (zoom valido + indice de animacion + id de move con sentido). Los
  jugadores son $FF8400 y $FF9000, y estan dentro de los detectados.

  La lista sale en el panel para poder comprobar que no se cuela nada.
  Si ves una base rara, quitala de la tabla OBJ_IGNORAR.

  AVISO
  -----
  ESCRIBE en la memoria del juego (AGENTS.md, regla 5). Instrumento de
  diagnostico: solo escribe cuando lo armas, y solo un word por objeto.
  No escribe nunca en un replay.
--]]

local TARGET = "md_yuyumte"

-- Struct del jugador (los offsets valen para cualquier objeto)
local O_ZOOM = 0x3E   -- escala, $100 = 1.0
local O_ANIM = 0x3C   -- indice de animacion x2
local O_MOVE = 0x5F   -- id de move
local O_FRAME= 0x59   -- indice de frame

local RAM_A, RAM_B = 0xFF8000, 0xFFA200
local RAM_STEP     = 0x20
local ZMIN, ZMAX   = 0x20, 0x100   -- rango que dejamos (12.5% .. 100%)
local ZSTEP        = 0x20
local ZDEF         = 0x100

-- Bases que se sabe que NO son objetos (ruido). Vacio de momento.
local OBJ_IGNORAR = {}

--------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------

local rb  = memory.readbyte
local rw  = memory.readword
local ww  = memory.writeword
local has_write = (memory.writeword ~= nil)
local has_hook  = (memory.registerwrite ~= nil)

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function hex(v) return string.format("$%04X", rw(v)) end
local function pct(z) return tostring(math.floor(z * 100 / 256)) .. "%" end

local function log(s) print("[zoom] " .. s) end

--------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------

local armado  = false
local zoom    = ZDEF
local busy    = false
local objs    = {}          -- bases detectadas
local hooked  = {}          -- direccion de $3E -> true (ya enganchada)
local ver_lista = true
local n_wr    = 0           -- escrituras interceptadas en el frame
local wr_tot  = {}          -- direccion -> escrituras acumuladas
local frames  = 0
local prev_pad = {}

--------------------------------------------------------------------------
-- Deteccion de objetos
--------------------------------------------------------------------------

-- Un valor "de zoom" es uno de los que el juego usa de verdad: 0, multiplos de
-- $20 entre $20 y $100, o los dos atajos $D8 (0.84) y $C8 (0.78).
local function valor_de_zoom(v)
  if v == 0 then return true end
  if v >= 0x20 and v <= 0x100 and (v % 0x20) == 0 then return true end
  if v == 0xD8 or v == 0xC8 then return true end
  return false
end

-- Rango de Bases de objeto segun los `lea.l $XXXX.w,a0` del codigo:
-- $8000-$83FF, $8400-$8FFF, $9100-$9FFF, $A100-$A180. Fuera de ahi solo hay
-- listas de cajas ($A2xx-$A6xx), punteros de entidad ($A8xx), buffers
-- ($E000-$EAFF) y globales del VDP ($F000-$FFFF).
local function base_probable(base)
  local b = base - 0xFF0000
  if b >= 0x8000 and b <= 0xAFFF then return true end
  if b >= 0xB000 and b <= 0xDFFF then return true end
  return false
end

local function parece_objeto(base)
  if not base_probable(base) then return false end
  if not valor_de_zoom(rw(base + O_ZOOM)) then return false end
  for i = 1, #OBJ_IGNORAR do
    if OBJ_IGNORAR[i] == base then return false end
  end
  return true
end

local function escanear()
  local nuevo = {}
  for base = RAM_A, RAM_B, RAM_STEP do
    if parece_objeto(base) then nuevo[#nuevo + 1] = base end
  end
  local antes = #objs
  objs = nuevo
  if antes ~= #objs then
    log(string.format("objetos: %d -> %d", antes, #objs))
  end
end

--------------------------------------------------------------------------
-- El write hook: re-imponer el zoom
--------------------------------------------------------------------------

local function mk_hook(addr)
  return function()
    n_wr = n_wr + 1
    wr_tot[addr] = (wr_tot[addr] or 0) + 1
    if not armado or busy then return end
    if rw(addr) == zoom then return end
    busy = true
    ww(addr, zoom)
    busy = false
  end
end

local function colgar(base)
  local addr = base + O_ZOOM
  -- Las DOS direcciones: la que escribe el 68000 ($00xx) y el espejo ($FFxx).
  -- Con solo una no llega (ver yuyu_hitbox_hud.lua).
  for _, a in ipairs({ addr, addr - 0xFF0000 }) do
    if not hooked[a] and has_hook then
      hooked[a] = true
      memory.registerwrite(a, 2, mk_hook(a))
    end
  end
end

local function colgar_todos()
  for i = 1, #objs do colgar(objs[i]) end
end

--------------------------------------------------------------------------
-- Entrada
--------------------------------------------------------------------------

local function held(pad, key)
  local v = pad[key]
  return v and true or false
end

local function armar(on)
  armado = on
  if on then
    escanear()
    log(string.format("armado. zoom = $%04X (%s). Objetos: %d",
      zoom, pct(zoom), #objs))
  else
    log("desarmado. El juego recupera su zoom.")
  end
end

local function tick()
  local pad = joypad.get()

  local a = held(pad, "P2 Button A") or held(pad, "P1 Mode")
  local b = held(pad, "P2 Button B")
  local c = held(pad, "P2 Button C")

  if a and not (prev_pad.a or false) then armar(not armado) end
  if c and not (prev_pad.c or false) then
    ver_lista = not ver_lista
  end
  if b and not (prev_pad.b or false) then
    zoom = ZDEF
    armado = false
    log("zoom a $100 y desarmado.")
  end

  local dz = 0
  if held(pad, "P2 Left")  then dz = dz - ZSTEP end
  if held(pad, "P2 Right") then dz = dz + ZSTEP end
  if dz ~= 0 then
    local antes = zoom
    zoom = clamp(zoom + dz, ZMIN, ZMAX)
    if zoom ~= antes then
      -- el objetivo cambia al instante, sin esperar al write hook
      if armado then
        busy = true
        for i = 1, #objs do ww(objs[i] + O_ZOOM, zoom) end
        busy = false
      end
    end
  end

  prev_pad = { a = a, b = b, c = c }
end

--------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------

local function overlay()
  local sw = emu.screenwidth()

  local L = {}
  local put = function(s, c) L[#L + 1] = { s = s, c = c or 0xFFFFFFFF } end

  put("ZOOM  P2 A armar | flechas zoom | B reset | C lista", 0xFFFFA040)
  put(string.format("estado %s   zoom $%04X (%s)   objetos %d   escrituras %d",
    armado and "ARMADO" or "LIBRE ", zoom, pct(zoom), #objs, n_wr),
    armado and 0xFF40FF40 or 0xFFFFFFFF)
  put("")

  local n = math.min(#objs, 11)
  for i = 1, n do
    local base = objs[i]
    local nombre = ""
    if base == 0xFF8400 then nombre = "  <- P1"
    elseif base == 0xFF9000 then nombre = "  <- P2" end
    put(string.format("  $FF%04X  zoom %s  anim %s  move %02X  escr %d%s",
      base, hex(base + O_ZOOM), hex(base + O_ANIM), rb(base + O_MOVE),
      wr_tot[base + O_ZOOM] or 0, nombre))
  end
  if #objs > n then put(string.format("  ... y %d mas", #objs - n)) end

  put("")
  put("'escr' = veces que el juego toco ese zoom. Alto = objeto vivo.")

  gui.box(2, 2, sw - 3, 14 + #L * 9, 0x60000000, 0xFF909090)
  local y = 5
  for i = 1, #L do
    if ver_lista or i <= 4 then
      gui.text(5, y, L[i].s, L[i].c)
    end
    y = y + 9
  end
end

--------------------------------------------------------------------------
-- Arranque
--------------------------------------------------------------------------

local rom = emu.romname()
if tostring(rom) ~= TARGET then
  print(string.format("[zoom] aviso: rom actual '%s', esperado '%s'.",
        tostring(rom), TARGET))
end

if not has_write then
  print("[zoom] AVISO: memory.writeword no existe en este build. Nada.")
else
  escanear()
  colgar_todos()
  -- re-enganchar tras cada reset: FBNeo borra los hooks
  local function reenganchar()
    escanear()
    for i = 1, #objs do colgar(objs[i]) end
  end
  if emu.registerstart then emu.registerstart(reenganchar) end
end

emu.registerafter(function()
  local es_replay = (emu.isreplay ~= nil) and emu.isreplay() and true or false
  if not es_replay then
    tick()
    -- rescan periodico: los objetos aparecen y desaparecen
    if (frames % 30) == 0 then
      escanear()
      colgar_todos()
    end
  end
  overlay()
  n_wr = 0
  frames = frames + 1
end)

print("[zoom] listo. Campo de escala = $3E ($100 = 1.0). " ..
      "P2 A arma, flechas cambian el zoom, B vuelve a 1.0.")