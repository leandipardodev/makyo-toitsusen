--[[
  yuyu_camara.lua - TEST DE CAMARA  (Yu Yu Hakusho: Makyou Toitsusen)

  PARA QUE SIRVE
  --------------
  Responder la unica pregunta que queda abierta sobre la camara:

      ¿El escenario se dibuja en funcion de la camara, o los personajes
       se deslizan sobre un fondo quieto?

  Si el escenario se mueve, se puede hacer una camara libre (y con ella
  ver los ~560 px del stage en vez de los 240 px que barre el juego).
  Si NO se mueve, la camara solo mueve a los luchadores.

  QUE HACE
  --------
  NO toca la camara hasta que pulsas una tecla. Armado, sobrescribe el
  objetivo de camara ($A018 / $A01A). La cadena es:

      0x21556  camara = media de las X de mundo - 160
      0x2158C  $A018 = ese valor          <-- se reescribe CADA FRAME
      0x21590  clamp minimo  744
      0x215A4  clamp maximo  984
      0x215C4  $A01A = objetivo vertical (clamp 0..$20)
      0x215C8  move.w $a018.w,d0          <-- LEE $A018
      0x215CC  $A014 += ($A018 - $A014) >> 3     (suavizado)
      0x215D6  $A010 = $A014 + $10, $A012 = $A014 + $120  (paredes)
      0x215F4  $A016 += ($A01A - $A016) >> 4

  Por eso escribir "$A018 por frame" desde Lua NO vale: 0x2158C lo pisa.
  Hay que escribir ENTRE la escritura del juego y su lectura, y hay dos
  formas de pillarlo. Este script usa las DOS, asi que funciona aunque
  una este rota:

    1) exec hook en 0x0215C8, que es justo la instruccion que lo lee.
    2) write hook en $A018 y $A01A: cada vez que el juego las escribe, se
       reescribe al instante. El juego ya termino su escritura, asi que
       gana el nuestro, y 0x215C8 ya leeria lo nuestro.

  OJO: en este build de Fightcade el exec hook NO dispara (por eso
  yuyu_hitbox_hud.lua usa solo write hooks). Por eso el write hook es el
  que sostiene el test. Si los dos disparan, da igual: se escribe el
  mismo valor dos veces.

  COMO SE USA
  -----------
  1. Fightcade: entra a un COMBATE (la camara solo se calcula con
     entidades registradas; el contador es $A00E y sale en el panel).
  2. Game > Lua Scripting > New Lua Script Window > Browse > este fichero.
  3. Teclas (de P2, para no chocar con el juego; en un combate P2 es la CPU):
       P2 Button A      armar / desarmar   (tambien sirve P1 Mode)
       P2 Button B      recentrar: offsets a 0 y recapturar la base
       P2 Left / Right  mover el objetivo X +-2 px por frame
       P2 Up / Down     mover el objetivo Y +-2 px por frame
       P2 Button C      barrido automatico +-160 px (va y viene solo)
  4. Con la camara armada, muevela +-100 px y MIRA LA PANTALLA:
       - si se mueve el ESCENARIO  -> el fondo sigue a la camara
       - si solo se mueven los PERSONAJES -> el fondo es fijo

  QUE MIRAR EN EL PANEL
  ---------------------
     wr X/frame  escrituras del juego sobre $A018. En combate sale 1..3.
                Si sale 0, no hay camara: no estas en combate o
                $A00E = 0.
     exec        ejecuciones del hook en 0x0215C8. Si sale 0, no pasa
                nada: ese hook no funciona en este build (es normal) y
                el que manda es "wr X".
     $08 / $0C   posicion en pantalla de P1 y P2. Se mueven con la camara
                porque la proyeccion de loc_0156F0 resta la camara; eso
                es normal y no dice nada del fondo.

  AVISO
  -----
  Este script ESCRIBE en la memoria del juego, al contrario que el resto
  (ver AGENTS.md, regla 5). Es un instrumento de diagnostico, no un cheat:
  solo escribe cuando lo armas, y solo dos words. Desarmandolo, el juego
  sigue su camara normal al frame siguiente. No escribe nunca en un replay.
--]]

local TARGET = "md_yuyumte"

--------------------------------------------------------------------------
-- Direcciones (verificadas en game_68000.asm, ver AGENTS.md)
--------------------------------------------------------------------------

local CAM_X   = 0xFFA014   -- camara X real (la que se suaviza)
local CAM_Y   = 0xFFA016   -- camara Y real
local TGT_X   = 0xFFA018   -- objetivo X (el juego lo reescribe cada frame)
local TGT_Y   = 0xFFA01A   -- objetivo Y
local WALL_L  = 0xFFA010   -- pared izquierda = camX + $10
local WALL_R  = 0xFFA012   -- pared derecha     = camX + $120
local NENT    = 0xFFA00E   -- contador de entidades (si 0, no hay camara)
local VSCROLL = 0xFFF566   -- scroll vertical extra

