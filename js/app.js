/* =========================================================================
   MAKYOU TOITSUSEN — aplicacion de una sola pagina
   Sin dependencias: solo fetch de los JSON y painters.
   Idiomas: es / en / zh / ja, autodetectado y con selector en la cabecera.
   Rutas:  #/  #/personajes  #/persona/<id>  #/guias  #/matchup
          #/circuito  #/descargas  #/datos
   ========================================================================= */

const app = document.getElementById('app');
const DATOS = { pers: null, moves: null, circuito: null, extras: null };
let I18N = {};
let IDIOMA = 'es';

const IDIOMAS = ['es', 'en', 'zh', 'ja'];
const NOMBRES_IDIOMA = { es: 'Español', en: 'English', zh: '中文', ja: '日本語' };

const NOTAS = { S: 100, 'A+': 92, A: 82, 'B+': 72, B: 62, 'B−': 55, C: 42, 'C−': 36, D: 22, E: 12 };

/* --------------------------------------------------------------- traduccion */
function T(ruta, pordefecto) {
  let v = I18N[IDIOMA];
  for (const paso of ruta.split('.')) {
    if (v == null || typeof v !== 'object') { v = undefined; break; }
    v = v[paso];
  }
  if (v === undefined && IDIOMA !== 'es') {
    v = I18N.es;
    for (const paso of ruta.split('.')) {
      if (v == null || typeof v !== 'object') { v = undefined; break; }
      v = v[paso];
    }
  }
  return v === undefined ? (pordefecto || '') : v;
}

function detectarIdioma() {
  // 1) ?idioma=xx en la URL (para enlaces y capturas)
  const q = new URLSearchParams(location.search || '').get('idioma');
  if (q && IDIOMAS.indexOf(q) >= 0) return q;
  // 2) eleccion guardada por el visitante
  const guardado = localStorage.getItem('idioma');
  if (guardado && IDIOMAS.indexOf(guardado) >= 0) return guardado;
  // 3) lo que diga el navegador
  const nav = navigator.languages && navigator.languages.length
    ? navigator.languages : [navigator.language || 'es'];
  for (const l of nav) {
    const b = String(l).toLowerCase();
    if (b.startsWith('zh')) return 'zh';
    if (b.startsWith('ja')) return 'ja';
    if (b.startsWith('en')) return 'en';
    if (b.startsWith('es')) return 'es';
  }
  return 'es';
}

/* --------------------------------------------------------------- utiles */
const $ = (s, r) => (r || document).querySelector(s);
const esc = s => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const num = n => (n == null || isNaN(n)) ? '—' : Number(n).toLocaleString('es-AR');

