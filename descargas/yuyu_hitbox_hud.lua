--[[
  yuyu_hitbox_hud.lua — Hitbox display + HUD para
  Yu Yu Hakusho: Makyou Toitsusen (Mega Drive, 1994) en FBNeo / Fightcade.

  Uso:
    Game > Lua Scripting > New Lua Script Window > Browse > este fichero
    Cargar el ROM md_yuyumte y entrar a un combate.

  Muestra:
    - Las cinco listas de colisiones: hitbox, clash, hurtbox, pushbox y el
      descriptor de grab. Solo borde, sin relleno, para tapar lo menos posible.
    - Eje central del personaje y su caja de 48 px.
    - Input display de P1 abajo a la derecha (cruceta + A B C X Y Z + MODE/START).
    - Tira de los ultimos botones pulsados, con los frames entre pulsadas.
    - Numeros de vida y mana pegados a las barras originales del juego.
    - Barra de aturdimiento en escala global, con la marca del personaje actual.
    - Barra de hit-time y de congelacion global de especiales.
    - Titulo "N#ga hud" con arcoiris y relieve.

  Menu: se abre manteniendo MODE. A=ON/OFF, flechas mueven, B=reset.

  Es 100% pasivo: no escribe ni un byte en la memoria del juego.

  Documentacion de las direcciones: COLISIONES_Y_HITBOXES.md y AGENTS.md
--]]

--------------------------------------------------------------------------------
-- Configuracion
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- LOGO "N#ga" — pixel art dibujado a mano, no es una fuente.
--
-- Cada glifo es una lista de trazos (rectangulos) en una celda de 14x22. Las
-- unidades son de 2-3 px justamente para que se vea pixeleado de verdad: con la
-- fuente del emulador siempre se ve "tipografia", no pixel art.
--
-- El relieve se hace por EXTRUSION: el glifo se dibuja repetido desplazado 1, 2
-- y 3 px hacia abajo-derecha, cada capa en un tono mas oscuro, y cada capa lleva
-- una silueta negra 1 px mas grande que ella. Ese negro entre capas es lo que
-- separa los planos y da la sensacion de volumen.
--
-- Encima, un brillo especular que recorre las letras de izquierda a derecha,
-- como cuando la luz pega sobre un filo. Y todo el logo sube y baja 1 px muy
-- lento.
--
-- Estetica: blanco calido arriba, dorado abajo, extrusion rojo laca de samurai.
-- Los colores van en 0xAARRGGBB porque acá se usa gui.box, que SI es ARGB
-- (gui.drawline es RRGGBBAA, ver la nota de AGENTS.md).
--------------------------------------------------------------------------------
local LOGO = {
  N = { {0,0,3,22},{11,0,3,22},{3,0,3,4},{4,3,3,4},{5,6,3,4},{6,9,3,4},
       {7,12,3,4},{8,15,3,4},{9,18,3,4} },
  ["#"] = { {2,0,3,22},{9,0,3,22},{0,7,12,3},{0,14,12,3} },
  -- G mayuscula: como una C con un travesano entrando desde la derecha.
  G = { {2,0,9,3},{1,3,3,16},{2,19,9,3},{8,10,3,9},{5,10,6,3} },
  -- A mayuscula: dos patas y travesano, con remate en la punta.
  A = { {1,0,3,22},{10,0,3,22},{4,0,6,3},{2,12,10,3} },
}
local LOGO_ORDER = { "N", "#", "G", "A" }
local LOGO_CELL  = 16      -- 14 de glifo + 2 de aire entre letras
local LOGO_H     = 22      -- alto de la celda

-- Rampa vertical de la cara frontal: de blanco calido a dorado. Precalculada a
-- mano para no hacer mezcla de color en la funcion (y no liarse con el formato).
local LOGO_RAMP = {
  0xFFFFF8F0, 0xFFFFF0C0, 0xFFFFE090, 0xFFFFD060,
  0xFFFFC040, 0xFFF5A838, 0xFFE08828, 0xFFC06A18,
}
-- Tonos de la extrusion, del mas cercano al mas lejano.
local LOGO_DEPTH = { 0xFFB04A38, 0xFF7A2A20, 0xFF4E1410 }
local LOGO_BLACK = 0xFF000000

--------------------------------------------------------------------------------
-- BANDERA ARGENTINA, con llamas encima.
--
-- Tres bandas horizontales iguales (celeste / blanco / celeste) con el Sol de Mayo
-- al centro. Se dibuja por franjas de 1 px en vez de pixel por pixel: sale
-- exacto y es mas barato. Cada franja se desplaza un poco mas que la anterior,
-- que es lo que hace que la bandera ondee.
--
-- ARGB, porque va con gui.box.
--------------------------------------------------------------------------------
local BAND_CELESTE = 0xFF6FB4E0   -- azul de la banda 1 y 3
local BAND_BLANCO  = 0xFFF0F0F0
local SOL_MAYO     = 0xFFF5B71C   -- el sol del medio
local SOL_NUCLEO   = 0xFF9A5A08

-- El sol: 13x13, como filas de (columna inicial, ancho).
local SOL_ROWS = {
  {6,1},{5,3},{5,3},{4,5},{4,5},{3,7},{3,7},{3,7},{4,5},{4,5},{5,3},{5,3},{6,1},
}

-- Color de las llamas, de la punta (mas fria) a la base.
local FLAME_COLS = {
  0xFFFFF4A0, 0xFFFFC020, 0xFFFF7020, 0xFFE83810, 0xFF901008,
}

local function draw_flag(ox, oy, w, h, t)
  local band_h = h / 3
  for r = 0, h - 1 do
    -- Ondea: el desplazamiento crece con la distancia a la bandera, como una
    -- tela colgada de un asta.
    local off = math.floor(math.sin(t * 2.2 + r * 0.42) * (1 + r * 0.10))
    local c
    if r < band_h then c = BAND_CELESTE
    elseif r < band_h * 2 then c = BAND_BLANCO
    else c = BAND_CELESTE end
    gui.box(ox + off, oy + r, ox + w + off, oy + r, c)
  end

  -- Sol de Mayo en el centro de la banda blanca.
  local sx = ox + math.floor(w / 2) - 6
  local sy = oy + band_h - 6
  for r = 0, #SOL_ROWS - 1 do
    local a, b = SOL_ROWS[r + 1][1], SOL_ROWS[r + 1][2]
    local c = (r == 6) and SOL_NUCLEO or SOL_MAYO     -- fila del medio, mas oscura
    gui.box(sx + a, sy + r, sx + a + b - 1, sy + r, c)
  end
end