local P1      = 0xFF8400   -- slot del jugador 1
local P2      = 0xFF9000   -- slot del jugador 2 (stride $C00)
local O_SX    = 0x08       -- posicion en pantalla X
local O_SY    = 0x0C       -- posicion en pantalla Y

local HOOK_PC = 0x0215C8   -- 'move.w $a018.w,d0'

local STEP    = 2          -- px por frame de las flechas
local SWEEP   = 160        -- amplitud del barrido automatico
-- El objetivo se guarda en un word y el juego lo trata sin signo en la resta,
-- asi que 0 (o 4096) equivale a "sigue todo el rato hacia ahi": no hay limites
-- duros de movimiento, solo se evitan desbordes.
local XMIN, XMAX = 0, 4096
local YMIN, YMAX = 0, 2048

--------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------

local rw = memory.readword
local ww = memory.writeword
local has_write = (memory.writeword ~= nil)
local has_exec  = (memory.registerexec  ~= nil)
local has_wr    = (memory.registerwrite ~= nil)

-- Enmascarar a 16 bits sin operadores bitwise (el Lua de Fightcade es 5.1)
local function u16(v)
  return math.floor(v) % 65536
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function hex(v)
  return string.format("$%04X", u16(v))
end

local function sgn(v)
  if v > 32767 then v = v - 65536 end
  return v
end

local function log(s)
  print("[cam] " .. s)
end

--------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------

local armado   = false
local base_x   = 0        -- objetivo natural en el momento de armar
local base_y   = 0
local off_x    = 0        -- desplazamiento que le metemos nosotros
local off_y    = 0
local sweep_on = false
local sweep_p  = 0        -- posicion dentro del barrido (-SWEEP..+SWEEP)
local sweep_d  = 1
local busy     = false    -- guardia: escribir dispara el write hook
local replay   = false

local n_exec = 0          -- por frame
local n_wrx  = 0
local n_wry  = 0
local n_exec_tot = 0
local n_wrx_tot  = 0
local frames = 0
local prev_pad = {}

--------------------------------------------------------------------------
-- La escritura: dos words, y solo si estamos armados
--------------------------------------------------------------------------

local function aplicar()
  if not armado or busy then return end

  local tx = base_x + off_x
  local ty = base_y + off_y

  if sweep_on then
    -- va y viene solo, 1 px por cada acierto del hook
    sweep_p = sweep_p + sweep_d
    if sweep_p >  SWEEP then sweep_p =  SWEEP; sweep_d = -1 end
    if sweep_p < -SWEEP then sweep_p = -SWEEP; sweep_d =  1 end
    tx = base_x + sweep_p
  end

  local ux = u16(clamp(tx, XMIN, XMAX))
  local uy = u16(clamp(ty, YMIN, YMAX))

  local cambx = (rw(TGT_X) ~= ux)
  local camby = (rw(TGT_Y) ~= uy)
  if not cambx and not camby then return end

  busy = true
  if cambx then ww(TGT_X, ux) end
  if camby then ww(TGT_Y, uy) end
  busy = false
end

--------------------------------------------------------------------------
-- Los tres hooks
--------------------------------------------------------------------------

-- 1) exec en la instruccion que LEE $A018. Punto limpio, pero en este build
--    puede que no dispare (si no, el panel lo dice).
local function hook_exec()
  n_exec = n_exec + 1
  n_exec_tot = n_exec_tot + 1
  aplicar()
end

-- 2) el juego acaba de escribir $A018: se reescribe al instante
local function hook_wr_x()
  n_wrx = n_wrx + 1
  n_wrx_tot = n_wrx_tot + 1
  aplicar()
end

-- 3) idem con $A01A (0x215C4)
local function hook_wr_y()
  n_wry = n_wry + 1
  aplicar()
end

local function armar_hooks()
  if has_exec then memory.registerexec(HOOK_PC, hook_exec) end
  if has_wr then
    -- Las DOS direcciones: la que escribe el 68000 ($00A018) y el espejo
    -- de FBNeo ($FFA018). Con solo una no llega (ver yuyu_hitbox_hud.lua).
    memory.registerwrite(TGT_X,     2, hook_wr_x)
    memory.registerwrite(TGT_X - 0xFF0000, 2, hook_wr_x)
    memory.registerwrite(TGT_Y,     2, hook_wr_y)
    memory.registerwrite(TGT_Y - 0xFF0000, 2, hook_wr_y)
  end
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
    base_x = rw(TGT_X)
    base_y = rw(TGT_Y)
    off_x, off_y = 0, 0
    sweep_p, sweep_d = 0, 1
    log(string.format("armado. base X=%s Y=%s. Flechas mueven, B recentra, C barrido",
      hex(base_x), hex(base_y)))
  else
    log("desarmado. La camara vuelve a la normal.")
  end
end

