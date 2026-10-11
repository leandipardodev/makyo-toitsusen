--[[
  yuyu_voley.lua - MINIJUEGO DE VOLEY  (Yu Yu Hakusho - Makyou Toitsusen)

  QUE HACE, EN UNA LINEA
  -----------------------
  Lua tira una pelota desde arriba con fisicas; la unica cosa que la golpea son
  las HITBOXES que el juego ya genera en cada ataque normal. Si toca el suelo en
  la mitad del rival, punto tuyo; en la tuya, punto suyo. Y cae otra.

  POR QUE HACE FALTA UN WRITE HOOK PARA VER LAS HITBOXES
  ------------------------------------------------------
  El dispatcher (loc_01EDAC) construye las listas, las resuelve, y AL FINAL pone
  a cero los cinco contadores (0x1EDC2-0x1EDDA). Leyendo el contador desde
  fuera siempre sale 0. Hay que copiar la lista en el instante en que el juego
  escribe el contador, que es lo que hace yuyu_hitbox_hud.lua.

     hitbox   base $FFA200  contador $FFA004  stride $10  -> PEGA la pelota
     hurtbox  base $FFA400  contador $FFA008  stride $10  -> el cuerpo, rebota
     dentro:  +0 X, +4 Y, +8 radioX (bit 7 = terminador), +9 radioY,
              +$C owner ($8400 = P1, $9000 = P2)

  COORDENADAS
  -----------
  La pelota vive en PIXELES DE PANTALLA (asi se ve siempre y se coloca donde
  queremos). Las cajas se convierten al dibujar, con la misma calibracion que
  usa yuyu_hitbox_hud.lua, que es el que las alinea con los sprites:

     pantalla = mundo - camara + $80 - 127

  TECLAS: ninguna obligatoria. P2 B relanza la pelota.
--]]

local TARGET = "md_yuyumte"

--------------------------------------------------------------------------
-- Direcciones
--------------------------------------------------------------------------

local TGT_X = 0xFFA018
local CAM_X = 0xFFA014
local CAM_Y = 0xFFA016
local VSCROLL = 0xFFF566

local P1 = 0xFF8400
local P2 = 0xFF9000
local O_WX = 0x40
local O_WY = 0x44

local LISTA_HIT  = 0xFFA200
local CNT_HIT    = 0xFFA004
local LISTA_HURT = 0xFFA400
local CNT_HURT   = 0xFFA008
local STRIDE     = 0x10
local MAX_CAJAS  = 15

local CAM_MID = 0x360

--------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------

local rb  = memory.readbyte
local rw  = memory.readword
local rws = memory.readwordsigned
local ww  = memory.writeword

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function log(s) print("[voley] " .. s) end

local CAL_X, CAL_Y = -127, -127

local function sx_de(wx) return wx - rw(CAM_X) + 0x80 + CAL_X end
local function sy_de(wy) return wy - rw(CAM_Y) + rws(VSCROLL) + 0x20 - 8 + CAL_Y end

--------------------------------------------------------------------------
-- Copia de las listas cuando el juego escribe el contador
--------------------------------------------------------------------------

local hit, hurt = {}, {}

local function copiar(base, cnt_addr)
  local v = rw(cnt_addr)
  if v < 4 then return nil end
  local n = math.floor(v / STRIDE)
  if n < 1 then return nil end
  if n > MAX_CAJAS then n = MAX_CAJAS end
  local t = {}
  for k = 0, n - 1 do
    local a = base + k * STRIDE
    local rx = rb(a + 0x08)
    if rx >= 0x80 then rx = rx - 0x80 end
    t[k + 1] = { x = sx_de(rws(a + 0x00)), y = sy_de(rws(a + 0x04)),
                 rx = rx, ry = rb(a + 0x09), own = rw(a + 0x0C) }
  end
  return t
end

local function on_cnt_hit()  local t = copiar(LISTA_HIT,  CNT_HIT);  if t then hit  = t end end
local function on_cnt_hurt() local t = copiar(LISTA_HURT, CNT_HURT); if t then hurt = t end end

--------------------------------------------------------------------------
-- Minijuego  (la pelota, en pixeles de pantalla)
--------------------------------------------------------------------------

local SW, SH   = 320, 224
local PLAY_TOP = 16
local PLAY_BOT = 207