-- Llamas que suben desde el borde superior de la bandera. Doce paves con fases
-- distintas; cada una nace blanca y se apaga hasta rojo oscuro mientras sube.
local function draw_flames(ox, oy, w, t)
  for i = 0, 11 do
    local ph = i / 12
    local life = (t * 0.55 + ph) % 1.0        -- 0 = recien nacido, 1 = se apaga
    local fh = 5 + math.floor(7 * (1.0 - life))
    local jitter = math.sin(t * 5.0 + i * 2.3) * 1.5
    local x = ox + 3 + math.floor((w - 9) * ph) + math.floor(jitter)
    local y = oy - fh + math.floor(life * 4)
    local ci = 1 + math.floor(life * #FLAME_COLS)
    if ci > #FLAME_COLS then ci = #FLAME_COLS end
    gui.box(x, y, x + 2, y + fh - 1, FLAME_COLS[ci])
  end
end

-- Bandera + llamas, que es como se usa siempre.
local function draw_flag_flame(ox, oy, w, h, t)
  draw_flag(ox, oy, w, h, t)
  draw_flames(ox, oy, w, t)
end

--------------------------------------------------------------------------------
-- ESTRELLAS del hall de la fama.
--
-- Estrella grande 9x9, de 5 puntas, dibujada a mano: cada fila es una lista de
-- tramos (columna inicial, ancho). La punta, los dos brazos anchos y las dos
-- patas separadas se ven de verdad, no es un cuadrado con picos.
local STAR_BIG = {
  { {4,1} }, { {4,1} }, { {3,3} }, { {3,3} }, { {0,9} },
  { {1,7} }, { {2,5} }, { {2,2},{5,2} }, { {1,2},{6,2} },
}
-- Estrella chica 5x5, para el segundo puesto. Claramente menor que la otra.
local STAR_SML = {
  { {2,1} }, { {0,5} }, { {1,3} }, { {0,2},{3,2} },
}
local STAR_SILVER = 0xFFC8CEDA

-- Avance horizontal de la fuente de FBNeo, en px por caracter.
--
-- Medido a ojo: 8 caracteres ocupaban 62 px, o sea unos 7 y medio. Con 6 (que es
-- lo que se asumia antes) todo el texto centrado con esa cuenta quedaba
-- corrido a la izquierda. 7 es el entero que mejor centra.
local TXT_ADV = 7

local function draw_star(ox, oy, col, sml)
  local rows = sml and STAR_SML or STAR_BIG
  for r = 0, #rows - 1 do
    for _, seg in ipairs(rows[r + 1]) do
      -- Borde oscuro abajo a la derecha: es lo que le da volumen al dorado.
      gui.box(ox + seg[1] + 1, oy + r + 1,
              ox + seg[1] + seg[2], oy + r + 1, 0xFF6A3A08)
      gui.box(ox + seg[1], oy + r,
              ox + seg[1] + seg[2] - 1, oy + r, col)
    end
  end
end

-- OJO de pixel art, 14x9. Cada fila es una lista de segmentos { x, largo }.
--
-- Reemplaza a las estrellas en la fila honorifica de HolaTilin. El iris va en
-- EYE_IRIS y el contorno en EYE_EDGE, para que se lea sobre el velo oscuro.
local EYE_IRIS = 0xFFB44CE8
local EYE_EDGE = 0xFF2A0A3A
local EYE_SCLERA = 0xFFF0E8FF
local EYE = {
  { {3,8}, {11,1} },
  { {1,12} },
  { {0,14} },
  { {1,3}, {5,4}, {10,3} },
  { {1,3}, {5,4}, {10,3} },
  { {1,3}, {5,4}, {10,3} },
  { {0,14} },
  { {1,12} },
  { {3,8}, {11,1} },
}

local function draw_eye(ox, oy)
  -- Sclera: todo el ojo en un tono claro.
  for r = 0, #EYE - 1 do
    for _, seg in ipairs(EYE[r + 1]) do
      gui.box(ox + seg[1], oy + r,
              ox + seg[1] + seg[2] - 1, oy + r, EYE_SCLERA)
    end
  end
  -- Iris violeta en el bloque central de las tres filas del medio.
  for r = 3, 5 do
    local seg = EYE[r + 1][2]
    gui.box(ox + seg[1], oy + r,
            ox + seg[1] + seg[2] - 1, oy + r, EYE_IRIS)
  end
  -- Contorno: se marca el borde del ojo con el color oscuro.
  for r = 0, #EYE - 1 do
    for si, seg in ipairs(EYE[r + 1]) do
      local ultimo = (si == #EYE[r + 1])
      if ultimo then
        gui.box(ox + seg[1], oy + r, ox + seg[1], oy + r, EYE_EDGE)
      end
    end
  end
  -- Borde superior e inferior, delineando la forma del ojo.
  gui.box(ox + 3, oy, ox + 10, oy, EYE_EDGE)
  gui.box(ox + 3, oy + #EYE - 1, ox + 10, oy + #EYE - 1, EYE_EDGE)
end

-- LosDatos del torneo. { nombre, estrellas de oro, estrellas de plata }
local HALL = {
  { "Adolin",    2, 0 },
  { "Nomercy22", 1, 1 },
  { "N#ga",      1, 1 },
  { "Akara1996", 1, 0 },
  { "Kuusa",     1, 0 },
}

-- Toggles. Cruz, cuadricula, facing, coordenadas e historial arrancan
-- DESACTIVADOS: el HUD por defecto tiene que verse limpio, con solo las cajas y
-- las barras. Se encienden desde el menu (mantener MODE).
local SHOW_HITBOXES  = false
local SHOW_CLASH     = false
local SHOW_HURTBOXES = false
local SHOW_PUSHBOXES = false
local SHOW_GRAB      = false
local SHOW_AXIS      = false
local SHOW_GRID      = false
local SHOW_INPUT     = false
local SHOW_HUD       = false
local SHOW_STUN      = false
local SHOW_HITTIME   = false
local SHOW_HISTORY   = false
local SHOW_TIMELINE  = false
local SHOW_COORD     = false

-- Dibuja tambien las cajas del P2. Apagado por defecto como todo lo demas, pero
-- ojo: los proyectiles tienen owner del P2, asi que con el filtro activo no se
-- ve NINGUNA de sus hitboxes. Conviene prenderlo si se trabaja con proyectiles.
local SHOW_P2 = false

-- Calibracion de la conversion mundo -> pantalla, en pixeles.
--
-- $08/$0C NO son pixeles de pantalla: en $01575E se pasan como d2/d3 a $012C4,
-- que es el parser de la lista de sprites del VDP. Y $A014/$A016 son la CAMARA
-- (se actualizan cada frame en $0215D2 y $0215F4), no una base fija del stage.
--
-- Por eso el offset se calibra a mano en vez de copiar la formula de
-- loc_0156F0. La referencia es el CENTRO de la sombra redonda de los pies: la
-- linea horizontal de la cruz tiene que caer ahi.
local CAL_X, CAL_Y = -127, -127

--------------------------------------------------------------------------------
-- Direcciones (verificadas contra el desensamblado)
--------------------------------------------------------------------------------

local P1 = 0xFF8400                -- slot del jugador 1
-- P2 NO esta en $FF8800. Medido volcando los slots en ejecucion:
--   $FF8000 hp=0   stn=256 mp=0
--   $FF8400 hp=223 stn=48  mp=223   <- P1
--   $FF8800 hp=0   stn=0   mp=0     <- vacio
--   $FF8C00 hp=0   stn=0   mp=0     <- vacio
--   $FF9000 hp=223 stn=48  mp=223   <- P2, y baja a 218/45 y 148/9 al recibir
-- O sea que el stride real es $C00, no $400. Los docs decian $400; estaba mal.
local P2 = 0xFF9000

local rb  = memory.readbyte
local rw  = memory.readword
local rws = memory.readwordsigned

-- OFFSETS DEL STRUCT DEL JUGADOR.
--
-- Van en UNA tabla y no en 15 locales sueltas por una razon dura: Lua 5.1
-- tops en 200 locales por funcion y el script ya lo habia pegado ("main
-- function has more than 200 local variables"). Cada constante suelta es un
-- local que cuenta; en tabla, el grupo entero es uno solo.
--
-- Uso: O.HP, O.STUN, O.MP...
local O = {
  WORLD_LO  = 0x40,          -- X en mundo (long, en dos mitades)
  WORLDY_LO = 0x44,          -- Y en mundo
  FACING    = 0x61,
  HITPAUSE  = 0x69,          -- freeze del golpe: 16 normal, 28 clash
  HP        = 0x78,          -- HP real, word SIGNED, max 255
  HP_BAR    = 0x7A,          -- copia ANIMADA que dibuja la barra de HP
  STUN      = 0x7E,          -- presupuesto de stun
  STUN_MAX  = 0x80,
  MP        = 0xB8,          -- energia/TA gastable, NO HP
  MP_BAR    = 0xBC,          -- copia ANIMADA del maná (015832/015844)
  COMBO     = 0xC6,          -- contador de combo NATIVO del juego
}

-- COLORES Y UMBRALES, en tablas para no gastar un local por constante (Lua 5.1
-- tops en 200 locales por funcion).
--
-- OJO con el formato: gui.drawline usa 0xRRGGBBAA (alpha al final) y gui.box /
-- gui.text usan 0xAARRGGBB (alpha al frente). Los dos grupos estan separados
-- para que no se mezclen por error.
local COL = {
  -- para drawline (RRGGBBAA)
  gridMinor = 0xFFFFFF14,   -- blanco con alpha 14, casi invisible
  gridMajor = 0xFF306030,   -- magenta apagado con alpha 30
  gradTop   = 0xFFFFFFFF,   -- blanco
  gradMid   = 0x7FD4FFFF,   -- celeste
  gradBot   = 0x1030C8FF,   -- azul fuerte
  -- para box / text (ARGB)
  gridTxt   = 0xFFC0C0FF,
  histDim   = 0x60C0C0FF,
  pendTxt   = 0x809080FF,
}

-- UMBRALES de los recursos.
local LIM = {
  hpMax = 0xFF,   -- 255, move.w #$ff,$78(a5) en $012AE6
  hpLow = 0x6F,   -- 111, cmpi.w #$6f,$78(a5) en 14 sitios
  mpMax = 0xDF,   -- 223, move.l #$df0000,$b8(a5) en $01A2E2
  mpLow = 0x20,   -- 32, cmpi.w #$20,$b8(a5) en $01CD70
}

-- Direcciones del freeze / camara lenta.
--
-- OJO, esto se cambio mal una vez y rompio la barra de HIT (daba 12796, que es
-- $31FC, basura). Aunque el codigo fuente escriba "$f558.w", la DIRECCION QUE
-- FUNCIONA en la API de FBNeo es $FFF558 / $FFF55A. Probado en ejecucion:
-- con $FFF558 el freeze congela el juego y la barra muestra el valor; con
-- $0000F558 se lee basura.
local FRZ = {
  f     = 0xFFF558,   -- contador
  flag  = 0xFFF55A,   -- flag de congelado este frame
  hold  = 0x00A0,     -- tope al que se fuerza (160, el de las cinematicas)
}

-- Congelacion global de pantalla: $F558 con el flag $F55A. La carga la
-- cinematica de los especiales con 160 ("move.w #$a0,$f558.w" en $01FA82).
local HT_GLOBAL_MAX = 160

-- FREEZE (camara lenta) — conmutador.
--
-- El juego ya tiene este sistema y es un CICLO DEL 50%, no una parada:
-- $01EDFA esta en el dispatcher de colisiones y hace
--   subq.w #$1,$f558.w        el contador baja 1 por frame
--   btst.b #$1,d0             y el BIT 1 del contador decide este frame
--   move.b #$1,$f55a.w        bit1 = 1 -> congelado
--   clr.b  $f55a.w            bit1 = 0 -> corre normal
-- O sea que congela 1 frame y suelta 1, y por eso "la velocidad baja" en vez de
-- frenarse. Las cinematicas lo cargan con 160 ($01FA82: move.w #$a0,$f558.w).
--
-- Con el toggle en ON se mantiene $F558 alto, y eso replica el mismo ciclo del
-- juego pero sostenido. ESCRIBE en la memoria del juego.
local FREEZE_ON = false

-- $26 = PROFUNDIDAD / PLANO. Hay dos planos (uno detras y otro enfrente) y se
-- puede cruzar de uno a otro; $26 dice en cual esta el personaje. Lo confirmo el
-- usuario en ejecucion: 64 y 192 segun el plano.
--
-- OJO: $26 es un byte COMPARTIDO. $1F7B2 tambien lo escribe en cada contacto
-- ($3C/$40 y $BC/$C0), asi que el valor que se ve depende de que paso ultimo.

-- El stun max de los 10 personajes esta en las rutinas de init, una cada 74
-- bytes entre $0127CE y $012A74, con "move.w #$xx,$80(a5)":
--   40, 56, 48, 44, 54, 46, 40, 38, 48, 62
-- El maximo es 62 ($3E) en $012A68, y ese personaje arranca con el gauge lleno.
local STUN_GLOBAL_MAX = 62

-- Posiciones del HUD, en pixeles de pantalla de FBNeo. Todas en tablas para no
-- gastar un local por constante (Lua 5.1 tops en 200 locales por funcion).
--
-- Distribucion en la franja de arriba:
--   y=16..18  numeros de vida y mana de P1 (x=136) y de P2 (x=280)
--   y=32..35  barra de stun de P1 (x=88..128) y de P2 (x=232..272)
--   y=48..56  barra de HIT del combo (x=176..224)
local POS = {
  numX  = 136, numY = 15, mpY = 25,   -- numeros de P1 (1 px mas arriba)
  numX2 = 280,                          -- numeros de P2 (mismo Y)

  -- Barra de stun. Ambas de 40 px de ancho y 3 de alto, en la misma fila.
  stun = { x = 88,  y = 32, w = 40, h = 3 },   -- P1
  stun2 = { x = 232, y = 32, w = 40, h = 3 },  -- P2

  -- Hit-time (la barra HIT de abajo a la izquierda) va de x=176 a x=224 y de
  -- y=48 a y=56.
  ht = { x = 176, y = 48, w = 48, h = 8, max = 25 },

  -- Indicador de teclas y panel de combo.
  keys  = { x = 0, y = 0, w = 92, h = 26 },
  combo = { x = 160, y = 16 },
}
local GRID_STEP = 16

--------------------------------------------------------------------------------
-- Panel de combo
--
-- Reemplaza al indicador de facing (que ahora arranca apagado). Arriba al
-- centro, desde x=128.
--
-- Todo se saca de HOOKS DE ESCRITURA, no de exec: registerexec no dispara en
-- este build de Fightcade. La direccion del write es la que dice a quien le
-- pegaron, asi que mirando donde se escribe alcanza para saber que P1 le esta
-- pegando a P2 (y descartar los golpes de P2 sobre P1).
--
--   $FF8878  HP de P2     -> cada baja es dano
--   $FF887E  stun de P2   -> cada baja es stun aplicado
--   $FF84B8  mana de P1   -> delta < 0 gastado, delta > 0 ganado
--   $FF88C6  combo nativo del juego (se muestra como referencia)
--
-- El chippeo se detecta SOLO como "dano sin stun": el resolver tiene dos
-- caminos, el reducido (01f3dc, $65/4+1) no toca $7E y el completo si
-- (01f424/01f42c). No hace falta saber cual de los dos es el del bloqueo para
-- cumplir con "cuenta como hit pero no suma stun".
--------------------------------------------------------------------------------
-- Panel de combo y barra de stun. Las coordenadas estan en la tabla POS, arriba.
--
-- Rellenado automatico de vida y mana de LOS DOS jugadores.
--
-- Dispara por TIEMPO, no por flanco: cuando pasan REGEN_FRAMES sin que caiga un
-- golpe, se rellena. Asi no hace falta golpear para que se regenere, que es lo
-- que se pidio. Antes disparaba con el flanco de $C6 y salia un golpe tarde,
-- porque $C6 no baja a 0 hasta el siguiente impacto.
--
-- OJO: esto ESCRIBE en la memoria del juego, asi que el script deja de ser
-- pasivo. A pedido explicito del usuario.
local REFILL_ON_COMBO_END = true
local REGEN_FRAMES = 60      -- ~1 segundo a 60 fps sin recibir un golpe
-- Maximo de vida por personaje. NO se hardcodea porque depende del personaje
-- (este da 223, no 255). Se captura del propio juego: en el frame 0 la vida esta
-- a tope, y cada vez que sube se vuelve a capturar. Escribir el maximo global
-- (255) en un personaje que da 223 hace que $7A pase de largo y la barra se rompa.
local p1_hp_max = 0
local p2_hp_max = 0
-- Marca de que el proximo salto de HP lo hicimos nosotros, para que el detector
-- de round nuevo no se dispare con nuestro propio rellenado.
local self_refill = false
-- Frames transcurridos desde el ultimo golpe REAL (con stun). El chippeo NO lo
-- reinicia: por eso un bloqueo con habilidades encadenadas no puede mantener viva
-- la cadena ni frenar la regeneracion.
-- Frames desde CUALQUIER golpe, para la regeneracion por tiempo.
local frames_since_real = 9999
local frames_since_hit = 9999
-- Ventana maxima entre dos golpes reales para que el chippeo pueda continuar una
-- cadena. El hit-time es 16 (01f2E0); 24 deja margen a los encadenes rapidos.
local COMBO_GAP = 24
--
-- No hay ventana de frames propia: el corte lo decide el contador NATIVO del
-- juego ($C6). Se resetea por estado, cuando la victima sale del rango de
-- hitstun $20-$30 ($01FA6A), no por un timeout.
local SHOW_COMBO = false

--------------------------------------------------------------------------------
-- Colisiones
--------------------------------------------------------------------------------

-- Un color por caja, opaco. El alpha del relleno no sirve de nada: gui.box lo
-- ignora y pinta opaco, por eso las cajas se dibujan solo con el borde.
--
-- Cada tipo tiene un TRAZADO distinto, no solo un color distinto: con cinco
-- rectangulos superpuestos del mismo color el ruido era insufrible.
--
--   solid    rectangulo completo  -> hitbox, la que mas importa
--   dashed   rectangulo punteado  -> hurtbox
--   corners  solo las 4 esquinas   -> pushbox y clash, las mas grandes
--   double   doble rectangulo     -> grab, no es una caja normal
--
-- EL ORDEN DE ESTA TABLA ES EL ORDEN DE DIBUJO: primero lo que menos importa,
-- asi la hitbox queda arriba de todo y nunca tapada.
--
-- COLORES: en este build el color va como 0xRRGGBBAA, NO 0xAARRGGBB. O sea que
-- el byte de ALPHA es el ULTIMO, no el primero. Se comprobo en ejecucion con el
-- selftest: pasar 0xFFFF8000 drawing daba "pale yellow TRANSPARENTE" y no se
-- veía, mientras 0xFF00FFFF daba magenta opaca y si se veía.
--
-- Ese fue el bug de las cajas invisibles desde el principio: tres de los cinco
-- colores tenian el byte bajo en 0, o sea alpha cero. La paleta vieja
-- (60E060, C0C040, 80A0FF, E040E0, FF6060) tenia alphas 60, 40, FF, E0, 60:
-- por eso la hurt (la unica con FF) era la unica que se veia.
--
-- Grosor: todo a 1 px. Se prueba asi porque con 2 y 3 px las cajas se merging
-- entre si cuando se superponen, y lo que interesa es ver cada rectangulo.
local LISTS = {
  { name = "push", base = 0xFFA500, cnt = 0xFFA00A, stride = 0x10,
    on = function() return SHOW_PUSHBOXES end,
    style = "corners", line = 0xFF0000FF, width = 1 },
  { name = "clsh", base = 0xFFA300, cnt = 0xFFA006, stride = 0x10,
    on = function() return SHOW_CLASH end,
    style = "corners", line = 0xFF8000FF, width = 1 },
  { name = "hurt", base = 0xFFA400, cnt = 0xFFA008, stride = 0x10,
    on = function() return SHOW_HURTBOXES end,
    style = "dashed", line = 0x00FFFFFF, width = 1 },
  { name = "grab", base = 0xFFA600, cnt = 0xFFA00C, stride = 0x20,
    on = function() return SHOW_GRAB end,
    style = "double", line = 0xFF00FFFF, width = 1 },
  { name = "hit",  base = 0xFFA200, cnt = 0xFFA004, stride = 0x10,
    on = function() return SHOW_HITBOXES end,
    style = "solid", line = 0xFFFF00FF, width = 1 },
}

local HOOK_PC = 0x01EDAC

-- Contador de frame PROPIO. No se usa emu.framecount() porque no avanza de
-- forma confiable en este build, y cuando no avanzaba el snapshot se
-- reutilizaba para siempre: la caja del ultimo golpe quedaba congelada en el
-- aire. Este se incrementa una vez por registerafter, o sea una vez por frame.
local frame_id = 0

local hooked = false
local exec_stamp = -1
local counts = { 0, 0, 0, 0, 0 }

-- Fallback por escritura: si el exec hook no prende, los write hooks sobre los
-- cinco contadores capturan los valores. El dispatcher escribe el total al
-- final y despues pone 0, asi que se ignoran las escrituras en 0.
local wr_counts = { 0, 0, 0, 0, 0 }
local wr_seen = false
local wr_frame = -1

-- Instantanea de los datos de cada lista, tomada en el MISMO instante en que el
-- contador se escribe.
--
-- Por que hace falta: el contador y los datos de la caja no se leen juntos. El
-- builder escribe la caja y despues el contador (01ec3e..01ec84), pero el dibujo
-- pasa por emu.registerafter, que puede caer ANTES del VBlank que construye las
-- cajas del frame. Resultado: al dibujar se leen los datos del frame anterior y la
-- caja aparece 1 frame en la posicion vieja.
--
-- Guardando los datos en el hook, lo que se dibuja siempre corresponde al mismo
-- instante que el conteo.
local wr_boxes = {}

-- Memoria del rango de grab, indexada por la TABLA DE MOVIMIENTOS ($8C) del
-- personaje, no por el jugador: cada personaje usa siempre el mismo builder de
-- grab, asi que la tabla lo identifica de forma unica.
--
-- VACIA a proposito y se llena sola: hay tres builders con valores distintos y no
-- se sabe cual usa cada personaje hasta medirlo con un agarre real.
--
-- LA CAPTURA ES DE UN SOLO FRAME. Antes se exigian GRAB_TRY_FRAMES (40) frames
-- con el descriptor presente, pero el dispatcher lo borra en $01EDDA: el
-- descriptor solo existe 1 frame por intento de agarre. El contador nunca
-- llegaba a 40, la captura nunca se confirmaba y el marcador nunca se dibujaba
-- (la sonda se quedaba en "marcador capturado=NO" para siempre).
--
-- Como ahora se lee el MISMO frame en que se escribio, el offset sale bien y no
-- hace falta quedarse con la mejor de varias lecturas.
local grab_mem = {}
local grab_warned = {}      -- para no repetir el aviso en cada intento
local probe_n = 0

-- LOS TRES SABORES DE AGARRE, leidos del codigo del juego.
--
-- Hay tres builders que escriben el descriptor, y los valores estan LITERALES en
-- el codigo (no son inventados ni vienen de guia web). Cada fila dice de donde
-- sale cada numero:
--
--   $0161BA:  addi.w #$10 / subi.w #$10   -> X = jugador +- 16
--            subi.w  #$30                 -> Y = jugador - 48
--            move.b  #$10, +$4 / #$10, +$5 -> radios 16 y 16
--   $0175E6:  +- 16 / -16                  -> X +- 16, Y - 16
--            move.b  #$0C, +$4 / #$10, +$5 -> radios 12 y 16
--   $018342:  +- $18 / -$30                -> X +- 24, Y - 48
--            move.b  #$18, +$4 / #$08, +$5 -> radios 24 y 8
--
-- OJO: +$4 y +$5 son RADIOS, no medidas. El resolver loc_01EEE2 los SUMA
-- (01ef58: move.b +$4,d1 / add.b +$4_del_otro,d1) y lo compara con la distancia.
-- Asi que un radio de 16 es una caja de 32 px de ancho.
--
-- Que hace que un agarre sea "mejor" que otro, con estos numeros:
--   area    B2 es el mas chico y pegado al cuerpo (Y -16): agarra menos.
--           B3 agarra lejos (radio X 24) pero solo a la altura de la cabeza
--           (radio Y 8).
--   +$6     move que ejecuta el agarrador al conectar: $B9 en B1 y B3, $B8 en B2.
--           Son continuaciones de combo DISTINTAS.
--   +$10    separacion horizontal de la victima: +24 en B1 y B3 (queda adelante),
--           -24 en B2 (queda detras: es un lanzamiento, no una sujecion).
--   +$A     facing que se le fuerza a la victima: 1 en B1/B3, 0 en B2.
local GRAB_KINDS = {
  { dxm = 16, dy = -48, rx = 16, ry = 16, mov = 0xB9, sep =  24 },  -- $0161BA
  { dxm = 16, dy = -16, rx = 12, ry = 16, mov = 0xB8, sep = -24 },  -- $0175E6
  { dxm = 24, dy = -48, rx = 24, ry =  8, mov = 0xB9, sep =  24 },  -- $018342
}
-- El que se usa hasta saber cual le toca a cada personaje.
local GRAB_DEFAULT = GRAB_KINDS[1]

-- Corrige que la cruz no este exactamente centrada en el sprite. La vertical
-- se calibro contra el centro de la sombra; la horizontal quedo sin afinar.
local GRAB_X_FIX = 0

-- Si se dibuja una lista cuyo contador NO fue escrito este frame. Should be
-- false: leer el contador directo dejaba la ultima caja colgada en el aire.
-- Ponerlo en true solo para depurar, porque reintroduce el bug.
local RAW_FALLBACK = false
local raw_warned = false

--------------------------------------------------------------------------------
-- Utilidades
--------------------------------------------------------------------------------

local function own_lo(v)
  return bit.band(v, 0xFFFF)
end

-- El owner NO se guarda completo. El builder hace "move.w a5" (0x01EC40,
-- 0x01EC9E, 0x01ECFC, 0x01ED5A, 0x0161BE), asi que el campo +$C solo tiene
-- el WORD BAJO: $8400 para P1 y $9000 para P2 (ver la nota de P2 arriba).
local function owner_base(v)
  local lo = own_lo(v)
  if lo == own_lo(P1) then return P1 end
  if lo == own_lo(P2) then return P2 end
  return nil
end

local function list_by(name)
  for i = 1, #LISTS do
    if LISTS[i].name == name then return LISTS[i] end
  end
  return nil
end

local function moves_key(base)
  return rw(base + 0x8C)
end

-- Los contadores son offsets EN BYTES, no cantidades.
local function box_count(counter, stride)
  if counter <= 0 then return 0 end
  return math.min(math.floor(counter / stride), 0xF0 / stride)
end

-- nil = dibujar todas las cajas; un numero = solo las de ese jugador.
-- Ojo: no escribir como "SHOW_P2 and nil or P1", porque el and/or de Lua
-- devuelve P1 en los dos casos.
local function owner_filter()
  if SHOW_P2 then return nil end
  return own_lo(P1)
end

--------------------------------------------------------------------------------
-- Conversion mundo -> pantalla
--
-- $08/$0C son la posicion en pantalla PERO CLAMPADA: loc_0156F0 (0x15700 y
-- 0x15730) recorta X a [0x40..0x1FF] e Y a [0x40..0x1C0] y luego resta 8.
-- En cuanto el personaje se sale de esa caja el valor se satura y todo lo
-- anclado a el se queda corrido. Por eso se recalcula la MISMA formula SIN
-- clamp y SIN el offset de empuje ($54/$56), que es de un solo frame.
--------------------------------------------------------------------------------
local function player_screen(base)
  return rw(base + O.WORLD_LO) - rw(0xFFA014) + 0x80 + CAL_X,
         rw(base + O.WORLDY_LO) - rw(0xFFA016) + rws(0xFFF566) + 0x20 - 8 + CAL_Y
end

local function to_screen(owner, bx, by)
  local base = owner_base(owner) or P1
  local ax, ay = player_screen(base)
  return ax + (bx - rw(base + O.WORLD_LO)),
         ay + (by - rw(base + O.WORLDY_LO))
end

--------------------------------------------------------------------------------
-- Dibujo: triangulos y texto con relieve
--------------------------------------------------------------------------------

-- Triangulo relleno de 9 px, centrado en (cx,cy). La fuente de FBNeo no
-- garantiza glifos de flecha, asi que se dibuja a mano.
-- Mide 5 px en el eje hacia el que apunta y 9 en el otro, y siempre nace
-- pegado a un borde: se corrnen 2 px para que quede centrado en la caja.
local function tri(cx, cy, dir, col)
  if dir == "right" then
    cx = cx + 2
  elseif dir == "left" then
    cx = cx - 2
  elseif dir == "down" then
    cy = cy + 2
  else
    cy = cy - 2
  end
  for i = 0, 4 do
    local o = 4 - i
    if dir == "right" then
      gui.drawline(cx - 4 + i, cy - o, cx - 4 + i, cy + o, col)
    elseif dir == "left" then
      gui.drawline(cx + 4 - i, cy - o, cx + 4 - i, cy + o, col)
    elseif dir == "down" then
      gui.drawline(cx - o, cy - 4 + i, cx + o, cy - 4 + i, col)
    else
      gui.drawline(cx - o, cy + 4 - i, cx + o, cy + 4 - i, col)
    end
  end
end

-- El sombreado BLANCO en las 4 diagonales es lo que da el aspecto de 3D. Ese
-- halo solo se ve si el texto NO es blanco puro, asi que esta funcion decide
-- sola: texto de color -> halo blanco; texto blanco -> sombra oscura.
-- Texto SIN relieve: un solo gui.text, sin sombra ni contorno. Para numeros
-- chicos pegados a una barra, el relieve de hud_text los engorda y los hace
-- ilegibles. El glifo queda de 1 px.
local function text_plain(x, y, s, col)
  gui.text(x, y, s, col)
end

local function hud_text(x, y, s, col)
  local r = math.floor(col / 65536) % 256
  local g = math.floor(col / 256) % 256
  local b = col % 256
  if r > 200 and g > 200 and b > 200 then
    gui.text(x + 1, y + 1, s, 0xB0000000)
  else
    gui.text(x - 1, y - 1, s, 0xC0FFFFFF)
    gui.text(x + 1, y - 1, s, 0xC0FFFFFF)
    gui.text(x - 1, y + 1, s, 0xC0FFFFFF)
    gui.text(x + 1, y + 1, s, 0xC0FFFFFF)
  end
  gui.text(x, y, s, col)
end

--------------------------------------------------------------------------------
-- Cajas: SOLO el borde, sin relleno
--
-- Se dibuja con gui.drawline, que si renderiza (la cruz del personaje sale de
-- ahi). Antes se le ponia una pasada negra de 1 px debajo de cada linea para
-- "darle cuerpo" y eso fue un error: sobre fondo oscuro el negro se comia la
-- linea de color y las cajas NO se veian.
--------------------------------------------------------------------------------
-- Dibuja la figura con GROSOR. En vez de calcular un offset por segmento, se
-- dibuja la MISMA figura w veces, cada una 1 px mas adentro: eso produce un
-- borde de w px de grosor. El trazado (punteado / esquinas / doble / solida) se
-- mantiene igual en todas las pasadas, asi que el estilo no se pierde.
--
-- dash: separacion entre puntos del punteado, en px (la guirnalda mide siempre
-- 2 px). Por defecto 4, que es lo que usa la hurt. El grab pasa 12, o sea el
-- triple, para que sus puntos NO se confundan con los de la hurt.
local function draw_box(x1, y1, x2, y2, col, style, corner, w, dash)
  if x2 - x1 < 0 then x1, x2 = x2, x1 end
  if y2 - y1 < 0 then y1, y2 = y2, y1 end
  w = w or 1
  if w < 1 then w = 1 end

  for d = 0, w - 1 do
    local ax, ay, bx, by = x1 + d, y1 + d, x2 - d, y2 - d
    if bx - ax < 0 or by - ay < 0 then break end

    if style == "corners" then
      -- Largo de la esquina PROPORCIONAL a la caja, no fijo en 6. Con 6 px fijos
      -- eran cuatro angulitos chiquitos que sobre un fondo con ruido no se
      -- veian: la sonda decia "realmente=8 fuera=0", o sea que las cajas si se
      -- dibujaban, pero parecian ausentes.
      local min_side = math.min(bx - ax, by - ay)
      local c = corner
      if not c then
        c = math.floor(min_side * 0.35)
        if c < 8 then c = 8 end
        if c > 18 then c = 18 end
      end
      if bx - ax < c * 2 then c = math.floor((bx - ax) / 2) end
      if by - ay < c * 2 then c = math.floor((by - ay) / 2) end
      if c > 0 then
        gui.drawline(ax, ay, ax + c, ay, col)
        gui.drawline(ax, ay, ax, ay + c, col)
        gui.drawline(bx, ay, bx - c, ay, col)
        gui.drawline(bx, ay, bx, ay + c, col)
        gui.drawline(ax, by, ax + c, by, col)
        gui.drawline(ax, by, ax, by - c, col)
        gui.drawline(bx, by, bx - c, by, col)
        gui.drawline(bx, by, bx, by - c, col)
      end
    elseif style == "dashed" then
      local step, on = dash or 4, 2
      local x = ax
      while x <= bx do
        gui.drawline(x, ay, math.min(x + on, bx), ay, col)
        gui.drawline(x, by, math.min(x + on, bx), by, col)
        x = x + step
      end
      local y = ay
      while y <= by do
        gui.drawline(ax, y, ax, math.min(y + on, by), col)
        gui.drawline(bx, y, bx, math.min(y + on, by), col)
        y = y + step
      end
    else
      gui.drawline(ax, ay, bx, ay, col)
      gui.drawline(ax, by, bx, by, col)
      gui.drawline(ax, ay, ax, by, col)
      gui.drawline(bx, ay, bx, by, col)
    end

    -- El "double" del grab es un rectangulo mas adentro, dibujado una sola vez
    -- (en la pasada 0) para que quede el hueco de 2 px entre los dos bordes.
    if style == "double" and d == 0 and bx - ax > 4 and by - ay > 4 then
      gui.drawline(ax + 2, ay + 2, bx - 2, ay + 2, col)
      gui.drawline(ax + 2, by - 2, bx - 2, by - 2, col)
      gui.drawline(ax + 2, ay + 2, ax + 2, by - 2, col)
      gui.drawline(bx - 2, ay + 2, bx - 2, by - 2, col)
    end
  end
end

-- Autocomprobacion de dibujo. Dibuja UNA caja de cada lista en posicion fija,
-- sin tocar los datos del juego, con el MISMO trazo, grosor y color reales.
-- Separa dos cosas que desde la pantalla se ven igual:
--   si estas NO se ven -> el problema es el dibuje o la paleta
--   si estas SI se ven  -> el problema son los datos del juego (contadores,
--                         owners, radios o coordenadas)
local SELFTEST = false
local function draw_selftest()
  if not SELFTEST then return end
  for i = 1, #LISTS do
    local L = LISTS[i]
    local x = 8 + (i - 1) * 62
    gui.box(x - 1, 99, x + 30, 121, 0x80000000, 0x404040FF)
    draw_box(x, 100, x + 28, 118, L.line, L.style, nil, L.width)
    hud_text(x, 124, L.name, 0xFFFFFFFF)
  end
end
--------------------------------------------------------------------------------
-- Panel de combo: estado, hooks y dibujo
--
-- Los hooks de escritura se disparan DURANTE el frame, en el orden en que la
-- CPU ejecuta el resolver: primero se resta HP (01f424) y despues el stun
-- (01f42c). Por eso NO se puede clasificar el golpe en el momento del write de
-- HP: todavia no se sabe si vendra stun. Se acumulan los deltas del frame y la
-- clasificacion se hace al cierre, en combo_update().
--------------------------------------------------------------------------------

-- Acumuladores del combo.
--
-- NO hay hooks de escritura sobre el struct del jugador: los hooks entraban
-- pero los deltas salian mal (doble disparo por el sync del espejo, deltas
-- perdidos si habia dos escrituras en el mismo frame). Ahora se LEE una vez
-- por frame desde combo_update(), que es determinista.
--
-- EL CONTADOR NATIVO $C6 VA UN GOLPE ATRASADO. En loc_01F9C8 el primer impacto
-- cae en el reset (clr.b $c6 en $01FA6A) en vez de incrementar, asi que $C6
-- marca N-1 mientras hay N golpes. Por eso $C6 NO se usa para contar, solo
-- para saber si la cadena sigue viva:
--
--   $C6 > 0  -> el golpe entra en la cadena existente: acumula
--   $C6 == 0 -> es el primer golpe de una cadena nueva: reinicia todo y
--                arranca en 1 (tanto el primer golpe de un combo real como
--                un golpe suelto, que para el panel es lo mismo)
--
-- El maná gastado va en dos etapas, pending y spent, porque el coste se paga
-- al LANZAR la habilidad y el golpe puede tardar o no llegar nunca. Ver el
-- comentario donde se usa.
local combo = {
  hits = 0, dmg = 0, stun = 0,
  spent = 0,       -- gastado de la cadena abierta (solo diagnostico)
  pending = 0,     -- gastado con la cadena cerrada (solo diagnostico)
  gained = 0,      -- ganado por encadenar (solo diagnostico)
  live = false,
  -- El NETO de mana se calcula por DIFERENCIA, no sumando costes.
  --
  -- El problema del metodo anterior: hay habilidades que no gastan maná, otras
  -- que gastan, y el juego ademas MANDA maná al encadenar ($C6*2). Conocer el
  -- coste de cada una no esta al alcance y cualquier tabla se queda corta.
  --
  -- La foto inicial no falla: se lee el maná en el frame en que el primer golpe
  -- abre la cadena, y se resta del valor actual. Da el resultado sea cual sea el
  -- origen, gastado o ganado, sin saber nada de costes.
  mana_base = 0,   -- maná de P1 en el frame que abrió la cadena
  net = 0,         -- resultado que se muestra
  net_frozen = false,
}

-- Ultimo valor leido de cada campo, para sacar deltas.
local prev_hp   = rws(P2 + O.HP)
local prev_stun = rw(P2 + O.STUN)
local prev_mana = rw(P1 + O.MP)
local refill_warned = false

-- Ultimo frame_id con golpe, para diagnostico.
local last_hit_frame = -1
local last_hp, last_stun = 0, 0

-- El contador NATIVO del juego. Vive en el DEFENSOR (a4 en $01F9C8), asi que
-- para ver el combo de P1 hay que leer el de P2.
--
-- No tiene timer: se resetea por ESTADO, cuando el move id de la victima ($5F)
-- sale del rango de hitstun $20-$30 ($01FA6A).
local function combo_native()
  return rb(P2 + O.COMBO)
end

local function combo_full_reset()
  combo.hits = 0
  combo.dmg = 0
  combo.stun = 0
  combo.gained = 0
  combo.spent = 0
  combo.pending = 0
  combo.live = false
end

-- Rellena vida y mana de los DOS jugadores.
--
-- ESCRIBE en la memoria del juego: el script deja de ser pasivo, a pedido
-- explicito del usuario.
--
-- Escribe LAS DOS copias del HP, no solo $78: $7A es la que dibuja la barra y
-- persigue a $78 de a uno por frame (0157a8 / 0157ac), o sea que si solo se
-- escribiera $78 la barra tardaria segundos en llegar y se veria el arranque.
--
-- Solo word, nunca long: el maná ocupa $B8..$BB y escribir de mas pisaria $BA.
local function combo_refill()
  if not memory.writeword then
    if not refill_warned then
      refill_warned = true
      print("[yuyu] AVISO: memory.writeword no existe en este build. "
            .. "La regeneracion automatica NO va a funcionar.")
    end
    return
  end
  -- Si nunca se capturo el maximo (script cargado a mitad de un round), primero
  -- se intenta tomar del valor actual. Si tampoco hay nada, no se escribe:
  -- escribir 255 en un personaje de 223 rompe la barra.
  if p1_hp_max <= 0 or p2_hp_max <= 0 then
    if p1_hp_max <= 0 then p1_hp_max = rws(P1 + O.HP) end
    if p2_hp_max <= 0 then p2_hp_max = rws(P2 + O.HP) end
    if p1_hp_max <= 0 or p2_hp_max <= 0 then return end
  end

  memory.writeword(P1 + O.HP,     p1_hp_max)
  memory.writeword(P1 + O.HP_BAR, p1_hp_max)
  memory.writeword(P2 + O.HP,     p2_hp_max)
  memory.writeword(P2 + O.HP_BAR, p2_hp_max)
  -- El maná tiene el mismo truco que el HP: $BC es la copia que DIBUJA la barra
  -- y persigue a $B8 de a uno por frame (015836 / 015844). Si solo se escribe
  -- $B8 el numero se actualiza al instante pero la barra no se mueve hasta el
  -- proximo golpe, que es lo que pasaba.
  memory.writeword(P1 + O.MP,     LIM.mpMax)
  memory.writeword(P1 + O.MP_BAR, LIM.mpMax)
  memory.writeword(P2 + O.MP,     LIM.mpMax)
  memory.writeword(P2 + O.MP_BAR, LIM.mpMax)

  -- El relleno aparece como un salto de HP al frame siguiente. Con esto se anota
  -- para que el detector de round nuevo lo ignore, y se sincronizan los valores
  -- leidos para que no se vea como dano ni como una curacion.
  --
  -- Ademas se congela el NETO de maná: si no, al dejar el gauge en 223 el neto
  -- saltaria a un numero enorme en el frame siguiente.
  combo.net_frozen = true
  self_refill = true
  prev_hp = p2_hp_max
  prev_mana = LIM.mpMax
  frames_since_hit = 0
end

-- Falta algo que rellenar? Evita estar escribiendo cada segundo en vanos.
local function needs_refill()
  return rws(P1 + O.HP) < p1_hp_max
      or rws(P2 + O.HP) < p2_hp_max
      or rw(P1 + O.MP) < LIM.mpMax
      or rw(P2 + O.MP) < LIM.mpMax
end

-- Se ejecuta una vez por frame. Sube o baja el freeze.
--
-- DOS ERRORES QUE TENIA:
--
-- 1) Pausaba COMPLETO. Recargaba el contador en cada frame con 0xFFFF, y como
--    el dispatcher decide con el BIT 1 del contador, subirlo siempre a 0xFFFF
--    dejaba el bit 1 permanentemente en 1 -> congelado todos los frames.
--
-- 2) Al apagar seguia en camara lenta. Al dejar de recargar, el contador se
--    quedaba en ~65535 y tardaba 65.000 frames en agotarse.
--
-- Ahora: recarga SOLO cuando ya llego a cero, y al apagar limpia los dos campos.
-- Asi el contador baja solo y su bit 1 va alternando, que es el ciclo 50/50 del
-- juego; y apagar es inmediato.
local function freeze_update()
  -- Apagado NO se toca la memoria NADA. Antes, con el toggle en OFF, se
  -- escribia 0 en $F558 y $F55A en cada frame: 60 escrituras por segundo a una
  -- direccion que ademas estaba mal (ver FRZ), y corrompio el juego entero.
  -- El juego se encarga solo de bajar su propio contador; no hay que limpiarlo.
  if not FREEZE_ON then return end
  if not memory.writeword then return end

  -- Solo recarga cuando ya llego a cero. Recargarlo siempre dejaria el bit 1
  -- del contador permanentemente en 1 y el juego quedaria PAUSADO, no en camara
  -- lenta: el dispatcher decide con ese bit (subq.w #$1 / btst.b #$1).
  -- Con el valor que usa el juego para las cinematicas, 160 ($A0).
  if rw(FRZ.f) <= 0 then
    memory.writeword(FRZ.f, FRZ.hold)
  end
end

-- El gasto que se muestra. Es solo spent: el pending queda oculto hasta que un
-- golpe abre la cadena y lo adopta.
local function combo_spent()
  return combo.spent
end

-- Una vez por frame. Lee, saca deltas y decide.
local function combo_update()
  local hp   = rws(P2 + O.HP)
  local stun = rw(P2 + O.STUN)
  local mana = rw(P1 + O.MP)
  local c6   = combo_native()

  local d_hp   = prev_hp - hp
  local d_stun = prev_stun - stun
  local d_mana = mana - prev_mana

  -- Round nuevo: la vida sube a tope de golpe. Todo a cero. El salto lo tiene que
  -- haber hecho el juego, no nosotros: si el relleno disparo esto, se perderia
  -- el panel recien cerrado.
  if hp > prev_hp + 32 then
    if self_refill then
      self_refill = false
    else
      combo_full_reset()
    end
  end

  -- Captura del maximo de vida del personaje. Sirve cualquier subida de vida:
  -- cuando el juego la pone a tope, ese valor ES el maximo. Con eso se evita
  -- escribir 255 en un personaje que da 223.
  if hp > prev_hp and hp > 0 then
    p2_hp_max = hp
    p1_hp_max = rws(P1 + O.HP)
  end

  -- Cuenta de frames sin golpe, para la regeneracion por tiempo. El contador de
  -- golpes REALES va aparte: el chippeo no lo reinicia, que es lo que hacia que
  -- bloqueando con habilidades la cadena y la regen vivieran eternas.
  frames_since_hit = frames_since_hit + 1
  frames_since_real = frames_since_real + 1
  if d_hp > 0 then
    frames_since_hit = 0
    if d_stun > 0 then frames_since_real = 0 end
    last_hit_frame = frame_id
    last_hp = d_hp
    last_stun = d_stun
  end

  -- Se dispara por TIEMPO: un segundo sin recibir un golpe REAL y se rellena, sin
  -- necesidad de tocar nada. Usa frames_since_real y no frames_since_hit para que
  -- el chippeo de un bloqueo no lo siga aplazando indefinidamente.
  if REFILL_ON_COMBO_END and frames_since_real >= REGEN_FRAMES and needs_refill() then
    combo_refill()
  end

  -- El nativo dice si la cadena sigue viva. No decide cuando acumular: eso lo
  -- hace el golpe, porque va un golpe atrasado.
  combo.live = (c6 > 0)

  -- --- el golpe ---
  if d_hp > 0 then
    -- El chippeo es dano SIN stun: asi lo distinguirgo, sin tocar el camino de
    -- los golpes reales. Un golpe de verdad siempre resta stun (01f42c).
    local chip = (d_stun <= 0)

    if chip and frames_since_real > COMBO_GAP then
      -- Bug reportado: bloqueando, las habilidades tiran chippeo sin parar y la
      -- cadena no se rompia nunca, porque $C6 no baja a 0 mientras la victima
      -- sigue en el rango de hitstun. Un chippeo aislado NO continua la cadena:
      -- abre una nueva de 1. Los golpes reales NO entran por esta rama, asi que
      -- el contador de combos queda intacto.
      combo.hits = 1
      combo.dmg = d_hp
      combo.stun = 0
      combo.gained = 0
      combo.spent = combo.pending
      combo.pending = 0
      -- Foto inicial del maná para el neto. Se toma con la cadena recien
      -- abierta, asi que el gasto de la habilidad que la abrio (pagado antes de
      -- conectar) queda incluido en la diferencia.
      combo.mana_base = mana + combo.pending
      combo.net = 0
      combo.net_frozen = false
    elseif c6 > 0 then
      -- El nativo dice que hay cadena abierta: este golpe continua la anterior.
      combo.hits = combo.hits + 1
      combo.dmg  = combo.dmg + d_hp
      if d_stun > 0 then combo.stun = combo.stun + d_stun end
    else
      -- Cadena NUEVA. Sirve tanto para el primer golpe de un combo real como
      -- para un golpe suelto: en los dos casos el panel muestra ese golpe solo.
      combo.hits = 1
      combo.dmg  = d_hp
      combo.stun = (d_stun > 0) and d_stun or 0
      combo.gained = 0
      -- El gasto de la habilidad que abrio esta cadena entra ahora: estaba en
      -- pending porque se pago antes de que existiera la cadena.
      combo.spent = combo.pending
      combo.pending = 0
      -- Foto inicial del maná para el neto. Se toma con la cadena recien abierta, MAS
      -- el pending.
      --
      -- Sumar el pending es lo que hace que el gasto de la habilidad cuente: el
      -- coste se paga al LANZAR, o sea ANTES de que el primer golpe abra la
      -- cadena. Sin sumarlo, un combo de una sola habilidad daba siempre 0.
      --
      -- Y no arrastra las habilidades que fallaron: si se tiro una al aire y
      -- despues se encadeno un golpe normal, el pending de la fallada se
      -- suma aqui pero el maná actual tambien lo descuenta, y se cancelan.
      combo.mana_base = mana + combo.pending
      combo.net = 0
      combo.net_frozen = false
    end
  end

  -- El gasto y la ganancia por deltas quedan SOLO para la consola: ya no son la
  -- cifra que se muestra, porque fallan con las habilidades que no gastan maná.
  if d_mana < 0 then
    if combo.live then
      combo.spent = combo.spent - d_mana
    else
      combo.pending = combo.pending - d_mana
    end
  elseif d_mana > 0 and combo.live then
    -- Filtro de relleno: $01B462 manda el gauge a 223 entero. Si venia de lejos
    -- y el salto es grande, es relleno, no premio por combo.
    local refill = (mana >= LIM.mpMax) and (LIM.mpMax - prev_mana) > 16
    if not refill then combo.gained = combo.gained + d_mana end
  end

  -- --- el NETO, que es lo unico que se muestra ---
  --
  -- Se recalcula mientras la cadena este viva o sea reciente. Cuando pasa mucho
  -- tiempo sin golpe real se congela, para que el panel quede con el resultado
  -- del ultimo combo y no siga contando.
  if not combo.net_frozen then
    if combo.live or frames_since_real <= COMBO_GAP then
      combo.net = mana - combo.mana_base
    end
  end

  prev_hp = hp
  prev_stun = stun
  prev_mana = mana
end
--------------------------------------------------------------------------------
-- Dibujo de las cajas
--------------------------------------------------------------------------------
local function draw_boxes()
  local filter = owner_filter()

  -- Fuente de los contadores, en este orden:
  --   1) cache del exec hook (momento exacto de la colision)
  --   2) write hooks sobre los contadores
  --   3) lectura directa (solo sirve si no se limpiaron todavia)
  --
  -- Cada snapshot se sella con frame_id: solo vale en el frame exacto en que
  -- se capturo.
  local use, src = nil, ""
  if exec_stamp == frame_id then
    use, src = counts, "exec"
  elseif wr_seen and wr_frame == frame_id then
    use = {}
    for i = 1, #LISTS do
      use[i] = box_count(wr_counts[i], LISTS[i].stride)
    end
    src = "wr"
  end
  if not use then
    -- SIN fuente fresca NO se dibuja nada, y esto es lo que arregla las cajas
    -- que quedaban pegadas en el aire cuando terminaba la animacion.
    --
    -- El builder solo escribe el contador cuando mete una caja (0x1EC84), y
    -- $01EDAC lo pone a 0 en los cinco, todos los frames (0x1EDC2..0x1EDDA).
    -- O sea que un write por frame SIEMPRE llega. Si no hay write, no hay caja.
    --
    -- El fallback "raw" de antes leia el contador directo, y ahi se colgaba: en
    -- el frame en que el dispatcher se salta el borrado (0x01EDB2, bne $1ee1c)
    -- el contador conserva el valor viejo y el builder ya no lo toca, asi que
    -- la ultima hitbox/clashbox se quedaba dibujada en el aire.
    if RAW_FALLBACK then
      use = {}
      for i = 1, #LISTS do
        use[i] = box_count(rw(LISTS[i].cnt), LISTS[i].stride)
      end
      src = "raw"
    else
      -- Ceros explicitos: si `use` queda vacia, `use[i]` es nil y mas abajo
      -- `drawn = drawn + use[i]` revienta con "arithmetic on a nil value".
      use = {}
      src = "stale"
      for i = 1, #LISTS do
        use[i] = 0
      end
      -- Si hay contador != 0 sin write, los write hooks estan muertos. Avisar
      -- una sola vez, porque si no el HUD entero desaparece sin explicar.
      --
      -- Solo tiene sentido si YA vimos un write: al arrancar, antes del primer
      -- write, los contadores tienen el valor que dejo la pantalla anterior y
      -- el aviso saltaba siempre en el frame 1, mintiendo.
      if not raw_warned and wr_seen then
        for i = 1, #LISTS do
          if box_count(rw(LISTS[i].cnt), LISTS[i].stride) > 0 then
            raw_warned = true
            print("[yuyu] AVISO: contador != 0 sin write este frame. "
                .. "Los write hooks de los contadores no estan entrando; "
                .. "poner RAW_FALLBACK = true para ver, pero el bug de la caja "
                .. "colgada vuelve.")
            break
          end
        end
      end
    end
  end

  local drawn = 0
  local really_drawn = 0
  local off_screen = 0

  for i = 1, #LISTS do
    local L = LISTS[i]
    if L.on() then
      drawn = drawn + use[i]
      -- Datos desde la instantanea del hook, no desde memoria. Ver la nota de
      -- wr_boxes: leerlos al dibujar mete un frame de atraso.
      local snap = wr_boxes[i]
      for k = 0, use[i] - 1 do
        local owner, bx, by, rx, ry, pw, ph
        local d = snap and snap[k]
        if d then
          owner, bx, by, rx, ry, pw, ph = d.owner, d.bx, d.by, d.rx, d.ry, d.pw, d.ph
        else
          -- Sin instantanea (todavia no hubo write, o la lista no paso por el
          -- hook): se lee en vivo, que es mejor que no dibujar nada.
          local a = L.base + k * L.stride
          owner = rw(a + 0x0C)
          bx = rws(a + 0x00)
          if L.stride == 0x20 then
            -- Descriptor de grab: NO es una caja de 16 bytes. El builder
            -- ($0161C2..$0161F0) escribe X en +0, Y en +2, rx en +4 y ry en
            -- +5. Y va en +2 y no en +4: leer +4 cogia los radios.
            by = rws(a + 0x02)
            rx = rb(a + 0x04)
            ry = rb(a + 0x05)
          else
            by = rws(a + 0x04)
            rx = bit.band(rb(a + 0x08), 0x7F)
            ry = rb(a + 0x09)
          end
          local ob0 = owner_base(owner)
          if ob0 then
            pw = rw(ob0 + O.WORLD_LO)
            ph = rw(ob0 + O.WORLDY_LO)
          end
        end
        local ob = owner_base(owner)
        if (not filter) or own_lo(owner) == filter then
          -- OJO: el filtro tiene que ser OR, no AND. Muchas hitboxes de
          -- proyectil tienen un radio en 0 (son finas, tipo linea o rayo), y con
          -- AND no se dibujaban nunca. Un radio en 0 se dibuja como 1 px.
          if rx > 0 or ry > 0 then
            local ex = rx > 0 and rx or 1
            local ey = ry > 0 and ry or 1
            -- La caja de grab se captura UNA VEZ por personaje, en el MISMO frame en que
            -- el juego la escribe. Antes se exigian 40 frames seguidos con el
            -- descriptor presente, pero solo existe 1 (ver la nota de grab_mem).
if L.stride == 0x20 and ob then
              local key = moves_key(ob)
              if not grab_mem[key] then
                -- Offset con la posicion del dueno TOMADA EN LA MISMA INSTANTE
                -- que la caja (viene en el snapshot como pw/ph). Antes se
                -- comparaba contra la posicion del personaje leida al final del
                -- frame, y si se movio entre medias el offset salia corrido.
                local dxm = math.abs(bx - d.pw)
                local dy  = by - d.ph

                -- MATCH EXACTO contra los tres builders del ROM. Antes se
                -- guardaba la lectura "mas parecida" con una heuristica y un
                -- plazo de 40 frames que nunca se cumplia (el descriptor solo
                -- existe 1 frame), asi que nunca se capturaba nada.
                --
                -- Los tres tienen el mismo radio salvo en Y, asi que primero se
                -- descarta por dy y luego se confirma con dx y los radios.
                local hit, name = nil, "?"
                for i = 1, #GRAB_KINDS do
                  local K = GRAB_KINDS[i]
                  if dy == K.dy and dxm == K.dxm and ex == K.rx and ey == K.ry then
                    hit = K
                    name = ("$%04X" % (i == 1 and 0x0161BA or (i == 2 and 0x0175E6 or 0x018342)))
                    break
                  end
                end

                if hit then
                  grab_mem[key] = hit
                  print(string.format(
                    "[yuyu] grab: personaje medido -> builder %s  "
                    .. "%dx%d  dx=%d dy=%d  mov=$%02X sep=%d",
                    name, hit.rx, hit.ry, hit.dxm, hit.dy, hit.mov, hit.sep))
                elseif not grab_warned[key] then
                  grab_warned[key] = true
                  print(string.format(
                    "[yuyu] grab: no coincide con ningun builder (dxm=%d dy=%d "
                    .. "%dx%d). Los tres del ROM son 16/-48, 16/-16 y 24/-48.",
                    dxm, dy, ex, ey))
                end
              end
            end
            local sx, sy = to_screen(ob or owner, bx, by)
            -- Se recorta a la pantalla. Una caja con el centro en 312 y radio 14
            -- llegaba a x2=326 con la pantalla en 320: si drawline no dibuja fuera
            -- del área visible, esa caja se perdía entera.
            local sw2, sh2 = emu.screenwidth(), emu.screenheight()
            local x1 = sx - ex; local y1 = sy - ey
            local x2 = sx + ex; local y2 = sy + ey
            if x1 < 0 then x1 = 0 end
            if y1 < 0 then y1 = 0 end
            if x2 > sw2 - 1 then x2 = sw2 - 1 end
            if y2 > sh2 - 1 then y2 = sh2 - 1 end
            if x2 > x1 and y2 > y1 then
              draw_box(x1, y1, x2, y2, L.line, L.style, nil, L.width)
              really_drawn = really_drawn + 1
            else
              off_screen = off_screen + 1
            end
          end
        end
      end
    end
  end

  -- Sonda: una linea cada 60 frames con cuantos se dibujaron y el origen.
  probe_n = probe_n + 1
  if probe_n % 60 == 0 then
    local ax, ay = player_screen(P1)
    -- Los contadores van CON NOMBRE. Antes salia "push 2 0 6 0 0" y habia que
    -- acordarse del orden para saber cual era el grab.
    local parts = {}
    for i = 1, #LISTS do
      parts[#parts + 1] = string.format("%s=%d", LISTS[i].name, use[i])
    end
    print(string.format("[yuyu] dib=%d realmente=%d fuera=%d src=%s pj=%d,%d | %s",
      drawn, really_drawn, off_screen, src, ax, ay, table.concat(parts, " ")))
    print(string.format("[yuyu] pantalla=%dx%d", emu.screenwidth(),
          emu.screenheight()))

    -- Medidas reales de la PRIMERA caja de cada lista, tomadas de la MISMA
    -- instantanea que se dibuja. Distingue tres fallos que desde la pantalla se
    -- ven iguales: contador en 0 (no hay caja), radios en 0 (no se dibuja) y
    -- coordenadas fuera de pantalla (se dibuja donde no se ve).
    local meas = {}
    for i = 1, #LISTS do
      local L = LISTS[i]
      local d = wr_boxes[i] and wr_boxes[i][0]
      if use[i] > 0 and d then
        local sx, sy = to_screen(owner_base(d.owner) or d.owner, d.bx, d.by)
        meas[#meas + 1] = string.format("%s n=%d r=%dx%d org=%s pant=%d,%d w=%d",
          L.name, use[i], d.rx, d.ry, tostring(d.owner), sx, sy, L.width)
      else
        meas[#meas + 1] = string.format("%s n=%d", L.name, use[i])
      end
    end
    print("[yuyu] cajas: " .. table.concat(meas, " | "))

    -- Estado del grab por separado: el marcador medido, y el contador crudo del
    -- descriptor. Si el contador nunca pasa de 0, el builder de grab no esta
    -- corriendo o el hook del contador no entra.
    print(string.format(
      "[yuyu] grab: contador=%d | marcador capturado=%s",
      use[4],
      (function()
        for k, v in pairs(grab_mem) do
          return string.format("si (%dx%d dx=%d dy=%d)", v.rx, v.ry, v.dxm, v.dy)
        end
        return "NO"
      end)()))
    -- Diagnostico del panel de combo. Se imprime TODO el estado de una vez para
    -- poder ver de un vistazo cual de los acumuladores se mueve y cual no.
    print(string.format(
      "[yuyu] combo: HIT=%d (nativo=%d) live=%s | dmg=%d stun=%d gastado=%d ganado=%d (pend=%d)",
      combo.hits, combo_native(), tostring(combo.live), combo.dmg, combo.stun,
      combo_spent(), combo.gained, combo.pending))
    print(string.format(
      "[yuyu] lectura: hpP2=%d stnP2=%d mpP1=%d | ultimo golpe: hace %df hp=%d stun=%d",
      rws(P2 + O.HP), rw(P2 + O.STUN), rw(P1 + O.MP),
      last_hit_frame < 0 and -1 or (frame_id - last_hit_frame), last_hp, last_stun))

    -- Localizador de slots: el HP maximo depende del personaje (este da 223, no
    -- 255), asi que buscar 255 no encuentra nada. Se dumpean los offsets
    -- conocidos de cada base candidata de $400 para ver cual esta poblada.
    if probe_n % 300 == 0 then
      local rows = {}
      for base = 0xFF8000, 0xFF9400, 0x400 do
        rows[#rows + 1] = string.format("$%X hp=%d stn=%d mp=%d",
          base, rw(base + O.HP), rw(base + O.STUN), rw(base + O.MP))
      end
      print("[yuyu] slots: " .. table.concat(rows, " | "))
    end
  end
end

--------------------------------------------------------------------------------
-- Grab fijo: rango de agarre siempre visible, siguiendo al personaje
--
-- Se dibuja con los offsets memorizados de la ultima caja REAL. El signo del
-- offset en X se recalcula cada frame con el facing, igual que hace el builder
-- ("addi.w #$10" si facing == 0, "subi.w #$10" si no), asi que el marcador se
-- da vuelta cuando el personaje cambia de lado.
--
-- La BASE del recuadro va a la altura de la linea horizontal de la cruz, que
-- es donde estan los pies: se ancla por abajo, no por el centro.
--------------------------------------------------------------------------------
local function draw_grab_range()
  local L = list_by("grab")
  if not (L and L.on()) then return end

  -- Se dibuja SIEMPRE, aunque nunca se haya agarrado a nadie con este personaje.
  -- Los tres valores posibles salen del CODIGO del juego (GRAB_KINDS), no de
  -- inventarlos: el "~" de la etiqueta avisa que todavia no sabemos cual de los
  -- tres le toca a este personaje.
  local key = moves_key(P1)
  local m = grab_mem[key] or GRAB_DEFAULT
  local medido = grab_mem[key] ~= nil

  local ax, ay = player_screen(P1)
  local dx = m.dxm + GRAB_X_FIX
  if rb(P1 + O.FACING) ~= 0 then dx = -dx end
  local sx = ax + dx
  -- sy es el CENTRO de la caja, no su borde. Se dibujaba de (sy - ry*2) a sy,
  -- o sea medio radio demasiado arriba: por eso el marcador salia en una
  -- posicion que no correspondia. Va de sy-ry a sy+ry.
  local sy = ay + m.dy

  -- Punteado con paso 12, el TRIPLE que la hurt (que usa 4). Misma guirnalda de
  -- 2 px, pero con los puntos bien separados: si no, los dos punteados del
  -- juego son indistinguibles.
  draw_box(sx - m.rx, sy - m.ry, sx + m.rx, sy + m.ry,
           L.line, "dashed", 4, 1, 12)
  hud_text(sx + m.rx + 3, sy - m.ry,
           string.format("grab%s %d %dx%d", medido and "" or " ~",
                         dx, m.rx * 2, m.ry * 2),
           0xFF00FFFF)
end

--------------------------------------------------------------------------------
-- Eje del personaje y cuadricula
--------------------------------------------------------------------------------
local function draw_axis()
  if not SHOW_AXIS then return end
  local px, py = player_screen(P1)
  gui.drawline(px - 10, py, px + 10, py, 0xFFFFFFFF)
  gui.drawline(px, py - 10, px, py + 10, 0xFFFFFFFF)
  gui.drawline(px - 24, py - 48, px + 24, py - 48, 0xFF60FF60)
  gui.drawline(px - 24, py, px + 24, py, 0xFF60FF60)
  gui.drawline(px - 24, py - 48, px - 24, py, 0xFF60FF60)
  gui.drawline(px + 24, py - 48, px + 24, py, 0xFF60FF60)
  if SHOW_COORD then
    gui.text(px + 26, py - 4, string.format("%d,%d", px, py), 0xFFFFFFFF)
  end
end

-- Grid de calibracion. Esta para medir, no para verse: por eso es casi invisible
-- y etiqueta CADA linea, no solo las mayores. Con la de 16 se puede leer en que
-- pixel cae cada cosa y decir la coordenada exacta.
--
-- drawline es de 1 px, asi que "mas delgada" no se puede: lo que se baja es el
-- alpha. Las mayores se dejan un poco mas visibles que las menores para no
-- perder el punto de referencia de cada 64.

local function draw_grid()
  if not SHOW_GRID then return end
  local sw, sh = emu.screenwidth(), emu.screenheight()

  for x = 0, sw, GRID_STEP do
    local major = (x % 64) == 0
    gui.drawline(x, 0, x, sh, major and COL.gridMajor or COL.gridMinor)
    -- Etiqueta en todas, pegada arriba. Con numeros de 3 digitos se lee el
    -- valor completo, que es lo que hace falta para ubicar las barras.
    gui.text(x + 1, 1, tostring(x), major and COL.gridTxt or 0x60C0C0FF)
  end

  for y = 0, sh, GRID_STEP do
    local major = (y % 64) == 0
    gui.drawline(0, y, sw, y, major and COL.gridMajor or COL.gridMinor)
    -- Etiqueta a la izquierda. Se dibuja DESPUES de la linea vertical de x=0,
    -- asi que el 0 queda arriba a la izquierda.
    gui.text(2, y + 1, tostring(y), major and COL.gridTxt or 0x60C0C0FF)
  end
end

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------
local function bar(x, y, w, h, ratio, fill, line)
  ratio = math.max(0, math.min(1, ratio or 0))
  gui.box(x, y, x + w, y + h, 0xB0000000, line)
  local fw = math.floor(w * ratio)
  if fw > 0 then
    gui.box(x, y, x + fw, y + h, fill, line)
    gui.drawline(x + 1, y + 1, x + fw - 1, y + 1, 0x60FFFFFF)
  end
  return fw
end

-- Mezcla dos colores de FBNeo (0xAARRGGBB). Se usa para el gradiente.
local function lerp_col(c1, c2, t)
  local function ch(sh) return bit.band(bit.rshift(c1, sh), 0xFF) end
  local function ch2(sh) return bit.band(bit.rshift(c2, sh), 0xFF) end
  local function mix(a, b) return math.floor(a + (b - a) * t + 0.5) end
  return bit.bor(bit.lshift(mix(ch(24), ch2(24)), 24),
                 bit.lshift(mix(ch(16), ch2(16)), 16),
                 bit.lshift(mix(ch(8),  ch2(8)),  8),
                 mix(ch(0), ch2(0)))
end

-- Relleno con GRADIENTE VERTICAL de tres paradas: blanco arriba, celeste en
-- el medio, azul fuerte abajo. Se dibuja con drawline fila por fila porque
-- gui.box no sabe gradientes.

local function bar_grad(x, y, w, h, ratio)
  ratio = math.max(0, math.min(1, ratio or 0))
  gui.box(x, y, x + w, y + h, 0xB0000000, 0xFF000000)
  local fw = math.floor(w * ratio)
  if fw <= 0 then return 0 end
  for i = 0, h - 1 do
    local t = (h > 1) and (i / (h - 1)) or 0
    local c = (t <= 0.5) and lerp_col(COL.gradTop, COL.gradMid, t * 2)
                      or lerp_col(COL.gradMid, COL.gradBot, (t - 0.5) * 2)
    gui.drawline(x, y + i, x + fw, y + i, c)
  end
  return fw
end

-- Texto con OUTLINE NEGRO y mas gordo: se pinta el glifo en negro en las ocho
-- direcciones y encima el de color. El contorno de 1 px alrededor es lo que lo
-- hace ver bold sin necesitar una fuente bold.
local function text_bold(x, y, s, col)
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        gui.text(x + dx, y + dy, s, 0xFF000000)
      end
    end
  end
  gui.text(x, y, s, col)
end

-- El maná se resume en UNA sola cifra, el NETO (ganado menos gastado). Antes
-- se mostraban las tres por separado y era mucho ruido para lo que dice.
local function draw_combo()
  if not SHOW_COMBO then return end

  local x, y = POS.combo.x, POS.combo.y
  local net = combo.net

  -- Fondo con SOLO 3 lados: superior, izquierdo e inferior. El borde derecho se
  -- borra a proposito, asi el bloque queda abierto y no parte la pantalla en dos.
  gui.box(x - 3, y - 4, x + 56, y + 40, 0xB0000000, 0xFF5070A0)
  gui.drawline(x + 56, y - 4, x + 56, y + 40, 0x00000000)

  -- Conteo propio. El nativo $C6 va un golpe atrasado (el primer impacto cae en
  -- el reset en vez de incrementar), asi que mostraria uno menos.
  text_bold(x, y, string.format("HIT %d", combo.hits), 0xFFFFFFFF)
  text_bold(x, y + 10, string.format("DMG %d", combo.dmg), 0xFFFFC060)
  text_bold(x, y + 20, string.format("STN %d", combo.stun), 0xFFC060FF)
  text_bold(x, y + 30, string.format("%s%d", net >= 0 and "+" or "", net),
            net >= 0 and 0xFF50FF50 or 0xFFFF5050)
end
local function draw_hud()
  if not SHOW_HUD then return end
  local hp = rws(P1 + O.HP)
  local mp = rw(P1 + O.MP)
  hud_text(POS.numX, POS.numY, string.format("%d", hp),
           hp <= LIM.hpLow and 0xFFFF4040 or 0xFFFFFFFF)
  hud_text(POS.numX, POS.mpY, string.format("%d", mp),
           mp <= LIM.mpLow and 0xFF60C0FF or 0xFFB0E0FF)

  -- P2: mismos numeros a la derecha. El HP de P2 lo tiene que leer con signo
  -- igual que P1 ($78 es signed), y el maná es unsigned (max 223).
  local hp2 = rws(P2 + O.HP)
  local mp2 = rw(P2 + O.MP)
  hud_text(POS.numX2, POS.numY, string.format("%d", hp2),
           hp2 <= LIM.hpLow and 0xFFFF4040 or 0xFFFFFFFF)
  hud_text(POS.numX2, POS.mpY, string.format("%d", mp2),
           mp2 <= LIM.mpLow and 0xFF60C0FF or 0xFFB0E0FF)
end

-- Barra de stun de UN jugador. La misma funcion sirve para P1 y para P2: misma
-- forma, misma marca del maximo global, y el valor "x/y" a la derecha.
local function stun_bar(g, base, fill, line)
  local stun = rw(base + O.STUN)
  local smax = rw(base + O.STUN_MAX)
  if smax <= 0 then return end
  bar(g.x, g.y, g.w, g.h, stun / smax, fill, line)

  -- Marca del maximo global (62): donde cae el tope de ESE personaje sobre la
  -- escala de todos.
  local mx = g.x + math.floor(g.w * smax / STUN_GLOBAL_MAX)
  if mx > g.x and mx < g.x + g.w then
    gui.drawline(mx, g.y, mx, g.y + g.h, 0xFFFFFFFF)
  end

  -- El valor va a la derecha de la barra, en texto PLANO: hud_text mete sombra
  -- en colores claros y contorno en los oscuros, y en un numero chico eso lo
  -- engorda hasta volverlo ilegible. Va 1 px mas abajo que la barra.
  text_plain(g.x + g.w + 2, g.y, string.format("%d/%d", stun, smax),
             0xFFFFD080)
end

local function draw_stun()
  if not (SHOW_HUD and SHOW_STUN) then return end
  -- Se vacia a medida que cada golpe descuenta del presupuesto ($7E) y llega a
  -- 0 en el knockdown (01f4d6).
  stun_bar(POS.stun,  P1, 0xC0FF9000, 0xFFC0A060)   -- P1: amarilla
  stun_bar(POS.stun2, P2, 0xC0C040FF, 0xFFC090D0)   -- P2: violeta
end

-- Hit-time. OJO: hay DOS sistemas de congelacion y hay que mirar los dos.
--
-- 1) Hitpause del golpe, en $69 (byte del jugador). Lo pone el resolver de
--    hitbox contra hurtbox en $01F2E0 con 16, y el de clash en $01F15E con 28.
--    Baja de a uno por frame ("subi.b #$1,$69(a5)", unas 20 veces en el ROM).
--
-- 2) Congelacion GLOBAL de pantalla, en $F558 con el flag $F55A. La carga la
--    cinematica de los especiales con 160 ("move.w #$a0,$f558.w" en $01FA82).
--
-- En $012AF4 el juego chequea PRIMERO $F55A y solo si esta en cero mira $69:
--   012af4:  cmpi.b #$0,$f55a.w / bne.b $12b2e
--   012afc:  cmpi.b #$0,$69(a5)  / bhi.b $12b36
local function draw_hittime()
  if not SHOW_HITTIME then return end
  local ht = rb(P1 + O.HITPAUSE)
  local gf = rw(FRZ.f)
  local on = rb(FRZ.flag)

  -- No hay barra de BLOCKSTUN. Era un valor fijo de 32 frames escrito a mano,
  -- no leido de la memoria: la direccion que lo mediria nunca se localizo (ver
  -- TABLAS_MOVES_Y_TIMING.md 6). O sea que era una constante de referencia, sin
  -- ningun dato del juego detrás. Se saco.

  local h, w = POS.ht.h, POS.ht.w

  if on ~= 0 and gf > 0 then
    -- Congelacion global de pantalla: manda sobre el hitpause del personaje.
    bar_grad(POS.ht.x, POS.ht.y, w, h, gf / HT_GLOBAL_MAX)
    text_bold(POS.ht.x + w + 3, POS.ht.y + 1,
              string.format("HIT %d", gf), 0xFFFF40FF)
    return
  end

  -- Hitpause del personaje, con la marca en los 16 del golpe normal.
  bar_grad(POS.ht.x, POS.ht.y, w, h, ht / POS.ht.max)
  text_bold(POS.ht.x + w + 3, POS.ht.y + 1,
            string.format("HIT %d", ht),
            ht > 0 and 0xFFFFFFFF or 0x6090B0D0)
  local mark = POS.ht.x + math.floor(w * 16 / POS.ht.max)
  gui.drawline(mark, POS.ht.y, mark, POS.ht.y + h, 0xFFFFE000)
end

--------------------------------------------------------------------------------
-- Input display
--------------------------------------------------------------------------------
local BUTTONS = { "A", "B", "C", "X", "Y", "Z" }

-- Alto total del bloque de teclas, del borde superior al inferior. El elemento
-- que mas abajo baja es la segunda fila de botones ABC/XYZ: by + 6 + 11 + 9.

-- Devuelve la Y donde tiene que quedar el BORDE INFERIOR del indicador: el
-- borde superior del primer cuadrado de la grid contando desde abajo.
--
-- La grid se dibuja en 0, 16, 32 ... hasta screenheight. Con 224 de alto las
-- lineas caen en 0..208 y 224, asi que el primer cuadrado desde abajo es
-- [208, 224] y su parte superior es 208. Si la ultima linea cae justo en el
-- borde de pantalla, el cuadrado de abajo es ese ultimo tramo y hay que subir
-- una linea.
local function grid_anchor_y()
  local sh = emu.screenheight()
  local last = math.floor(sh / GRID_STEP) * GRID_STEP
  if last >= sh then last = last - GRID_STEP end
  return last
end

local function draw_input()
  if not SHOW_INPUT then return end
  local pad = joypad.get()
  local sw = emu.screenwidth()
  -- Derecha: arriba el juego ya pone los retratos y las barras de los dos
  -- jugadores, y el display se solapaba con las de P2.
  --
  -- Las barras de stun / hit-time viven a la izquierda (x = 4..68), asi que
  -- subir este bloque hasta la linea de grid no las pisa.
  local bx = sw - POS.keys.w
  local by = grid_anchor_y() - POS.keys.h
  local cx, cy = bx + 10, by + 14
  local c = 0x80808080
  local on = 0xFFFFFFFF
  local function arm(x, y, w, h, pressed)
    gui.box(x, y, x + w, y + h, pressed and on or 0x00000000, c)
  end
  arm(cx - 9, cy - 3, 6, 6, pad["P1 Left"])
  arm(cx + 3, cy - 3, 6, 6, pad["P1 Right"])
  arm(cx - 3, cy - 9, 6, 6, pad["P1 Up"])
  arm(cx - 3, cy + 3, 6, 6, pad["P1 Down"])
  arm(cx - 3, cy - 3, 6, 6, false)

  for i = 1, #BUTTONS do
    local col = (i - 1) % 3
    local row = (i - 1) < 3 and 0 or 1
    local x = bx + 26 + col * 11
    local y = by + 6 + row * 11
    local pressed = pad["P1 Button " .. BUTTONS[i]]
    gui.box(x, y, x + 9, y + 9, pressed and on or 0x00000000, c)
    gui.text(x + 3, y + 2, BUTTONS[i], 0xFFE0E0E0)
  end

  -- Mode arriba y Start abajo, apilados: en horizontal se salian de pantalla.
  local mx = bx + 58
  local mode, start = pad["P1 Mode"], pad["P1 Start"]
  gui.box(mx, by + 3, mx + 21, by + 12, mode and on or 0x00000000, c)
  gui.text(mx + 3, by + 5, "MODE", mode and on or 0xFFE0E0E0)
  gui.box(mx, by + 14, mx + 21, by + 23, start and on or 0x00000000, c)
  gui.text(mx + 3, by + 16, "START", start and on or 0xFFE0E0E0)
end

--------------------------------------------------------------------------------
-- Historial de botones
--
-- Los ultimos pulsados de P1 en orden, a la izquierda del titulo, hasta el
-- borde. El mas reciente queda pegado al titulo. Los botones NO desaparecen:
-- se acumulan y los viejos se corren a la izquierda. Al entrar pegan un
-- destello que se baja a HIST_DIM y ahi se quedan. Debajo va el numero de
-- frames desde la pulsada anterior, que es lo que sirve para leer frame data.
--------------------------------------------------------------------------------
local HIST_MAX  = 14
local HIST_GLOW = 14
local HIST_DIM  = 0.72

-- El tercer campo, si esta, es la direccion del triangulo a dibujar en vez de
-- la letra: las cuatro flechas de la cruceta se dibujan como triangulos.
local HIST_KEYS = {
  { "A", "P1 Button A" }, { "B", "P1 Button B" }, { "C", "P1 Button C" },
  { "X", "P1 Button X" }, { "Y", "P1 Button Y" }, { "Z", "P1 Button Z" },
  { "L", "P1 Left", "left" },   { "R", "P1 Right", "right" },
  { "U", "P1 Up", "up" },       { "D", "P1 Down", "down" },
  { "M", "P1 Mode" },           { "S", "P1 Start" },
}

local hist = {}
local hist_n = 0
local prev_pressed = {}
local own_frame = 0
local last_press_frame = 0

local function update_history()
  local pad = joypad.get()
  for i = 1, #HIST_KEYS do
    local name, key = HIST_KEYS[i][1], HIST_KEYS[i][2]
    -- joypad.get() solo trae las teclas pulsadas; el resto es nil, no false.
    local down = pad[key] and true or false
    if down and not prev_pressed[name] then
      hist_n = hist_n + 1
      if hist_n > HIST_MAX then
        for j = 1, hist_n - 1 do hist[j] = hist[j + 1] end
        hist_n = HIST_MAX
      end
      hist[hist_n] = { name = name, dir = HIST_KEYS[i][3], age = 0,
                       gap = own_frame - last_press_frame }
      last_press_frame = own_frame
    end
    prev_pressed[name] = down
  end
  own_frame = own_frame + 1
  for j = 1, hist_n do
    hist[j].age = hist[j].age + 1
  end
end

local function draw_history()
  if not SHOW_HISTORY then return end
  local sw = emu.screenwidth()
  -- Franja INFERIOR de la grid: entre la linea 0 y la 1, o sea los 16 px de
  -- abajo, y de x = 0 hasta la ultima linea vertical. El historial vive aca,
  -- no arriba al lado del titulo.
  local ay = grid_anchor_y()
  for j = hist_n, 1, -1 do
    local slot = hist_n - j           -- 0 = el mas reciente
    local x = slot * 14
    if x + 10 > sw then break end
    local h = hist[j]
    local glow = 1.0
    if h.age > 1 then
      local t = (h.age - 1) / HIST_GLOW
      if t > 1 then t = 1 end
      glow = 1.0 - (1.0 - HIST_DIM) * t
    end
    local col = 0xFF000000 + math.floor(0xFF * glow)
    -- Chip de 8 px de alto y el numero de frames debajo, en los otros 8: asi
    -- entra justo en la franja de 16 px sin pasarse.
    gui.box(x, ay, x + 10, ay + 8, 0x60000000, col)
    if h.dir then
      tri(x + 5, ay + 4, h.dir, col)
    else
      gui.text(x + 3, ay, h.name, col)
    end
    if SHOW_TIMELINE and slot > 0 and h.gap < 100 then
      gui.text(x + 2, ay + 8, string.format("%d", h.gap),
               0xFF00FF00 + math.floor(0x7F * glow))
    end
  end
end

-- Dibuja el logo "N#ga" en (ox, oy).
--
-- Capas, de la mas lejana a la mas cercana:
--   1) silueta negra 1 px mas grande que cada capa (el reborde)
--   2) relleno de la capa en su tono
--   3) al final la cara frontal con la rampa vertical y el brillo que pasa
local function draw_logo(ox, oy, t)
  local n = #LOGO_ORDER
  local total = n * LOGO_CELL

  -- Cuanto extrusion hay ahora: alterna 2 y 3 capas, asi el relieve "respira".
  local depth = 2 + (math.sin(t * 0.8) > 0 and 1 or 0)
  -- El logo flota 1 px arriba y abajo.
  local bob = (math.sin(t * 1.7) > 0) and 0 or -1

  -- Posicion del brillo especular: recorre de izquierda a derecha y vuelve.
  local sweep = ((t * 34) % (total + 24)) - 12

  for gi = 1, n do
    local strokes = LOGO[LOGO_ORDER[gi]]
    local gx = ox + (gi - 1) * LOGO_CELL
    local gy = oy + bob

    -- Capas de extrusion, de lejos a cerca.
    for d = depth, 1, -1 do
      local shade = LOGO_DEPTH[d] or LOGO_DEPTH[#LOGO_DEPTH]
      for i = 1, #strokes do
        local s = strokes[i]
        -- Negro 1 px mas grande: separa esta capa de la de atras.
        gui.box(gx + s[1] + d, gy + s[2] + d,
                gx + s[1] + s[3] + d, gy + s[2] + s[4] + d, LOGO_BLACK)
        gui.box(gx + s[1] + d, gy + s[2] + d,
                gx + s[1] + s[3] + d - 1, gy + s[2] + s[4] + d - 1, shade)
      end
    end

    -- Cara frontal: rampa vertical + brillo especular, fila por fila.
    for i = 1, #strokes do
      local s = strokes[i]
      for row = 0, s[4] - 1 do
        local ry = s[2] + row
        local step = math.floor(ry * #LOGO_RAMP / LOGO_H)
        if step >= #LOGO_RAMP then step = #LOGO_RAMP - 1 end
        local col = LOGO_RAMP[step + 1]
        -- El brillo: una banda clara que pasa por las letras.
        local px = gx + s[1]
        local near = math.abs(px - sweep)
        if near < 7 then
          col = 0xFFFFFFFF
        end
        gui.box(px, gy + ry, gx + s[1] + s[3] - 1, gy + ry, col)
      end
    end
  end
end

-- "training lua": va al lado del logo, en el espacio reservado de
-- x=80..160, y=192..208. La fuente del emulador mide 6 px de avance, asi que 12
-- letras son 72 px y entran justos.
local function draw_subtitle(ox, oy)
  local s = "training lua"
  gui.text(ox + 1, oy + 1, s, LOGO_BLACK)      -- sombra
  gui.text(ox, oy, s, 0xFFB0C8E8)
end

--------------------------------------------------------------------------------
-- HALL DE LA FAMA — pantalla de ganadores.
--
-- Se abre desde el boton del menu y se cierra con cualquier boton. Trae el
-- titulo con una bandera a cada lado y el podio con las estrellas de cada uno.
local function draw_hall(t)
  local sw, sh = emu.screenwidth(), emu.screenheight()

  -- VELO sobre el escenario: oscurece la pantalla como un filtro, dejando ver
  -- el juego detras.
  --
  -- Se hace con drawline y NO con gui.box porque gui.box IGNORA el alpha y
  -- pinta opaco (con el nunca se ve un filtro). El color de drawline va en
  -- 0xRRGGBBAA, o sea el ALPHA es el ultimo byte: negro al 60% es
  -- 0x00000099.
  local VEIL = 0x00000099
  for y = 0, sh - 1 do
    gui.drawline(0, y, sw, y, VEIL)
  end

  -- HOLA TILIN, honorary row ARRIBA del titulo, con un ojo violeta a la DERECHA
  -- en lugar de estrellas.
  --
  -- No va en HALL porque NO es un puesto del ranking: HALL dibuja una tabla con
  -- posiciones y recompensas, y el #0 va arriba de todo, con otro formato.
  local H0_NAME = "HolaTilin"
  local H0_RANK = "#0"

  -- Ancho del bloque: el nombre mas el ojo, para poder centrarlo bien.
  local EYE_W = 14
  local h0_w = #H0_RANK * TXT_ADV + 4 + #H0_NAME * TXT_ADV + 6 + EYE_W
  local h0_x = math.floor((sw - h0_w) / 2)
  local H0_Y = 4

  -- Placa oscura detras, como el titulo y el primer puesto: sobre el velo el
  -- violeta claro se apagaba.
  --
  -- Termina en H0_Y+9 y NO en +12: las banderas arrancan en y=14, asi que con +12
  -- la placa se metia debajo de ellas y las banderas la tapaban.
  gui.box(h0_x - 5, H0_Y - 3, h0_x + h0_w + 5, H0_Y + 9,
          0xFF1A0A22, 0xFF6A3A9A)
  text_bold(h0_x, H0_Y, H0_RANK, 0xFFB070E8)
  text_bold(h0_x + #H0_RANK * TXT_ADV + 4, H0_Y, H0_NAME, 0xFFFFFFFF)
  -- Ojo violeta a la derecha del nombre.
  draw_eye(h0_x + #H0_RANK * TXT_ADV + 4 + #H0_NAME * TXT_ADV + 6, H0_Y)

  local titulo = "Ganadores del torneo argentino"
  -- El avance de la fuente de FBNeo es de unos 7 px por caracter (8 caracteres
  -- ocupaban 62 px), no 6. Con 6 el titulo quedaba corrido a la izquierda.
  local tx = math.floor((sw - #titulo * TXT_ADV) / 2)

  -- Bandera flameando a cada lado del titulo.
  -- Banderas del torneo: SIN llamas. Las llamas doradas quedan solo en la bandera
  -- de N#GA del menu.
  draw_flag(6, 14, 40, 28, t)
  draw_flag(sw - 46, 14, 40, 28, t + 3.1)
  -- El titulo va sobre una placa oscura: asi se lee ENCIMA del velo, siempre,
  -- sin depender de que el texto quede despues o antes del filtro.
  local tw = #titulo * TXT_ADV
  gui.box(tx - 5, 25, tx + tw + 5, 40, 0xFF1A1408, 0xFF8A6A28)
  -- Blanco puro con sombra dura: el doradochico se perdia sobre el velo.
  gui.text(tx + 2, 31, titulo, 0xFF000000)
  text_bold(tx, 29, titulo, 0xFFFFFFFF)
  gui.drawline(tx, 44, tx + tw - 1, 44, 0xFFB08838)

  -- Podio. Cada fila: puesto, nombre, estrellas de oro y de plata.
  --
  -- El bloque va CENTRADO: se mide con el hueco mas ancho (nombre de 9
  -- caracteres + dos estrellas) y se calcula el margenIzquierdo a partir de ahi.
  -- Con posiciones fijas el bloque quedaba pegado a la izquierda.
  local RANK_X, NAME_X, STAR_X = 0, 20, 96
  local block_w = STAR_X + 26
  local bx = math.floor((sw - block_w) / 2) + RANK_X

  local y0 = 56
  for i = 1, #HALL do
    local nombre, oro, plata = HALL[i][1], HALL[i][2], HALL[i][3]
    local ry = y0 + (i - 1) * 26

    -- Fondo alternado, muy tenue, para separar las filas de un vistazo.
    if i % 2 == 0 then
      gui.box(bx - 6, ry - 4, bx + block_w, ry + 18, 0x38101828, 0x00000000)
    end

    -- El primer puesto va en blanco puro con placa oscura debajo: sobre el velo
    -- el dorado se apagaba y parecia que estaba detras del filtro.
    local winner = (i == 1)
    local col = winner and 0xFFFFFFFF or 0xFFE8ECF4
    if winner then
      gui.box(bx + NAME_X - 3, ry - 3,
              bx + NAME_X + #nombre * TXT_ADV + 3, ry + 11,
              0xFF241A06, 0xFF9A7020)
    end
    text_bold(bx + RANK_X, ry, string.format("%d", i), 0xFF9A7020)
    text_bold(bx + NAME_X, ry, nombre, col)

    local sx = bx + STAR_X
    for s = 1, oro do
      draw_star(sx, ry, (i == 1) and 0xFFFFE070 or 0xFFD08010, false)
      sx = sx + 12
    end
    -- La de plata es siempre mas chica que la de oro, como se pidio.
    if plata > 0 then
      draw_star(sx + 2, ry + 2, STAR_SILVER, true)
    end
  end

  -- Pie: como salir. Ahora el hall se cierra con un toque de START, porque MODE
  -- ya solo abre y cierra el menu de toggles.
  local pie = "pulsá START para salir"
  gui.text(math.floor((sw - #pie * TXT_ADV) / 2), sh - 22, pie, 0xFF9AA8C0)
end

-- El aviso "hold mode to open training menu" se muestra solo hasta que se abre
-- el menu por PRIMERA vez. Despues no vuelve a aparecer en la sesion (queda
-- armedado en false). OJO: es por sesion; si se recarga el script con Browse,
-- el aviso aparece de nuevo, porque no hay forma de guardar estado entre
-- recargas.
local menu_seen = false
local MENU_HINT = "hold mode to open training menu"

local function draw_status()
  -- El logo ya no va en la pantalla de combate, solo en el menu.
  draw_history()
  -- Aviso de como abrir el menu, abajo a la izquierda. Solo hasta la primera vez
  -- que se abre: despues menu_seen queda armado y no vuelve a salir.
  if not menu_seen then
    hud_text(5, 216, MENU_HINT, 0x60C8D8F0)
  end
end

--------------------------------------------------------------------------------
-- Menu
--
-- Se abre manteniendo MODE un instante, para que no se abra por accident al
-- tocarlo. Es la unica tecla que no se usa para golpear, asi que el menu no
-- pisa nada de la partida.
--
--   mantener MODE   abrir / cerrar
--   arriba / abajo  mover el cursor
--   A               activar o desactivar la opcion
--   B               volver todo a los valores de fabrica
--
-- Va en DOS COLUMNAS: con 20 opciones en una sola hacia 226 px de alto en una
-- pantalla de 224 y se cortaba abajo.
--------------------------------------------------------------------------------
local MENU_HOLD = 30
local MENU_COLS = 2
local COLW  = 100
local GUTTER = 26      -- margen izquierdo para las miniaturas
local PRE_W  = 18
local VAL_X, LAB_X = 1, 24

-- Estetica del menu: laca oscura con filetes dorados, en la misma paleta que el
-- logo para que se lean como una sola cosa. Antes era un rectángulo gris con
-- borde verde fluorescente.
--
-- OJO: todos estos van en 0xAARRGGBB porque van a gui.box / gui.text, que SI
-- usan ARGB. gui.drawline es RRGGBBAA (ver la nota de AGENTS.md).
local MC = {
  panel    = 0xF0141620,   -- fondo del panel
  edgeHi   = 0xFFFFC860,   -- filete exterior, dorado claro
  edgeLo   = 0xFF7A5220,   -- filete interior, dorado apagado
  head     = 0xFFB0C8E8,   -- texto de la cabecera
  sep      = 0xFF8A6A28,   -- lineas separadoras
  sel      = 0x70FFB840,   -- relleno de la fila seleccionada
  selTxt   = 0xFFFFF0B0,   -- texto de la fila seleccionada
  txt      = 0xFFD8DCE4,   -- texto normal
  off      = 0xFF808890,   -- valor apagado (OFF)
}

local menu_open = false
local menu_row  = 0
local mode_hold = 0
local mode_done = false
-- El aviso "hold mode to open training menu" se muestra solo hasta que se abre
-- el menu por PRIMERA vez. Despues no vuelve a aparecer en la sesion (queda
-- armedado en false). OJO: es por sesion; si se recarga el script con Browse,
-- el aviso aparece de nuevo, porque no hay forma de guardar estado entre
-- recargas.
local menu_prev = {}
-- Pantalla del hall de la fama abierta. Es un estado aparte del menu: cuando
-- esta abierta el menu de toggles no se dibuja ni responde, y se cierra
-- manteniendo MODE.
local hall_open = false
-- Estado previo de START, para detectar el flanco y cerrar el hall con un toque.
local hall_start_pressed = false
-- Latido del diagnostico: cuenta frames de forma incondicional. Se usa para el
-- print de consola; no se dibuja.
local heartbeat = 0

-- El cuarto campo, si esta, es la lista de colisiones de la que habla el
-- item: el menu dibuja una mini muestra de SU trazo real en el margen.
local function bool_item(label, get, set, prev)
  return { label = label, kind = "bool", get = get, set = set, prev = prev,
           value = function() return get() and 1 or 0 end,
           act = function() set(not get()) end }
end

-- Item de ACCION: no es un ON/OFF, dispara otra pantalla. kind = "act" para que
-- draw_menu_row lo dibuje distinto (dorado, con brillo) y no intente alternarlo.
local function action_item(label, fn)
  return { label = label, kind = "act",
           get = function() return false end,
           value = function() return 1 end,
           act = fn }
end

-- Un toggle que maneja varias opciones a la vez. Se lee EN VIVO (no cacheado),
-- asi que si algo cambia una opcion por otra via el menu sigue mintiendo.
-- Al activar pone todas en el mismo valor.
local function group_item(label, keys)
  local function on()
    for i = 1, #keys do
      if keys[i].get() then return true end
    end
    return false
  end
  return { label = label, kind = "bool", get = on,
           value = function() return on() and 1 or 0 end,
           act = function()
             local v = not on()
             for i = 1, #keys do keys[i].set(v) end
           end }
end

-- Default de cada toggle. Se guardan por NOMBRE y no por indice: antes era una
-- tabla posicional y cada vez que se agretaba o quitaba una opcion habia que
-- renumerar a mano, que ya salio mal una vez.
local function defaults()
  return {
    hitbox = SHOW_HITBOXES, clash = SHOW_CLASH, hurtbox = SHOW_HURTBOXES,
    pushbox = SHOW_PUSHBOXES, grab = SHOW_GRAB, axis = SHOW_AXIS,
    grid = SHOW_GRID, input = SHOW_INPUT, hud = SHOW_HUD, stun = SHOW_STUN,
    hittime = SHOW_HITTIME, history = SHOW_HISTORY, timeline = SHOW_TIMELINE,
    coord = SHOW_COORD, p2 = SHOW_P2, combo = SHOW_COMBO,
    refill = REFILL_ON_COMBO_END, freeze = FREEZE_ON,
  }
end

local function menu_restore_defaults()
  local d = defaults()
  SHOW_HITBOXES, SHOW_CLASH, SHOW_HURTBOXES = d.hitbox, d.clash, d.hurtbox
  SHOW_PUSHBOXES, SHOW_GRAB, SHOW_AXIS      = d.pushbox, d.grab, d.axis
  SHOW_GRID, SHOW_INPUT, SHOW_HUD           = d.grid, d.input, d.hud
  SHOW_STUN, SHOW_HITTIME                   = d.stun, d.hittime
  SHOW_HISTORY, SHOW_TIMELINE              = d.history, d.timeline
  SHOW_COORD, SHOW_P2                       = d.coord, d.p2
  SHOW_COMBO, REFILL_ON_COMBO_END          = d.combo, d.refill
  FREEZE_ON                              = d.freeze
end

local MENU = {
  bool_item("hitbox", function() return SHOW_HITBOXES end,
            function(v) SHOW_HITBOXES = v end, list_by("hit")),
  bool_item("clash", function() return SHOW_CLASH end,
            function(v) SHOW_CLASH = v end, list_by("clsh")),
  bool_item("hurtbox", function() return SHOW_HURTBOXES end,
            function(v) SHOW_HURTBOXES = v end, list_by("hurt")),
  bool_item("pushbox", function() return SHOW_PUSHBOXES end,
            function(v) SHOW_PUSHBOXES = v end, list_by("push")),
  bool_item("grab", function() return SHOW_GRAB end,
            function(v) SHOW_GRAB = v end, list_by("grab")),
  -- Antes "mandos", "historial" y "timeline" eran tres interruptores y "cruz"
  -- y "coord" otros dos. Ninguno se usaba por separado, asi que ahora hay dos
  -- grupos que los prenden y apagan juntos.
  group_item("teclas", {
    { get = function() return SHOW_INPUT end,    set = function(v) SHOW_INPUT = v end },
    { get = function() return SHOW_HISTORY end,  set = function(v) SHOW_HISTORY = v end },
    { get = function() return SHOW_TIMELINE end, set = function(v) SHOW_TIMELINE = v end },
  }),
  group_item("coordenadas", {
    { get = function() return SHOW_AXIS end,  set = function(v) SHOW_AXIS = v end },
    { get = function() return SHOW_COORD end, set = function(v) SHOW_COORD = v end },
  }),
  bool_item("cajas P2", function() return SHOW_P2 end,
            function(v) SHOW_P2 = v end),
  bool_item("cuadrica", function() return SHOW_GRID end,
            function(v) SHOW_GRID = v end),
  bool_item("hp/mana", function() return SHOW_HUD end,
            function(v) SHOW_HUD = v end),
  bool_item("stun", function() return SHOW_STUN end,
            function(v) SHOW_STUN = v end),
  bool_item("hit-time", function() return SHOW_HITTIME end,
            function(v) SHOW_HITTIME = v end),
  bool_item("combo", function() return SHOW_COMBO end,
            function(v) SHOW_COMBO = v end),
  bool_item("rellenar HP,MP", function() return REFILL_ON_COMBO_END end,
            function(v) REFILL_ON_COMBO_END = v end),
  bool_item("freeze", function() return FREEZE_ON end,
            function(v) FREEZE_ON = v end),
  -- Al FINAL del menu, como se pidio. kind = "act": no es un toggle, abre el
  -- hall de la fama.
  action_item("hall de la fama", function()
    hall_open = true
    -- Se abre con START (un toque) y se cierra con START. No hay contador de
    -- mantenimiento aca.
    hall_start_pressed = false
  end),
}

local function menu_slot(i)
  local rows = math.ceil(#MENU / MENU_COLS)
  local col = math.floor((i - 1) / rows)
  local row = (i - 1) % rows
  return col, row, rows
end

-- Pantalla del hall abierta: se cierra con un BOTON NUEVO, no con uno que ya
-- estaba apretado.
--
-- Esto se rompio al usar deteccion de NIVEL: uno activa el boton con A, y al
-- frame siguiente A sigue apretado, asi que "hay un boton apretado -> cerrar" lo
-- cerraba despues de 1 frame y no se veia nada.
--
-- Ahora se exige que el boton se haya SOLTADO antes de volver a cerrar, y ademas
-- se ignoran los primeros frames para que el A que abrio no la cierre.
-- Boton NUEVO = apretado AHORA y NO apretado en el frame anterior.
--
-- OJO, esto estaba al reves y por eso el hall NO SE CERRABA NUNCA: seponia
-- hall_prev[k] = true dentro del mismo for que despues chequeaba
-- "not hall_prev[k]", o sea que la condicion era siempre falsa.
--
-- El orden importa: primero se lee el estado viejo para calcular el flanco,
-- recien despues se guarda el nuevo para el proximo frame.
local function update_menu()
  local pad = joypad.get()
  local mode = pad["P1 Mode"] and true or false

  -- Pantalla del hall abierta. Se cierra con START, NO con MODE: antes MODE
  -- hacía tres cosas (abrir menu, cerrarlo, cerrar el hall) y se pisaban entre
  -- si. START no se usa para nada mas en el menu, asi que queda libre.
  if hall_open then
    local s = pad["P1 Start"] and true or false
    if s and not hall_start_pressed then
      hall_start_pressed = true
      hall_open = false
      menu_open = false
    end
    if not s then hall_start_pressed = false end
    return
  end

  if mode then
    mode_hold = mode_hold + 1
    -- ">=" y no "==": con igualdad, si un frame se pasa (o la cuenta arranca
    -- corrida) el menu NUNCA abre ni cierra, porque la igualdad exacta no se
    -- cumple jamas. Con ">=" dispara en cuanto llega al plazo.
    --
    -- El cerrojo evita que dispare en cada frame mientras se sigue apretando:
    -- hay que SOLTAR el boton para volver a armar.
    if mode_hold >= MENU_HOLD and not mode_done then
      menu_open = not menu_open
      menu_row = 0
      mode_done = true
      -- La PRIMERA vez que se abre, el aviso se apaga para siempre.
      if menu_open then menu_seen = true end
    end
  else
    mode_hold = 0
    mode_done = false
  end

  -- LATIDO INCONDICIONAL. Se imprime siempre, sin importar el estado del menu.
  -- Si esto deja de aparecer, el callback registerafter dejo de correr y el menu
  -- "clavado" es la ultima imagen dibujada, no un problema de logica.
  heartbeat = heartbeat + 1
  if heartbeat % 120 == 0 then
    print(string.format("[yuyu] latido=%d frame=%d mode=%s hold=%d done=%s menu=%s hall=%s",
          heartbeat, own_frame, tostring(mode), mode_hold,
          tostring(mode_done), tostring(menu_open), tostring(hall_open)))
  end

  if not menu_open then return end

  -- Navegacion con flanco, para no repetir por mantener.
  local function edge(key)
    local d = pad[key] and true or false
    local p = menu_prev[key]
    menu_prev[key] = d
    return d and not p
  end

  if edge("P1 Up")   then menu_row = menu_row - 1 end
  if edge("P1 Down") then menu_row = menu_row + 1 end
  if menu_row < 0 then menu_row = #MENU end
  if menu_row > #MENU then menu_row = 0 end

  local it = MENU[menu_row + 1]
  if it then
    if edge("P1 Button A") then it.act() end
    if edge("P1 Button B") then
      menu_restore_defaults()
    end
  end
end

local function draw_menu_row(cx, ly, it, sel)
  -- Boton de ACCION: dorado, con una banda de brillo que lo recorre. Se nota
  -- entre los toggles sin necesidad de leer el texto.
  if it.kind == "act" then
    local shine = (own_frame % 40) / 40.0
    gui.box(cx - 2, ly - 2, cx + COLW - 6, ly + 9,
            0xF04A3208, MC.edgeHi)
    local bx0, bx1 = cx + COLW - 30, cx + COLW - 8
    local px = bx0 + math.floor((bx1 - bx0) * shine)
    for k = 0, 6 do
      local a = 1 - math.abs(k - 3) / 3
      if a > 0 and px - 3 + k >= bx0 and px - 3 + k <= bx1 then
        gui.drawline(px - 3 + k, ly - 1, px - 3 + k, ly + 8,
                     0xFFFFE0A0)
      end
    end
    text_bold(cx + LAB_X - 20, ly, it.label, MC.selTxt)
    return
  end

  local on = it.value() ~= 0
  -- La fila seleccionada va en dorado claro; una fila apagada en gris, para que
  -- de un vistazo se sepa que esta OFF.
  local col = sel and MC.selTxt or (on and MC.txt or MC.off)
  local val = string.format("%-3s", on and "ON" or "off")
  hud_text(cx + VAL_X, ly, val, col)
  hud_text(cx + LAB_X, ly, it.label, col)
end

local function draw_menu()
  if not menu_open then return end
  local sw, sh = emu.screenwidth(), emu.screenheight()
  local colw, rowh = COLW, 10
  local _, _, rows = menu_slot(1)
  local w = colw * MENU_COLS + 6
  local h = rows * rowh + 24
  local x = (sw - w) / 2 + GUTTER
  local y = (sh - h) / 2

  -- Panel: fondo laca con filete exterior claro e interior apagado. El filete
  -- de 1 px hace de bisel y da la sensacion de chapa, en vez del rectangulo
  -- gris con borde verde que habia.
  gui.box(x, y, x + w, y + h, MC.panel, MC.edgeHi)
  gui.box(x + 2, y + 2, x + w - 2, y + h - 2, MC.panel, MC.edgeLo)

  -- Cabecera sobre una franja oscura, para que la ayuda se lea separada del
  -- listado.
  gui.box(x + 3, y + 3, x + w - 3, y + 13, 0xF0080A12, MC.edgeLo)
  gui.text(x + 6, y + 5, "A ON/OFF   B reset   MODE salir", MC.head)
  gui.drawline(x + 3, y + 15, x + w - 3, y + 15, MC.sep)

  for i = 1, #MENU do
    local it = MENU[i]
    local col, row = menu_slot(i)
    local cx = x + 3 + col * colw
    local ly = y + 17 + row * rowh
    local sel = (i - 1) == menu_row
    if sel then
      gui.box(cx - 1, ly - 1, cx + colw - 4, ly + 8, MC.sel, MC.edgeLo)
    end
    if it.prev then
      local px = x - GUTTER + 4
      draw_box(px, ly - 1, px + PRE_W, ly + 7, it.prev.line, it.prev.style, 3, it.prev.width)
      gui.drawline(px + PRE_W + 2, ly + 3, x - 2, ly + 3, 0xFF40506A)
    end
    draw_menu_row(cx, ly, it, sel)
  end

  -- Logo y sub-titulo, ENCIMA del panel, en el espacio reservado:
  --   N#GA             de x=0  y=160 a x=80  y=208
  --   training lua     de x=80 y=192 a x=160 y=208
  -- El logo se corrojo hacia la derecha para pegarse al texto. own_frame hace de
  -- reloj: se anima solo, sin nada que medir.
  -- Bandera flameando DETRAS del logo. Va primero para que el extrusion y las
  -- letras queden encima.
  draw_flag_flame(2, 160, 76, 30, own_frame * 0.05)
  draw_logo(16, 166, own_frame * 0.05)
  draw_subtitle(84, 194)
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------
local function on_dispatch()
  for i = 1, #LISTS do
    counts[i] = box_count(rw(LISTS[i].cnt), LISTS[i].stride)
  end
  hooked = true
  exec_stamp = frame_id
  wr_seen = false
end

-- El callback de registerwrite no recibe argumentos: hay que leer la memoria
-- en la direccion que se registro, que se pasa por closure.
--
-- IMPORTANTE: hay que guardar TAMBIEN los ceros. $01EDAC pone a 0 los cinco
-- contadores en $01EDC2..$01EDDA todos los frames; si el callback descarta el
-- 0, wr_counts se queda con el ultimo valor no nulo y la hitbox/clashbox vieja
-- se sigue dibujando. El arreglo de "solo dibujar con write fresco" no servia
-- de nada, porque ademas wr_frame lo refrescaba en el mismo frame cualquier
-- pushbox o hurtbox con valor != 0, y el snapshot pasaba el test de frescura.
-- Copia los datos de las cajas de una lista al instante en que su contador se
-- escribe. Se lee el layout segun el stride: el descriptor de grab es de $20 y
-- tiene Y en +2 y los radios en +4/+5, el resto es de $16 con Y en +4 y radios
-- en +8/+9.
local function snap_list(i, v)
  local L = LISTS[i]
  local n = box_count(v, L.stride)
  local t = {}
  for k = 0, n - 1 do
    local a = L.base + k * L.stride
    local own = rw(a + 0x0C)
    -- Posicion del DUEÑO en el mismo instante. Sin esto, el offset del grab se
    -- mide contra la posicion del personaje leida al final del frame, y si se
    -- movio entremedio el offset sale corrido: por eso el marcador aparecia a
    -- veces en posiciones donde no va.
    local ob = owner_base(own)
    local pw, ph = 0, 0
    if ob then
      pw = rw(ob + O.WORLD_LO)
      ph = rw(ob + O.WORLDY_LO)
    end
    if L.stride == 0x20 then
      t[k] = { owner = own, bx = rws(a + 0x00), by = rws(a + 0x02),
               rx = rb(a + 0x04), ry = rb(a + 0x05), pw = pw, ph = ph }
    else
      t[k] = { owner = own, bx = rws(a + 0x00), by = rws(a + 0x04),
               rx = bit.band(rb(a + 0x08), 0x7F), ry = rb(a + 0x09),
               pw = pw, ph = ph }
    end
  end
  wr_boxes[i] = t
end

local function mk_count_hook(i, addr)
  return function()
    local v = rw(addr)
    wr_counts[i] = v
    -- Solo cuando el contador es positivo: en el borrado del dispatcher ($01EDC2)
    -- no hay nada que capturar.
    if v > 0 then snap_list(i, v) end
    wr_seen = true
    wr_frame = frame_id
  end
end

--------------------------------------------------------------------------------
-- Arranque
--------------------------------------------------------------------------------
local ROM = tostring(emu.romname())

-- FBNeo BORRA los hooks exec en cada reset del juego. Si el script se cargo
-- antes de que arrancara la partida, el hook se perdia. Por eso se re-arma
-- cada frame: registrar el mismo PC otra vez es idempotente y barato.
local function arm_hook()
  if memory.registerexec then
    memory.registerexec(HOOK_PC, on_dispatch)
  end
  if memory.registerwrite then
    for i = 1, #LISTS do
      local c = LISTS[i].cnt
      -- Registrar en las DOS direcciones: la que escribe el 68000 ($00A0xx)
      -- y el espejo de FBNeo ($FFA0xx). Con solo el espejo no llegaba nada.
memory.registerwrite(c, 2, mk_count_hook(i, c))
      memory.registerwrite(c - 0xFF0000, 2, mk_count_hook(i, c - 0xFF0000))
    end
  end
end


arm_hook()
if emu.registerstart then emu.registerstart(arm_hook) end

--------------------------------------------------------------------------------
-- ¿Estamos en combate?
--
-- Señal: hay cajas de colisión vivas. En los menus del juego (titulo, eleccion
-- de personaje, eleccion de escenario, pausa) no hay ninguna, porque no hay un
-- personaje con pushbox y hurtbox. En combate siempre las hay.
--
-- Es la señal mas barata que hay: no depende de ningun address nuevo del ROM y
-- ya se leen los contadores para dibujar las cajas.
--
-- Con esto el HUD desaparece solo fuera de la pelea. El menu de Lua NO se
-- filtra: se puede abrir desde cualquier pantalla.
-- IMPORTANTISIMO: lee los contadores DEL HOOK (wr_counts), no con rw() en vivo.
--
-- El dispatcher pone a cero los cinco contadores en $01EDC2..$01EDDA todos los
-- frames. O sea que para cuando llega registerafter, el valor en vivo ya es 0
-- INCLUSO en plena pelea. Con rw() en vivo esto devolvia false siempre, y todo
-- el HUD quedaba escondido: las cajas no se dibujaban y el panel de combo no
-- funcionaba. Ese fue el bug.
--
-- wr_counts es el valor que capturo el write hook en el instante en que el
-- builder escribio el contador, antes de que el dispatcher lo borrara.
local function fight_active()
  for i = 1, #LISTS do
    if box_count(wr_counts[i], LISTS[i].stride) > 0 then return true end
  end
  return false
end

-- NO se usa emu.registerbefore para invalidar el snapshot: en este build de
-- Fightcade no existe, y como la invalidacion era condicional el snapshot
-- NUNCA se limpiaba. Por eso la caja del ultimo golpe se quedaba congelada.
-- El snapshot se sella con frame_id (arriba) y frame_id avanza aqui, una vez
-- por frame.
emu.registerafter(function()
  arm_hook()
  freeze_update()
  combo_update()
  update_menu()
  update_history()

  -- Fuera de combate no se dibuja nada del HUD, y se limpian los acumuladores
  -- del combo para no arrastrar datos de la pelea anterior.
  if fight_active() then
    draw_grid()
    draw_selftest()
    draw_boxes()
    draw_grab_range()
    draw_axis()
    draw_hud()
    draw_hittime()
    draw_stun()
    draw_combo()
    draw_input()
    draw_status()
  else
    combo_full_reset()
  end

  -- El menu va siempre: se puede abrir desde cualquier pantalla. Pero si esta
  -- abierta la pantalla del hall, el menu de toggles no se dibuja.
  if hall_open then
    draw_hall(own_frame * 0.05)
  else
    draw_menu()
  end

  frame_id = frame_id + 1
end)

print(string.format("[yuyu] HUD listo. rom=%s hook en $%06X", ROM, HOOK_PC))