local function recentrar()
  off_x, off_y = 0, 0
  sweep_on = false
  sweep_p = 0
  base_x = rw(TGT_X)
  base_y = rw(TGT_Y)
  log(string.format("recentrado en X=%s Y=%s", hex(base_x), hex(base_y)))
end

local function tick()
  local pad = joypad.get()

  -- flancos: P2 para no chocar con el juego; P1 Mode como alternativa
  local a = held(pad, "P2 Button A") or held(pad, "P1 Mode")
  local b = held(pad, "P2 Button B")
  local c = held(pad, "P2 Button C")

  if a and not (prev_pad.a or false) then armar(not armado) end
  if b and not (prev_pad.b or false) then recentrar() end
  if c and not (prev_pad.c or false) then
    sweep_on = not sweep_on
    sweep_p, sweep_d = 0, 1
    log("barrido automatico: " .. (sweep_on and "ON" or "OFF"))
  end

  -- desplazamiento continuo con las flechas
  if armado then
    local dx, dy = 0, 0
    if held(pad, "P2 Left")  then dx = dx - STEP end
    if held(pad, "P2 Right") then dx = dx + STEP end
    if held(pad, "P2 Up")    then dy = dy - STEP end
    if held(pad, "P2 Down")  then dy = dy + STEP end
    off_x = clamp(off_x + dx, -2048, 2048)
    off_y = clamp(off_y + dy, -1024, 1024)
  end

  prev_pad = { a = a, b = b, c = c }
end

--------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------

local function overlay()
  local sw = emu.screenwidth()

  local cam_x, cam_y = rw(CAM_X), rw(CAM_Y)
  local tgt_x, tgt_y = rw(TGT_X), rw(TGT_Y)
  local for_x = base_x + (sweep_on and sweep_p or off_x)
  local for_y = base_y + off_y

  local L = {}
  local put = function(s, c) L[#L + 1] = { s = s, c = c or 0xFFFFFFFF } end

  put("TEST CAMARA  P2 A armar | B recentrar | C barrido | flechas mover", 0xFFFFA040)
  put(string.format("estado %s   wr X %d  wr Y %d  exec %d   frame %d",
    armado and "FORZADO" or "LIBRE   ", n_wrx, n_wry, n_exec, frames),
    armado and 0xFF40FF40 or 0xFFFFFFFF)
  put("")
  put(string.format("camara   X=%s (%d)   Y=%s (%d)",
    hex(cam_x), sgn(cam_x), hex(cam_y), sgn(cam_y)))
  put(string.format("natural  X=%s   Y=%s", hex(tgt_x), hex(tgt_y)))
  put(string.format("forzado  X=%s (%+d)   Y=%s (%+d)",
    hex(for_x), for_x - base_x, hex(for_y), for_y - base_y))
  put(string.format("paredes  %s .. %s   vscroll %s   entidades %s",
    hex(rw(WALL_L)), hex(rw(WALL_R)), hex(rw(VSCROLL)), hex(rw(NENT))))
  put(string.format("P1 pant. X=%s Y=%s   P2 X=%s Y=%s",
    hex(rw(P1 + O_SX)), hex(rw(P1 + O_SY)),
    hex(rw(P2 + O_SX)), hex(rw(P2 + O_SY))))
  put("")

  if n_wrx == 0 then
    put("SIN CAMARA: no hay escrituras en $A018. No estas en combate?", 0xFFFF4040)
  else
    put("mueve +-100 px: si se va el ESCENARIO, el fondo sigue a la camara")
    if n_exec == 0 then
      put("(exec hook = 0: normal en este build, manda el write hook)", 0xFF9090FF)
    end
  end

  gui.box(2, 2, sw - 3, 14 + #L * 9, 0x60000000, 0xFF909090)
  for i = 1, #L do
    gui.text(5, 5 + (i - 1) * 9, L[i].s, L[i].c)
  end
end

--------------------------------------------------------------------------
-- Arranque
--------------------------------------------------------------------------

local rom = emu.romname()
if tostring(rom) ~= TARGET then
  print(string.format("[cam] aviso: rom actual '%s', esperado '%s'.",
        tostring(rom), TARGET))
end

if not has_write then
  print("[cam] AVISO: memory.writeword no existe en este build. No se puede armar.")
else
  -- FBNeo borra los hooks en cada reset: se rearman al cargar y al resetear.
  armar_hooks()
  if emu.registerstart then emu.registerstart(armar_hooks) end
end

emu.registerafter(function()
  replay = (emu.isreplay ~= nil) and emu.isreplay() and true or false
  if not replay then tick() end
  overlay()
  n_exec, n_wrx, n_wry = 0, 0, 0
  frames = frames + 1
end)

print("[cam] listo. Exec 0x0215C8 + write hooks en $A018/$A01A. " ..
      "P2 A arma, flechas mueven, P2 B recentra, P2 C barre. " ..
      "En combate 'wr X' debe salir 1..3.")