local NET_X   = 160
local NET_TOP = 44

local BALL_R     = 5
local GRAV       = 0.38
local GOLPE_VX   = 6.5
local GOLPE_VY   = -9.5
local ENFRIAMIENTO = 8
local GRACIA      = 14
local ESPERA_PUNTO = 20
local PARED = 12

local bx, by = 160, 40          -- la pelota, en pantalla
local bvx, bvy = 0, 0
local gracia   = 0
local enfr     = { P1 = 0, P2 = 0 }
local suelo    = 190            -- Y de pantalla del suelo (se calibra)
local puntos   = { P1 = 0, P2 = 0 }
local saca_de  = "P2"
local rally    = 0
local flash    = 0
local espera   = 0
local aviso    = ""
local cam_lock = true
local busy     = false
local prev_b   = false

--------------------------------------------------------------------------
-- Camara fija
--------------------------------------------------------------------------

local function camara()
  if not cam_lock or busy then return end
  busy = true
  ww(TGT_X, CAM_MID)
  busy = false
end

local function colgar_hooks()
  if not memory.registerwrite then return end
  memory.registerwrite(CNT_HIT,    2, on_cnt_hit)
  memory.registerwrite(CNT_HIT - 0xFF0000, 2, on_cnt_hit)
  memory.registerwrite(CNT_HURT,   2, on_cnt_hurt)
  memory.registerwrite(CNT_HURT - 0xFF0000, 2, on_cnt_hurt)
  memory.registerwrite(TGT_X,      2, camara)
  memory.registerwrite(TGT_X - 0xFF0000, 2, camara)
end

--------------------------------------------------------------------------
-- Suelo real (de donde estan los pies de los luchadores)
--------------------------------------------------------------------------

local function calibrar_suelo()
  local y = math.max(sy_de(rw(P1 + O_WY)), sy_de(rw(P2 + O_WY)))
  if y < 110 or y > 214 then return end          -- valor sin sentido: se ignora
  if math.abs(y - suelo) > 30 then suelo = y   -- cambio de stage
  elseif y > suelo then suelo = y end           -- saltar no lo baja
end

--------------------------------------------------------------------------
-- Pelota
--------------------------------------------------------------------------

local function tirar()
  bx = (saca_de == "P1") and 80 or 240
  by = PLAY_TOP + 24          -- dentro de la pantalla, se ve caer
  bvx, bvy = 0, 0
  gracia = 0
  rally = 0
  enfr.P1, enfr.P2 = 0, 0
  aviso = ""
end

local function punto(quien)
  puntos[quien] = puntos[quien] + 1
  saca_de = (quien == "P1") and "P2" or "P1"
  rally = 0
  espera = ESPERA_PUNTO
  log(string.format("PUNTO de %s!  P1 %d - %d P2   saca %s",
    quien, puntos.P1, puntos.P2, saca_de))
end

local function pega(quien)
  local x_p = sx_de(rw(P1 + O_WX))
  local x_q = sx_de(rw(P2 + O_WX))
  local mio   = (quien == "P1") and x_p or x_q
  local rival = (quien == "P1") and x_q or x_p
  local dir = (rival >= mio) and 1 or -1
  bvx = dir * GOLPE_VX
  bvy = GOLPE_VY
  gracia = GRACIA
  rally = rally + 1
  enfr[quien] = ENFRIAMIENTO
  flash = 8
  aviso = "golpe de " .. quien
  log(string.format("GOLPE de %s -> %+d   vel %.1f / %.1f   rally %d",
    quien, dir, bvx, bvy, rally))
end

local function choca(c)
  return math.abs(bx - c.x) <= (c.rx + BALL_R) and
         math.abs(by - c.y) <= (c.ry + BALL_R)
end

-- hitbox de un ataque -> lanza la pelota al contrario
local function colision_golpe()
  for i = 1, #hit do
    local c = hit[i]
    local quien = (c.own == 0x8400) and "P1" or (c.own == 0x9000) and "P2" or nil
    if quien and enfr[quien] <= 0 and c.rx > 0 and c.ry > 0 and c.ry < 0x40 then
      if choca(c) then
        pega(quien)
        return true
      end
    end
  end
  return false
end