function limpiar(s) {
  return String(s == null ? '' : s)
    .replace(/\*\*/g, '').replace(/`/g, '')
    .replace(/^[\s\-–—]+/, '').trim();
}

function barra(nota, azul) {
  const v = NOTAS[nota] || 0;
  return `<span class="barra${azul ? ' b' : ''}"><i style="width:${v}%"></i></span>`;
}

function artePj(p) { return `img/pj_${String(p.pos).padStart(2, '0')}_${p.slug_foto}.png`; }
function pjPorId(id) { return DATOS.pers.find(p => p.id === id); }
function ctxDe(p) { return (p.ctx || []).map(c => 'ctx' + c); }

function movesDe(p) {
  const out = [];
  ctxDe(p).forEach(k => {
    const c = DATOS.moves[k];
    if (c) c.lista.forEach(m => out.push(Object.assign({ ctx: k }, m)));
  });
  return out;
}

function chip(origen) {
  return `<span class="chip chip-${origen}">${esc(T('chip.' + origen, origen))}</span>`;
}

/* --------------------------------------------------------------- cabecera */
const NAV_TEXTO = {
  '#/': 'nav.inicio', '#/personajes': 'nav.personajes', '#/guias': 'nav.guias',
  '#/matchup': 'nav.matchup', '#/circuito': 'nav.circuito',
  '#/descargas': 'nav.descargas'
};

function pintarMenu() {
  const h = location.hash || '#/';
  document.querySelectorAll('#menu a').forEach(a => {
    const destino = a.getAttribute('href');
    const activo = destino === h ||
      (h.startsWith('#/persona') && destino === '#/personajes');
    a.classList.toggle('on', activo);
    const k = NAV_TEXTO[destino];
    if (k) a.textContent = T(k, a.textContent);
  });
  document.querySelectorAll('[data-i18n]').forEach(n => {
    n.textContent = T(n.getAttribute('data-i18n'), n.textContent);
  });
  document.documentElement.lang = IDIOMA;
}

/* --------------------------------------------------------------- portada */
function vistaInicio() {
  const tira = (k, extra) => `<a class="tira" href="${extra.href}">
      <div class="num">${extra.n}</div><b>${esc(T('tiras.' + k + '.t'))}</b>
      <span>${esc(T('tiras.' + k + '.d'))}</span></a>`;

  return `
  <div class="seccion">
    <div class="hero">
      <img src="img/seleccion.png" alt="${esc(T('portada.titulo'))}">
      <div class="hero-texto">
        <div class="kicker">Mega Drive · 1994 · Makyo Toitsusen</div>
        <h1>${esc(T('portada.titulo'))}</h1>
        <p>${T('portada.bajada')}</p>
      </div>
    </div>

    <div class="tiras">
      ${tira('luchadores', { n: 11, href: '#/personajes' })}
      ${tira('guias', { n: 8, href: '#/guias' })}
      ${tira('matchup', { n: '11×11', href: '#/matchup' })}
      ${tira('circuito', { n: 3, href: '#/circuito' })}
    </div>

    <h2>${esc(T('portada.primero'))}</h2>
    <div class="tarjeta">
      ${T('datos_clave').map(f => `<div class="dato"><b>${esc(f[0])}</b><span>${f[1]}</span></div>`).join('')}
    </div>

    <h2>${esc(T('portada.los_once'))}</h2>
    <div class="rejilla">${DATOS.pers.map(tarjetaPj).join('')}</div>
  </div>`;
}

function tarjetaPj(p) {
  return `
  <a class="pj" href="#/persona/${p.id}">
    <span class="pos">${String(p.pos).padStart(2, '0')}</span>
    <div class="arte" style="background-image:url('${artePj(p)}')"></div>
    <div class="cuerpo">
      <h3>${esc(p.nombre)}</h3>
      <p class="lema">${esc(p.lema || '')}</p>
      <div class="notas">
        <span class="nota-mini">${T('notas.ATQ')} <b>${esc(p.perfil.Ataque || '—')}</b></span>
        <span class="nota-mini">${T('notas.DEF')} <b>${esc(p.perfil.Defensa || '—')}</b></span>
        <span class="nota-mini">${T('notas.VEL')} <b>${esc(p.perfil.Velocidad || '—')}</b></span>
        <span class="nota-mini">${T('notas.STUN')} <b>${p.stats.stun || '—'}</b></span>
      </div>
    </div>
  </a>`;
}

/* --------------------------------------------------------------- personajes */
function vistaPersonajes() {
  const orden = { S: 0, A: 1, B: 2, C: 3, D: 4 };
  const p = DATOS.pers.slice().sort((a, b) =>
    (orden[a.perfil.Ataque] || 9) - (orden[b.perfil.Ataque] || 9));
  return `
  <div class="seccion">
    <h1>${esc(T('personajes.titulo'))}</h1>
    <p class="sub">${T('personajes.sub')} ${chip('web')}</p>
    <div class="rejilla">${p.map(tarjetaPj).join('')}</div>
    <p class="sub" style="margin-top:22px">${T('personajes.nota')} ${chip('rom')}</p>
  </div>`;
}

/* --------------------------------------------------------------- ficha */
function vistaPersona(id) {
  const p = pjPorId(id);
  if (!p) return `<div class="seccion"><h1>${esc(T('no_encontrado'))}</h1>
    <p><a class="volver" href="#/personajes">${esc(T('volver'))}</a></p></div>`;
  const mv = movesDe(p).filter(m => m.dmg > 0).sort((a, b) => a.dmg - b.dmg);

  return `
  <div class="seccion">
    <p><a class="volver" href="#/personajes">${esc(T('volver'))}</a></p>
    <div class="ficha-cabecera">
      <div class="arte"><img src="${artePj(p)}" alt="${esc(p.nombre)}"></div>
      <div class="ficha-titulo">
        <div class="kicker">${esc(T('ficha.pos'))} ${String(p.pos).padStart(2, '0')} ${esc(T('ficha.en_pantalla'))}</div>
        <h1>${esc(p.nombre)}</h1>
        <div class="kana">${esc(p.nombre_kana || '')}</div>
        <p class="sub">${esc(p.lema || '')}</p>
        <p class="sub">${esc(p.rol || '')}</p>
        <div class="notas">
          ${nota('Ataque', p.perfil.Ataque)}${nota('Defensa', p.perfil.Defensa)}
          ${nota('Velocidad', p.perfil.Velocidad)}${nota('Salto', p.perfil.Salto)}
          ${nota('Global', p.perfil.Global, true)}
        </div>
      </div>
    </div>

    <div class="cols">
      <div>${bloqueNotas(p)}${bloqueNormales(p)}</div>
      <div>${bloqueEspeciales(p)}${bloqueVideo(p)}${bloqueLore(p)}</div>
    </div>

    ${bloqueArbol(p)}
    ${bloqueCombos(p)}
    ${bloqueMovelist(p, mv)}
    ${p.frases && p.frases.length ? `<div class="tarjeta"><h3>${esc(T('ficha.frases'))}</h3>
      <ul class="frases">${p.frases.map(f => `<li>«${esc(f)}»</li>`).join('')}</ul>
      <p class="sub"><span class="chip chip-web">${esc(T('datos.fuente_es'))}</span></p></div>` : ''}
  </div>`;
}

function nota(etiqueta, grado, azul) {
  if (!grado) return '';
  return `<div class="nota"><span>${esc(T('notas.' + etiqueta, etiqueta))}</span>
    <b>${esc(grado)}</b>${barra(grado, azul)}</div>`;
}

function bloqueNotas(p) {
  const s = p.stats || {};
  const filas = [];
  const add = (k, etiq) => { if (s[k] !== undefined) filas.push([etiq, s[k]]); };
  add('stun', 'Stun'); add('dash', 'Dash'); add('backdash', 'Backstep');
  add('walk', T('notas.Velocidad')); add('regen', T('ficha.regen'));
  filas.push([T('ficha.vida_hp'), '255']);
  filas.push([T('ficha.mana'), '223']);
  return `<div class="tarjeta"><h3>${esc(T('ficha.numeros'))}</h3>
    ${filas.map(f => `<div class="dato"><b>${esc(f[0])}</b><span>${f[1]}</span></div>`).join('')}
    <p class="sub" style="margin-top:12px">${esc(T('ficha.contexto'))}
      ${(p.ctx || []).map(c => 'ctx' + c).join(' y ')}.</p>
  </div>`;
}

function bloqueNormales(p) {
  if (!p.normales || !p.normales.length) return '';
  return `<div class="tarjeta"><h3>${esc(T('ficha.golpes_normales'))}</h3>
    <div class="tabla-scroll"><table>
      <thead><tr><th>${esc(T('ficha.col_move'))}</th><th>${esc(T('ficha.col_altura'))}</th>
        <th>${esc(T('ficha.col_efecto'))}</th>
        <th class="num">${esc(T('ficha.col_dmg'))}</th><th class="num">${esc(T('ficha.col_stun'))}</th>
        <th>${esc(T('ficha.col_cancel'))}</th></tr></thead>
      <tbody>${p.normales.map(g => `<tr>
        <td><b>${esc(limpiar(g.golpe))}</b></td>
        <td>${esc(limpiar(g.altura))}</td><td>${esc(limpiar(g.efecto))}</td>
        <td class="num">${esc(limpiar(g.dmg))}</td>
        <td class="num">${esc(limpiar(g.stun))}</td>
        <td>${esc(limpiar(g.cancel))}</td></tr>`).join('')}</tbody>
    </table></div>
    <p class="sub" style="margin-top:10px">${chip('web')} ${esc(T('ficha.nota_fuentes'))}</p>
  </div>`;
}

function bloqueEspeciales(p) {
  if (!p.especiales || !p.especiales.length) return '';
  const esSuper = e => /super/i.test(e.nombre);
  const sup = p.especiales.filter(esSuper);
  const resto = p.especiales.filter(e => !esSuper(e));
  const fila = e => `<tr>
      <td><b>${esc(limpiar(e.nombre))}</b></td>
      <td><kbd>${esc(limpiar(e.cmd))}</kbd></td>
      <td class="num">${esc(limpiar(e.dmg))}</td>
      <td class="num">${esc(limpiar(e.mana))}</td>
      <td class="num">${esc(limpiar(e.stun))}</td></tr>`;
  const cabeza = `<thead><tr><th>${esc(T('ficha.col_tecnica'))}</th><th>${esc(T('ficha.col_comando'))}</th>
      <th class="num">${esc(T('ficha.col_dmg'))}</th><th class="num">${esc(T('ficha.mana'))}</th>
      <th class="num">${esc(T('ficha.col_stun'))}</th></tr></thead>`;
  return `<div class="tarjeta"><h3>${esc(T('ficha.especiales'))}</h3>
    <div class="tabla-scroll"><table>${cabeza}
      <tbody>${resto.map(fila).join('')}</tbody></table></div>
    ${sup.length ? `<h4 style="margin-top:18px">${esc(T('ficha.super'))}</h4>
    <div class="tabla-scroll"><table>${cabeza}
      <tbody>${sup.map(fila).join('')}</tbody></table></div>` : ''}
    ${p.nota ? `<p class="sub" style="margin-top:12px">${esc(p.nota)}</p>` : ''}
    <p class="sub" style="margin-top:10px">${esc(T('ficha.comando_super'))}
      <kbd>${esc(p.super || '—')}</kbd> ${chip('web')}</p>
  </div>`;
}

function bloqueVideo(p) {
  const v = (p.extras && p.extras.video) || '';
  if (!v) {
    return `<div class="tarjeta"><h3>${esc(T('ficha.video'))}</h3>
      <div class="hueco">${T('ficha.falta_video')}</div></div>`;
  }
  return `<div class="tarjeta"><h3>${esc(T('ficha.video'))}</h3>
    <div class="video"><iframe src="${esc(v)}" title="${esc(p.nombre)}"
      allowfullscreen loading="lazy"></iframe></div></div>`;
}

function bloqueLore(p) {
  const l = (p.extras && p.extras.lore) || '';
  if (!l) {
    return `<div class="tarjeta"><h3>${esc(T('ficha.lore'))}</h3>
      <div class="hueco">${T('ficha.falta_lore')} <em>${esc(p.rol || '')}</em>.</div></div>`;
  }
  return `<div class="tarjeta"><h3>${esc(T('ficha.lore'))}</h3><p>${esc(l)}</p></div>`;
}

/* ------------------------------------------------------- arbol de aprendizaje */
function bloqueArbol(p) {
  const esp = (p.especiales || []).filter(e => !/super/i.test(e.nombre));
  const sup = (p.especiales || []).filter(e => /super/i.test(e.nombre));
  const cancelables = (p.normales || []).filter(g => /^s/i.test(limpiar(g.cancel)));

  const manaDe = e => {
    const m = limpiar(e.mana).match(/([\d.]+)/);
    return m ? parseFloat(m[1]) : 999;
  };
  const baratos = esp.filter(e => manaDe(e) <= 20);
  const caros = esp.filter(e => manaDe(e) > 20);
  const li = e => `<li><span class="nivel">${esc(limpiar(e.nombre))}</span>
    <kbd>${esc(limpiar(e.cmd))}</kbd> · ${T('ficha.col_dmg')} ${esc(limpiar(e.dmg))} ·
    ${esc(T('ficha.mana'))} ${esc(limpiar(e.mana))}</li>`;

  return `<h2>${esc(T('ficha.arbol'))}</h2>
    <p class="sub">${esc(T('ficha.arbol_sub'))}</p>
    <div class="arbol">
      <div class="rama"><h4>${esc(T('ficha.nivel1'))}</h4>
        <p class="sub">${esc(T('ficha.nivel1_txt'))}
          ${cancelables.length ? cancelables.map(g => `<kbd>${esc(limpiar(g.golpe))}</kbd>`).join(' ') : ''}</p>
      </div>
      <div class="rama"><h4>${esc(T('ficha.nivel2'))}</h4>
        <ol>${(baratos.length ? baratos : esp.slice(0, 2)).map(li).join('')}</ol></div>
      <div class="rama"><h4>${esc(T('ficha.nivel3'))}</h4>
        <ol>${(caros.length ? caros : esp.slice(-2)).map(li).join('')}</ol>
        <p class="sub">${esc(T('ficha.nivel3_txt'))}</p></div>
      <div class="rama"><h4>${esc(T('ficha.nivel4'))}</h4>
        <ol>${(sup.length ? sup : esp.slice(0, 1)).map(li).join('')}</ol>
        <p class="sub">${T('ficha.nivel4_txt')}</p></div>
    </div>`;
}

/* --------------------------------------------------------------- combos */
function claveCombos(id) { return 'combo_' + id; }
function combosGuardados(id) {
  try { return JSON.parse(localStorage.getItem(claveCombos(id)) || '[]'); }
  catch (e) { return []; }
}

function bloqueCombos(p) {
  const guardados = combosGuardados(p.id);
  const props = (p.normales || []).filter(g => /^s/i.test(limpiar(g.cancel)))
    .slice(0, 2).map(g => limpiar(g.golpe));
  const esp = (p.especiales || []).filter(e => !/super/i.test(e.nombre))
    .sort((a, b) => String(a.dmg).localeCompare(String(b.dmg))).slice(-2);

  return `<h2>${esc(T('ficha.combos'))}</h2>
    <p class="sub">${esc(T('ficha.combos_sub'))}</p>
    <div class="cols">
      <div><div class="tarjeta"><h3>${esc(T('ficha.tus_combos'))}</h3>
        <div id="lista-combos">${guardados.length
          ? guardados.map(c => comboFila(c, true)).join('')
          : `<p class="sub">${esc(T('ficha.vacio_combos'))}</p>`}</div>
        <div class="fil">
          <input type="text" id="c-input" placeholder="${esc(T('ficha.notacion'))}">
          <input type="text" id="c-nota" placeholder="${esc(T('ficha.nota_op'))}" style="min-width:150px">
          <button class="btn oro" id="c-add">${esc(T('ficha.anadir'))}</button>
          <button class="btn" id="c-clear">${esc(T('ficha.vaciar'))}</button>
        </div></div></div>
      <div><div class="tarjeta"><h3>${esc(T('ficha.propuestas'))}</h3>
        <p class="sub">${chip('med')} ${esc(T('ficha.propuestas_sub'))}</p>
        ${comboFila({ n: `${props[0] || '2A'} > ${limpiar(esp[0] ? esp[0].cmd : '')}` })}
        ${comboFila({ n: `${props[1] || props[0] || '2B'} > ${limpiar(esp[1] ? esp[1].cmd : (esp[0] ? esp[0].cmd : ''))}` })}
        ${p.especiales && p.especiales.length > 1
      ? comboFila({ n: `${limpiar(p.especiales[0].cmd)} > ${limpiar(p.especiales[1].cmd)}` }) : ''}
      </div></div>
    </div>`;
}

function comboFila(c, editable) {
  const pasos = String(c.n || '').split('>').map(x => `<kbd>${esc(x.trim())}</kbd>`)
    .join('<span style="color:var(--oro)">&rsaquo;</span>');
  return `<div class="combo">
    <span class="sec">${editable ? esc(c.nota || 'combo') : esc(T('ficha.proponer'))}</span>
    ${pasos}
    ${c.d ? `<span class="dmg">${esc(c.d)} ${esc(T('ficha.de_dano'))}</span>` : ''}
  </div>`;
}

function conectarCombos(p) {
  const add = $('#c-add'), clear = $('#c-clear'), inp = $('#c-input'), nota = $('#c-nota');
  if (!add || !p) return;
  add.onclick = () => {
    const n = inp.value.trim();
    if (!n) return;
    const l = combosGuardados(p.id);
    l.push({ n, nota: nota.value.trim() || 'combo' });
    localStorage.setItem(claveCombos(p.id), JSON.stringify(l));
    inp.value = ''; nota.value = '';
    render();
  };
  clear.onclick = () => { localStorage.removeItem(claveCombos(p.id)); render(); };
}

/* --------------------------------------------------------------- movelist */
function bloqueMovelist(p, mv) {
  const max = Math.max.apply(null, mv.map(m => m.dmg).concat([1]));
  return `<h2>${esc(T('ficha.framedata'))}</h2>
    <p class="sub">${T('ficha.framedata_sub')}
      (${ctxDe(p).map(c => DATOS.moves[c] ? DATOS.moves[c].tabla : '').join(' / ')}) ${chip('rom')}</p>
    <div class="fil">
      <input type="search" id="mv-buscar" placeholder="${esc(T('ficha.filtrar_id'))}">
      <input type="number" id="mv-min" placeholder="${esc(T('ficha.dmg_min'))}" style="min-width:130px">
      <select id="mv-orden" class="btn">
        <option value="dmg">${esc(T('ficha.ord_dmg'))}</option>
        <option value="startup">${esc(T('ficha.ord_startup'))}</option>
        <option value="stun">${esc(T('ficha.ord_stun'))}</option>
        <option value="id">${esc(T('ficha.ord_id'))}</option>
      </select>
    </div>
    <div class="tabla-scroll"><table id="mv-tabla">
      <thead><tr><th>${esc(T('ficha.col_move'))}</th><th>${esc(T('ficha.col_tipo'))}</th>
        <th class="num">${esc(T('ficha.col_inicio'))}</th><th class="num">${esc(T('ficha.col_activo'))}</th>
        <th class="num">${esc(T('ficha.col_recup'))}</th><th class="num">${esc(T('ficha.col_total'))}</th>
        <th class="num">${esc(T('ficha.col_dmg'))}</th><th></th>
        <th class="num">${esc(T('ficha.col_stun'))}</th></tr></thead>
      <tbody>${mv.map(m => filaMove(m, max)).join('')}</tbody>
    </table></div>`;
}

function filaMove(m, max) {
  const tags = [];
  if (m.hold) tags.push(`<span class="tag hold">${esc(T('ficha.mantener'))}</span>`);
  if (m.hits > 1) tags.push(`<span class="tag">${m.hits} ${esc(T('ficha.golpes'))}</span>`);
  if (m.especial) tags.push(`<span class="tag super">${esc(T('ficha.especial'))}</span>`);
  return `<tr data-id="${esc(m.hex)}" data-dmg="${m.dmg}" data-startup="${m.startup}" data-stun="${m.stun}">
    <td><b>${esc(m.hex)}</b></td>
    <td>${tags.join(' ') || `<span class="tag">${esc(T('ficha.normal'))}</span>`}</td>
    <td class="num">${m.startup}</td><td class="num">${m.activo}</td>
    <td class="num">${m.recovery}</td><td class="num">${m.total}</td>
    <td class="num"><b>${m.dmg}</b></td>
    <td><span class="barra-dmg"><i style="width:${Math.round(m.dmg / max * 100)}%"></i></span></td>
    <td class="num">${m.stun}</td>
  </tr>`;
}

function conectarMovelist() {
  const b = $('#mv-buscar'), min = $('#mv-min'), ord = $('#mv-orden'), tabla = $('#mv-tabla');
  if (!tabla) return;
  const filas = Array.prototype.slice.call(tabla.tBodies[0].rows);
  function filtrar() {
    const q = (b.value || '').toUpperCase();
    const n = parseInt(min.value || '0', 10);
    filas.forEach(f => {
      f.style.display = (f.dataset.id.toUpperCase().indexOf(q) >= 0 && +f.dataset.dmg >= n) ? '' : 'none';
    });
  }
  function ordenar() {
    const col = { dmg: 1, startup: 2, stun: 3, id: 0 }[ord.value];
    const asc = ord.value === 'id';
    filas.slice().sort((a, b2) => {
      const va = asc ? a.cells[0].textContent : +a.dataset[col];
      const vb = asc ? b2.cells[0].textContent : +b2.dataset[col];
      return va > vb ? 1 : va < vb ? -1 : 0;
    }).forEach(f => tabla.tBodies[0].appendChild(f));
  }
  if (b) b.oninput = filtrar;
  if (min) min.oninput = filtrar;
  if (ord) ord.onchange = ordenar;
}

/* --------------------------------------------------------------- guias */
function vistaGuias() {
  const guias = T('guias', []);
  return `<div class="seccion">
    <h1>${esc(T('nav.guias'))}</h1>
    <p class="sub"><a href="#/personajes">${esc(T('nav.personajes'))}</a></p>
    ${guias.map(g => `
      <div class="tarjeta">
        <h3>${esc(g.t)} ${chip(g.c === 'rom' ? 'rom' : g.c === 'med' ? 'med' : 'web')}</h3>
        <p class="sub">${esc(g.d)}</p>
        ${g.h.map(h => `<h4 style="margin-top:18px">${esc(h[0])}</h4><div>${h[1]}</div>`).join('')}
      </div>`).join('')}
  </div>`;
}

/* --------------------------------------------------------------- matchup */
function claveMatchup() { return 'matchup'; }

/* --- calificacion automatica 1-10 ------------------------------------------
   No son resultados medidos: sale de las notas de perfil (Ataque, Defensa,
   Velocidad, Global) mas dos numeros del ROM, la velocidad de dash y el stun
   reservado. Solo sirve para tener la matriz llena y ordenarla; cada celda
   sigue siendo editable a mano con lo que se sepa en la practica.          */
const VALOR_NOTA = {
  'S': 100, 'A+': 92, 'A': 85, 'A−': 78, 'A-': 78,
  'B+': 72, 'B': 65, 'B−': 58, 'B-': 58,
  'C': 50, 'C−': 42, 'C-': 42, 'D': 32, 'E': 12,
};
const valorNota = n => (VALOR_NOTA[n] !== undefined ? VALOR_NOTA[n] : 50);

function poderPj(x) {
  const pr = x.perfil || {}, st = x.stats || {};
  const base = 0.40 * valorNota(pr.Global) + 0.30 * valorNota(pr.Ataque) +
    0.20 * valorNota(pr.Defensa) + 0.10 * valorNota(pr.Velocidad);
  const maxDash = Math.max.apply(null, DATOS.pers.map(p => (p.stats || {}).dash || 0).concat([1]));
  const dash = ((st.dash || 0) / maxDash) * 10;
  const stun = ((st.stun || 40) / 60) * 6;
  return base + dash + stun;
}

function ratingAutomatico(fila, col) {
  const diff = (poderPj(fila) - poderPj(col)) / 7 + 5;
  return Math.max(1, Math.min(10, Math.round(diff)));
}

/* nombre corto para que las 12 columnas entren sin scroll horizontal */
const CORTO = {
  sensui: 'SEN', jin: 'JIN', itsuki: 'ITS', genkai: 'GEN', kuwabara: 'KUW',
  yusuke: 'YUS', kurama: 'KUR', hiei: 'HIE', chui: 'CHU',
  toguro_mayor: 'T.MAY', toguro_menor: 'T.MEN',
};
const corto = x => CORTO[x.id] || x.nombre.slice(0, 5).toUpperCase();

/* bucket de la calificacion -> clave de i18n */
function bucketCalif(n) {
  if (n >= 9) return 'mfuerte';
  if (n >= 7) return 'fuerte';
  if (n === 6) return 'afavor';
  if (n === 5) return 'parejo';
  if (n === 4) return 'encontra';
  if (n >= 3) return 'debil';
  return 'mdebil';
}

function matchupDatos() {
  try {
    const m = JSON.parse(localStorage.getItem(claveMatchup()) || '{}');
    return m && typeof m === 'object' ? m : {};
  } catch (e) { return {}; }
}

/** lo que se pinta en la celda: lo editado a mano, o el automatico */
function valorCelda(datos, fila, col) {
  const guardado = datos[fila.id] && datos[fila.id][col.id];
  if (guardado !== undefined && guardado !== null && String(guardado).trim() !== '') {
    return { texto: String(guardado), auto: false };
  }
  return { texto: String(ratingAutomatico(fila, col)), auto: true };
}
function vistaMatchup() {
  const datos = matchupDatos();
  const pjs = DATOS.pers;

  const celda = (fila, col) => {
    const { texto, auto } = valorCelda(datos, fila, col);
    const n = Math.max(1, Math.min(10, parseInt(texto, 10) || 5));
    const b = bucketCalif(n);
    return `<td class="celda cal-${b}${auto ? ' auto' : ''}"
      title="${esc(fila.nombre)} vs ${esc(col.nombre)}: ${n}/10 ${esc(T('matchup.bucket.' + b))}">
      <input type="number" min="1" max="10" value="${esc(texto)}"
        data-fila="${fila.id}" data-col="${col.id}">
      <span class="pie-celda">${esc(T('matchup.bucket.' + b))}</span></td>`;
  };

  const editados = pjs.reduce((a, f) => {
    const fila = datos[f.id] || {};
    return a + Object.keys(fila).filter(c => String(fila[c]).trim() !== '').length;
  }, 0);

  return `<div class="seccion">
    <h1>${esc(T('matchup.titulo'))}</h1>
    <p class="sub">${T('matchup.sub')}</p>

    <div class="fil">
      <button class="btn oro" id="mk-export">${esc(T('matchup.exportar'))}</button>
      <button class="btn" id="mk-auto">${esc(T('matchup.recalcular'))}</button>
      <button class="btn" id="mk-clear">${esc(T('matchup.borrar_todo'))}</button>
      <span class="sub" style="margin:0">
        <span class="chip chip-med">${editados} ${esc(T('matchup.editados'))}</span>
        ${chip('web')} ${esc(T('matchup.auto_nota'))}</span>
    </div>

    <div class="tarjeta">
      <h3>${esc(T('matchup.como'))}</h3>
      <p>${T('matchup.como_txt')}</p>
      <div class="escala">${['mdebil', 'debil', 'encontra', 'parejo', 'afavor', 'fuerte', 'mfuerte']
      .map(b => `<span class="celda cal-${b}"><b>${esc(T('matchup.bucket.' + b))}</b></span>`).join('')}</div>
    </div>

    <div class="matriz-wrap"><table class="matriz">
      <thead><tr><th></th>${pjs.map(c => `<th title="${esc(c.nombre)}">${esc(corto(c))}</th>`).join('')}</tr></thead>
      <tbody>${pjs.map(f => `<tr>
        <th class="fila" title="${esc(f.nombre)}">${esc(corto(f))}</th>
        ${pjs.map(c => c.id === f.id ? '<td class="celda diagonal">—</td>' : celda(f, c)).join('')}
      </tr>`).join('')}</tbody>
    </table></div>

    <h2>${esc(T('matchup.diag'))}</h2>
    <p class="sub">${esc(T('matchup.diag_txt'))}</p>
    ${bloqueDiag()}
  </div>`;
}

function bloqueDiag() {
  const pjs = DATOS.pers;
  const filas = pjs.map(p => {
    let suma = 0, n = 0, editados = 0;
    pjs.forEach(o => {
      if (o.id === p.id) return;
      const { texto, auto } = valorCelda(matchupDatos(), p, o);
      suma += Math.max(1, Math.min(10, parseInt(texto, 10) || 5));
      n++;
      if (!auto) editados++;
    });
    return { p, media: suma / n, n, editados };
  }).sort((a, b) => b.media - a.media);
  const max = Math.max.apply(null, filas.map(f => f.media));
  return `<div class="tabla-scroll"><table>
    <thead><tr><th>${esc(T('matchup.jugador'))}</th>
      <th class="num">${esc(T('matchup.diag_media'))}</th>
      <th class="num">${esc(T('matchup.diag_edit'))}</th>
      <th>${esc(T('matchup.diag_fortaleza'))}</th></tr></thead>
    <tbody>${filas.map(f => `<tr>
      <td><b>${esc(f.p.nombre)}</b></td>
      <td class="num"><b>${f.media.toFixed(1)}</b></td>
      <td class="num">${f.editados}/${f.n}</td>
      <td><span class="barra-puntos"><i style="width:${Math.round(f.media / max * 100)}%"></i></span></td>
    </tr>`).join('')}</tbody></table></div>`;
}

function conectarMatchup() {
  const exportar = $('#mk-export'), borrar = $('#mk-clear'), auto = $('#mk-auto');
  const tabla = document.querySelector('.matriz');
  if (tabla) {
    tabla.addEventListener('change', e => {
      const inp = e.target;
      if (!inp || inp.tagName !== 'INPUT') return;
      const f = inp.dataset.fila, c = inp.dataset.col;
      const datos = matchupDatos();
      if (!datos[f]) datos[f] = {};
      const v = inp.value.trim();
      if (v !== '') datos[f][c] = String(Math.max(1, Math.min(10, parseInt(v, 10) || 5)));
      else delete datos[f][c];
      localStorage.setItem(claveMatchup(), JSON.stringify(datos));
      render();
    });
  }
  if (auto) auto.onclick = () => {
    if (confirm(T('matchup.recalcular') + '?')) {
      localStorage.removeItem(claveMatchup());
      render();
    }
  };
  if (borrar) borrar.onclick = () => {
    if (confirm(T('matchup.borrar_todo') + '?')) {
      localStorage.removeItem(claveMatchup());
      render();
    }
  };
  if (exportar) exportar.onclick = () => {
    const datos = matchupDatos();
    // se exporta la matriz completa ya resuelta (editada + automatica) y
    // aparte cuales celdas se editaron a mano
    const completa = {};
    const manual = {};
    DATOS.pers.forEach(f => {
      completa[f.id] = {};
      DATOS.pers.forEach(c => {
        if (c.id === f.id) return;
        const { texto, auto } = valorCelda(datos, f, c);
        completa[f.id][c.id] = +texto;
        if (!auto) (manual[f.id] = manual[f.id] || {})[c.id] = +texto;
      });
    });
    const salida = {
      _nota: '1-10 = que tan fuerte le pega la fila contra la columna. ' +
        'Lo automatico sale del perfil y los stats del ROM, no de partidas medidas.',
      _manual: Object.keys(manual).length ? manual : 'ninguna celda editada a mano',
      calificacion: completa,
    };
    descargar('matchup.json', salida);
  };
}

/* --------------------------------------------------------------- circuito */
function vistaCircuito() {
  const c = DATOS.circuito;
  let jugadores = c.jugadores || [];
  const guardados = localStorage.getItem('circuito_jugadores');
  if (guardados) { try { jugadores = JSON.parse(guardados); } catch (e) { } }

  const P = c.pesos;
  const conPuntos = jugadores.map(j => ({
    ...j,
    puntos: (j.torneo || 0) * P.estrella_dorada +
      (j.v2v2 || 0) * P.estrella_plateada + (j.liga || 0) * P.liga
  })).sort((a, b) => b.puntos - a.puntos || String(a.nombre).localeCompare(String(b.nombre)));
  const max = Math.max.apply(null, conPuntos.map(j => j.puntos).concat([1]));

  /* insignias de cada jugador: una por cada trofeo que tenga, mas las
     medallas declaradas a mano. Los tres iconos son los mismos del podio. */
  const insignias = j => {
    const out = [];
    for (let i = 0; i < (j.torneo || 0); i++) out.push({ i: '🥇', t: T('circuito.p1d') });
    for (let i = 0; i < (j.v2v2 || 0); i++) out.push({ i: '🥈', t: T('circuito.p2d') });
    for (let i = 0; i < (j.liga || 0); i++) out.push({ i: '🏆', t: T('circuito.p3d') });
    (j.medallas || []).forEach(m => {
      if (m === 'oro') out.push({ i: '🥇', t: T('circuito.med_oro') });
      else if (m === 'plata') out.push({ i: '🥈', t: T('circuito.med_plata') });
      else if (m === 'bronce') out.push({ i: '🥉', t: T('circuito.med_bronce') });
    });
    return out;
  };

  const historia = c.historia || [];

  return `<div class="seccion">
    <h1>${esc(T('circuito.titulo'))}</h1>
    <p class="sub">${T('circuito.intro', c.intro || '')}</p>

    <div class="podio">
      <div class="puesto oro"><div class="icono">🥇</div>
        <b>${esc(T('circuito.podio'))}</b>
        <span class="peso">${esc(T('circuito.p1d'))} · ${esc(T('circuito.peso'))} ${P.estrella_dorada}</span></div>
      <div class="puesto plata"><div class="icono">🥈</div>
        <b>${esc(T('circuito.podio2'))}</b>
        <span class="peso">${esc(T('circuito.p2d'))} · ${esc(T('circuito.peso'))} ${P.estrella_plateada}</span></div>
      <div class="puesto"><div class="icono">🏆</div>
        <b>${esc(T('circuito.podio3'))}</b>
        <span class="peso">${esc(T('circuito.p3d'))} · ${esc(T('circuito.peso'))} ${P.liga}</span></div>
    </div>

    <div class="tarjeta">
      <h3>${esc(T('circuito.calculo'))}</h3>
      <p>${T('circuito.calculo_txt')}</p>
      <p style="font-size:20px;text-align:center;margin:18px 0">
        <b style="color:var(--oro)">${esc(T('circuito.puntos'))} = ${esc(T('circuito.torneo'))} × ${P.estrella_dorada}</b>
        &nbsp;+&nbsp;<b>${esc(T('circuito.v2v2'))} × ${P.estrella_plateada}</b>
        &nbsp;+&nbsp;<b>${esc(T('circuito.liga'))} × ${P.liga}</b></p>
      <p class="sub">${T('circuito.explica')}</p>
    </div>

    <h2>${esc(T('circuito.ranking'))}</h2>
    ${conPuntos.length ? `
    <div class="tabla-scroll"><table>
      <thead><tr><th>${esc(T('circuito.pos'))}</th><th>${esc(T('circuito.jugador'))}</th>
        <th>${esc(T('circuito.insignias'))}</th>
        <th class="num">${esc(T('circuito.torneo'))}</th><th class="num">${esc(T('circuito.v2v2'))}</th>
        <th class="num">${esc(T('circuito.liga'))}</th><th class="num">${esc(T('circuito.puntos'))}</th>
        <th>${esc(T('circuito.progreso'))}</th></tr></thead>
      <tbody>${conPuntos.map((j, i) => `<tr>
        <td class="escudo">${i + 1}</td>
        <td><b>${esc(j.nombre)}</b></td>
        <td class="insignias">${insignias(j).length
        ? insignias(j).map(x => `<span title="${esc(x.t)}">${x.i}</span>`).join('')
        : `<span class="sub">${esc(T('circuito.sin_titulos'))}</span>`}</td>
        <td class="num">${j.torneo || 0}</td><td class="num">${j.v2v2 || 0}</td>
        <td class="num">${j.liga || 0}</td><td class="num"><b>${j.puntos}</b></td>
        <td><span class="barra-puntos"><i style="width:${Math.round(j.puntos / max * 100)}%"></i></span></td>
      </tr>`).join('')}</tbody></table></div>` :
      `<div class="hueco">${T('circuito.vacio')}</div>`}

    <div class="tarjeta">
      <h3>${esc(T('circuito.cargar'))}</h3>
      <p class="sub">${T('circuito.cargar_sub')}</p>
      <textarea id="c-area" rows="6" placeholder="Nico, 2, 1, 0&#10;Santi, 1, 0, 1"
        style="width:100%;background:var(--panel2);border:1px solid var(--linea);
        border-radius:10px;color:var(--texto);padding:12px;font:13px ui-monospace,Consolas,monospace"></textarea>
      <div class="fil">
        <button class="btn oro" id="c-cargar">${esc(T('circuito.cargar_btn'))}</button>
        <button class="btn" id="c-exportar">${esc(T('circuito.exportar'))}</button>
        <button class="btn" id="c-vaciar">${esc(T('circuito.borrar'))}</button>
      </div>
    </div>

    <h2>${esc(T('circuito.premiacion'))}</h2>
    <div class="tarjeta"><div class="tabla-scroll"><table>
      <thead><tr><th>${esc(T('circuito.premio'))}</th><th>${esc(T('circuito.que_es'))}</th>
        <th class="num">${esc(T('circuito.peso'))}</th></tr></thead>
      <tbody>
        <tr><td><b>${esc(T('circuito.podio'))}</b></td><td>${esc(T('circuito.p1d'))}</td><td class="num">${P.estrella_dorada}</td></tr>
        <tr><td><b>${esc(T('circuito.podio2'))}</b></td><td>${esc(T('circuito.p2d'))}</td><td class="num">${P.estrella_plateada}</td></tr>
        <tr><td><b>${esc(T('circuito.podio3'))}</b></td><td>${esc(T('circuito.p3d'))}</td><td class="num">${P.liga}</td></tr>
      </tbody></table></div>
      <div class="hueco" style="margin-top:16px">${esc(T('circuito.falta_premios'))}</div>
    </div>

    <h2>${esc(T('circuito.historia'))}</h2>
    <p class="sub">${T('circuito.historia_sub')}</p>
    ${historia.length ? `
    <div class="tabla-scroll"><table>
      <thead><tr><th>${esc(T('circuito.temporada'))}</th><th>${esc(T('circuito.ganador'))}</th>
        <th>${esc(T('circuito.personajes'))}</th><th>${esc(T('circuito.notas'))}</th></tr></thead>
      <tbody>${historia.map(t => `<tr>
        <td><b>${esc(t.temporada || '')}</b></td>
        <td>${esc(t.ganador || '')}</td>
        <td>${(t.personajes || []).map(p => `<span class="tag">${esc(p)}</span>`).join(' ')}</td>
        <td class="sub">${esc(t.notas || '')}</td></tr>`).join('')}</tbody>
    </table></div>` : `<div class="hueco">${esc(T('circuito.sin_historia'))}</div>`}
  </div>`;
}

function conectarCircuito() {
  const btn = $('#c-cargar'), ex = $('#c-exportar'), vac = $('#c-vaciar'), area = $('#c-area');
  if (btn) btn.onclick = () => {
    const jugadores = area.value.split('\n').map(s => s.trim()).filter(Boolean).map(s => {
      const p = s.split(',').map(x => x.trim());
      return { nombre: p[0] || '—', torneo: +p[1] || 0, v2v2: +p[2] || 0, liga: +p[3] || 0 };
    });
    localStorage.setItem('circuito_jugadores', JSON.stringify(jugadores));
    render();
  };
  if (vac) vac.onclick = () => { localStorage.removeItem('circuito_jugadores'); render(); };
  if (ex) ex.onclick = () => {
    const jugadores = JSON.parse(localStorage.getItem('circuito_jugadores') || '[]');
    const datos = Object.assign({}, DATOS.circuito, { jugadores });
    descargar('circuito.json', datos);
  };
}

function descargar(nombre, datos) {
  const blob = new Blob([JSON.stringify(datos, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = nombre;
  a.click();
}

/* --------------------------------------------------------------- descargas */
function vistaDescargas() {
  const d = DATOS.descargas;
  return `<div class="seccion">
    <h1>${esc(T('descargas.titulo'))}</h1>
    <p class="sub">${T('descargas.intro', d.intro || '')}</p>
    ${d.categorias.map(cat => `
      <h2>${esc(cat.titulo)}</h2>
      <p class="sub">${esc(cat.descripcion || '')}</p>
      ${cat.items.map(it => `
        <div class="desc">
          <div class="icono">${esc(it.icono || '📦')}</div>
          <div class="cuerpo">
            <b>${esc(it.nombre)}</b>
            <p>${esc(it.desc || '')}</p>
            ${it.nota ? `<p class="sub" style="margin-top:6px">${esc(it.nota)}</p>` : ''}
          </div>
          ${it.href ? `<a class="btn" href="${esc(it.href)}" download>${esc(T('descargas.descargar'))}</a>`
      : `<span class="btn vacio">${esc(T('descargas.sin_archivo'))}</span>`}
        </div>`).join('')}
    `).join('')}
    <div class="hueco" style="margin-top:26px">${esc(T('descargas.nota_rom'))}</div>
  </div>`;
}

/* --------------------------------------------------------------- router */
function render() {
  const h = (location.hash || '#/').replace(/^#\/?/, '');
  const partes = h.split('/').filter(Boolean);
  const sec = partes[0] || '';
  let html = '';

  try {
    if (!sec) html = vistaInicio();
    else if (sec === 'personajes') html = vistaPersonajes();
    else if (sec === 'persona') html = vistaPersona(partes[1]);
    else if (sec === 'guias') html = vistaGuias();
    else if (sec === 'matchup') html = vistaMatchup();
    else if (sec === 'circuito') html = vistaCircuito();
    else if (sec === 'descargas') html = vistaDescargas();
    else html = vistaInicio();
  } catch (e) {
    html = `<div class="seccion"><h1>Error</h1><pre>${esc(e.stack || e)}</pre></div>`;
  }

  app.innerHTML = html;
  pintarMenu();
  conectarCombos(pjPorId(partes[1]) || { id: '-' });
  conectarMovelist();
  conectarMatchup();
  conectarCircuito();
  if (sec === 'persona' || sec === 'matchup') window.scrollTo(0, 0);
}

window.addEventListener('hashchange', render);

function montarSelector() {
  const sel = document.getElementById('idioma');
  if (!sel) return;
  sel.innerHTML = IDIOMAS.map(i =>
    `<option value="${i}"${i === IDIOMA ? ' selected' : ''}>${NOMBRES_IDIOMA[i]}</option>`).join('');
  sel.onchange = () => {
    localStorage.setItem('idioma', sel.value);
    IDIOMA = sel.value;
    render();
  };
}

document.addEventListener('DOMContentLoaded', async () => {
  const barraMenu = $('#menu');
  $('#hamburguesa').onclick = () => barraMenu.classList.toggle('abierto');
  barraMenu.addEventListener('click', e => {
    if (e.target.tagName === 'A') barraMenu.classList.remove('abierto');
  });

  const pedir = async f => {
    try { return await (await fetch('data/' + f)).json(); }
    catch (e) { console.error('no se pudo cargar ' + f, e); return null; }
  };
  const [pers, moves, circuito, descargas, extras, i18n] = await Promise.all([
    pedir('personajes.json'), pedir('moves.json'), pedir('circuito.json'),
    pedir('descargas.json'), pedir('extras.json'), pedir('i18n.json')
  ]);

  I18N = i18n || {};
  IDIOMA = detectarIdioma();

  DATOS.pers = pers || [];
  DATOS.moves = moves || {};
  DATOS.circuito = circuito || {
    pesos: { estrella_dorada: 1, estrella_plateada: 0.5, liga: 3 }, jugadores: []
  };
  DATOS.descargas = descargas || { categorias: [] };
  DATOS.extras = extras || {};
  DATOS.pers.forEach(p => {
    p.extras = DATOS.extras[p.id] || {};
    p.slug_foto = (p.retrato.match(/_([^_]+)\.png$/) || [])[1] || p.id;
  });

  montarSelector();
  render();
});