-- hurtbox (el cuerpo) -> solo rebota
local function colision_cuerpo()
  for i = 1, #hurt do
    local c = hurt[i]
    if (c.own == 0x8400 or c.own == 0x9000) and c.rx > 0 and c.ry > 0 and c.ry < 0x40 then
      if choca(c) then
        local s = (bx >= c.x) and 1 or -1
        bvx = s * math.max(math.abs(bvx), 2.5)
        bvy = bvy - 0.8
        bx = bx + s * 3
        aviso = "cuerpo"
        return true
      end
    end
  end
  return false
end

local function fisicas()
  bvy = bvy + GRAV
  local x_ant = bx
  bx = bx + bvx
  by = by + bvy

  if gracia > 0 then gracia = gracia - 1 end
  if enfr.P1 > 0 then enfr.P1 = enfr.P1 - 1 end
  if enfr.P2 > 0 then enfr.P2 = enfr.P2 - 1 end
  if flash > 0 then flash = flash - 1 end

  -- paredes
  if bx < PARED then bx = PARED; bvx = math.abs(bvx) end
  if bx > SW - PARED then bx = SW - PARED; bvx = -math.abs(bvx) end
  if by < PLAY_TOP then by = PLAY_TOP; bvy = math.abs(bvy) end

  -- suelo = punto
  if by >= suelo then
    by = suelo
    punto(bx < NET_X and "P2" or "P1")
    bvx, bvy = 0, 0
    return
  end

  colision_cuerpo()

  -- red vertical (se comprueba el cruce para que una pelota rapida no la pase)
  if gracia <= 0 and by >= NET_TOP and (x_ant - NET_X) * (bx - NET_X) <= 0 then
    bx = bx - (bvx >= 0 and 6 or -6)
    bvx = -bvx * 0.5
    bvy = bvy * 0.5 - 0.6
  end
end

--------------------------------------------------------------------------
-- Dibujo (sin hitboxes: solo la pista)
--------------------------------------------------------------------------

local COL_RED  = 0xD8D8D8FF
local COL_BALL = 0xFFFFE000
local COL_BORD = 0xFF503000
local COL_HIT  = 0xFF60FF60

local function overlay()
  local sw = emu.screenwidth()

  gui.drawline(0, suelo, sw - 1, suelo, 0x707070C0)

  gui.drawline(NET_X, NET_TOP, NET_X, suelo, COL_RED)
  for y = NET_TOP, suelo, 16 do
    gui.drawline(NET_X - 5, y, NET_X + 5, y, 0xA0A0A0D0)
  end

  local k = clamp((suelo - by) / 70, 0, 1)
  gui.drawline(bx - 6 + k * 9, suelo, bx + 6 + k * 9, suelo, 0x50505070)

  local col = COL_BALL
  if flash > 0 then col = COL_HIT end
  if espera > 0 then col = 0xFF707070 end
  gui.box(bx - BALL_R, by - BALL_R, bx + BALL_R, by + BALL_R, col, COL_BORD)

  local y = 4
  gui.text(5, y, string.format("P1 %d - %d P2     rally %d",
    puntos.P1, puntos.P2, rally), 0xFFFFA040); y = y + 9
  gui.text(5, y, string.format("cajas: hit %d  hurt %d   %s",
    #hit, #hurt, aviso), 0xFFFFFFFF)
end

--------------------------------------------------------------------------
-- Arranque
--------------------------------------------------------------------------

local rom = emu.romname()
if tostring(rom) ~= TARGET then
  print(string.format("[voley] aviso: rom actual '%s', esperado '%s'.",
        tostring(rom), TARGET))
end

calibrar_suelo()
tirar()

colgar_hooks()
if emu.registerstart then emu.registerstart(colgar_hooks) end

emu.registerafter(function()
  local es_replay = (emu.isreplay ~= nil) and emu.isreplay() and true or false
  if not es_replay then
    calibrar_suelo()
    local pad = joypad.get()
    local b = pad["P2 Button B"]
    local pb = prev_b
    if b and not pb then tirar() end
    prev_b = b

    if espera > 0 then
      espera = espera - 1
      if espera == 0 then tirar() end
    else
      if not colision_golpe() then fisicas() end
    end
  end
  overlay()
end)

print("[voley] listo. Pelota en pixeles de pantalla, sale desde arriba. " ..
      "Solo la pegan las hitboxes del juego. P2 B relanza.")