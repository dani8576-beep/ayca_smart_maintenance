// ===============================
// AYCA SMART — RECURSOS SOLICITADOS DEL EVENTO (Fase B)
// ===============================
// Tablas/funciones Supabase (2026-08-03_recursos_evento_bodega_fase_a.sql,
// 2026-08-03_recursos_evento_fase_b_agregar_equipo.sql):
//   evento_recursos — herramienta_codigo XOR insumo_codigo XOR equipo_bodega_id
//     (o ninguno, recurso genérico). Filas origen='plantilla' se generan solas
//     al agregar/quitar equipos (fn_consolidar_recursos_evento) y todavía NO
//     traen equipo_bodega_id asignado — limitación conocida, ver ficha.
//   fn_agregar_recurso_manual_evento / fn_quitar_recurso_evento /
//   fn_aprobar_recurso_evento / fn_aprobar_evento_recursos — alta/baja/aprobación.
//   fn_generar_vale_desde_recursos — arma un vale 'pendiente' en bodega_entregas
//     con las líneas aprobadas y con ítem real asignado (NO mueve stock).
//   fn_confirmar_vale_pendiente — lo usa Bodega para confirmar el vale (fuera
//     del alcance de esta pantalla; vive en el módulo de Bodega).
// Requiere: supabaseAYCA (database.js), eventoActualId (eventos.js),
//   _escJs() (permisos.js). Se carga DESPUÉS de eventos.js.

const EVENTOS_RECURSO_CATEGORIA_LABEL = {
  herramienta:  '🔧 Herramienta',
  instrumento:  '📟 Instrumento',
  equipo_apoyo: '🧰 Equipo de apoyo',
  epp:          '🦺 EPP',
  repuesto:     '⚙️ Repuesto',
  consumible:   '🧴 Consumible',
  material:     '🧱 Material'
};

let _eventosRecursosCache = [];         // últimas filas cargadas (para recalcular botones sin volver a Supabase)
let _eventosRecursosEventoTerminal = false;
let _eventosProcesandoRecurso = false;  // evita doble clic en acciones de recurso

// ══════════════════════════════════════════
// CARGA Y RENDER PRINCIPAL
// ══════════════════════════════════════════
async function eventosCargarRecursosDelEvento(eventoTerminal) {
  const cont = document.getElementById('eventoRecursosCont');
  if (!cont || !eventoActualId) return;

  _eventosRecursosEventoTerminal = eventoTerminal;
  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:16px">Cargando recursos...</p>';

  try {
    // herramienta_codigo/equipo_bodega_id/insumo_codigo son FK reales →
    // embebibles directo, igual que equipos(tag,nombre) en la sección de Equipos.
    const { data, error } = await supabaseAYCA
      .from('evento_recursos')
      .select(`
        id, categoria_recurso, nombre_generico, herramienta_codigo, insumo_codigo, equipo_bodega_id,
        cantidad_sugerida, cantidad_aprobada, origen, estado_fila, vale_detalle_id,
        herramientas(nombre), equipos_bodega(codigo, nombre), insumos_bodega(nombre)
      `)
      .eq('evento_mantencion_id', eventoActualId)
      .neq('estado_fila', 'eliminado')
      .order('creado_en', { ascending: true });

    if (error) throw error;

    _eventosRecursosCache = data || [];
    cont.innerHTML = _eventosRecursosRenderBotones() + _eventosRecursosRenderLista();
  } catch (e) {
    console.error('eventosCargarRecursosDelEvento:', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar recursos: ${e.message}</p>`;
  }
}

function _eventosRecursosRenderBotones() {
  if (_eventosRecursosEventoTerminal) {
    return `<p style="color:#92400e;background:#fffbeb;border:1px solid #fcd34d;border-radius:8px;padding:8px 12px;font-size:12px;margin:0 0 8px">
      ⚠️ Este evento está finalizado/cancelado — no se pueden modificar recursos.
    </p>`;
  }

  const hayNoConformes = _eventosRecursosCache.some(r =>
    r.cantidad_aprobada == null || Number(r.cantidad_aprobada) !== Number(r.cantidad_sugerida)
  );
  const hayListosParaVale = _eventosRecursosCache.some(r =>
    r.cantidad_aprobada != null && r.vale_detalle_id == null && (r.herramienta_codigo || r.equipo_bodega_id)
  );

  return `
    <div id="eventoRecursoFormWrap" style="display:none;margin-bottom:12px"></div>
    <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:10px">
      <button class="btn-gris" style="width:auto;padding:8px 14px;font-size:13px" onclick="eventosMostrarFormRecurso()">+ Agregar recurso</button>
      ${hayNoConformes ? `<button class="btn-verde" style="width:auto;padding:8px 14px;font-size:13px" onclick="eventosAprobarTodoRecursos()">✅ Aprobar todo</button>` : ''}
      ${hayListosParaVale ? `<button class="btn-verde" style="width:auto;padding:8px 14px;font-size:13px" onclick="eventosGenerarValeRecursos()">📤 Generar vale para Bodega</button>` : ''}
    </div>`;
}

function _eventosRecursosRenderLista() {
  if (!_eventosRecursosCache.length) {
    return '<p style="color:#6b7280;text-align:center;padding:16px">Sin recursos solicitados.</p>';
  }
  return _eventosRecursosCache.map(_eventosRecursoTarjeta).join('');
}

function _eventosRecursoTarjeta(r) {
  const conforme = r.cantidad_aprobada != null && Number(r.cantidad_aprobada) === Number(r.cantidad_sugerida);
  const clr = conforme ? '#16a34a' : (r.cantidad_aprobada != null ? '#0b5cc7' : '#6b7280');
  const lbl = conforme ? 'Aprobado' : (r.cantidad_aprobada != null ? 'Aprobado (parcial)' : 'Pendiente');

  let itemTexto = '<span style="color:#9ca3af">Sin ítem de Bodega asignado</span>';
  if (r.herramienta_codigo)      itemTexto = `🔧 ${r.herramientas?.nombre || '—'} [${r.herramienta_codigo}]`;
  else if (r.equipo_bodega_id)   itemTexto = `📟 ${r.equipos_bodega?.nombre || '—'} [${r.equipos_bodega?.codigo || '—'}]`;
  else if (r.insumo_codigo)      itemTexto = `📦 ${r.insumos_bodega?.nombre || '—'} [${r.insumo_codigo}]`;

  const enVale = r.vale_detalle_id != null;

  let acciones = '';
  if (!_eventosRecursosEventoTerminal) {
    acciones = '<div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end">';
    if (!conforme) {
      acciones += `<button class="btn-verde" style="width:auto;padding:6px 12px;font-size:12px" onclick="eventosAprobarRecurso('${r.id}')">✅ Aprobar</button>`;
    }
    if (!enVale) {
      acciones += `<button class="btn-rojo" style="width:auto;padding:6px 12px;font-size:12px" onclick="eventosQuitarRecurso('${r.id}', '${_escJs(r.nombre_generico)}')">✖ Quitar</button>`;
    }
    acciones += '</div>';
  }

  return `
    <div class="card" style="border-left:4px solid ${clr};padding:10px 12px;margin:6px 0">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:6px;margin-bottom:4px">
        <b style="color:#0b3158;font-size:13px">${r.nombre_generico}</b>
        <span style="flex-shrink:0;font-size:10px;background:${clr};color:white;padding:2px 8px;border-radius:99px">${lbl}</span>
      </div>
      <div style="font-size:12px;color:#6b7280">
        ${EVENTOS_RECURSO_CATEGORIA_LABEL[r.categoria_recurso] || r.categoria_recurso}
        &nbsp;·&nbsp; ${r.origen === 'plantilla' ? '🔖 Plantilla' : '✍️ Manual'}
        ${enVale ? '&nbsp;·&nbsp; <span style="color:#0b5cc7">📤 En vale</span>' : ''}
        <br>${itemTexto}
        <br>Sugerido: ${r.cantidad_sugerida}${r.cantidad_aprobada != null ? ` · Aprobado: ${r.cantidad_aprobada}` : ''}
      </div>
      ${acciones}
    </div>`;
}

// ══════════════════════════════════════════
// AGREGAR RECURSO MANUAL (form inline, sin pantalla nueva)
// ══════════════════════════════════════════
function eventosMostrarFormRecurso() {
  const wrap = document.getElementById('eventoRecursoFormWrap');
  if (!wrap) return;
  wrap.style.display = 'block';
  wrap.innerHTML = `
    <div class="card" style="padding:12px 14px">
      <h4 style="margin:0 0 10px;color:#0b3158">Nuevo recurso manual</h4>

      <label style="font-size:12px;font-weight:bold;color:#374151">Categoría *</label>
      <select id="rec_categoria" onchange="_eventosOnCategoriaRecursoChange()" style="margin-bottom:8px">
        <option value="herramienta">🔧 Herramienta</option>
        <option value="instrumento">📟 Instrumento</option>
        <option value="equipo_apoyo">🧰 Equipo de apoyo</option>
        <option value="epp">🦺 EPP</option>
        <option value="repuesto">⚙️ Repuesto</option>
        <option value="consumible">🧴 Consumible</option>
        <option value="material">🧱 Material</option>
      </select>

      <label style="font-size:12px;font-weight:bold;color:#374151">Nombre *</label>
      <input type="text" id="rec_nombre" placeholder="Ej: Multímetro digital" style="margin-bottom:8px">

      <label style="font-size:12px;font-weight:bold;color:#374151">Cantidad sugerida *</label>
      <input type="number" id="rec_cantidad" min="0.01" step="1" value="1" style="margin-bottom:8px">

      <label style="font-size:12px;font-weight:bold;color:#374151">Ítem real de Bodega (opcional)</label>
      <select id="rec_item" style="margin-bottom:10px">
        <option value="">Cargando...</option>
      </select>

      <div style="display:flex;gap:8px">
        <button class="btn-verde" style="flex:1" onclick="eventosGuardarRecursoManual()">💾 Guardar</button>
        <button class="btn-gris" style="flex:1" onclick="eventosOcultarFormRecurso()">✖ Cancelar</button>
      </div>
    </div>`;
  _eventosOnCategoriaRecursoChange();
}

function eventosOcultarFormRecurso() {
  const wrap = document.getElementById('eventoRecursoFormWrap');
  if (wrap) { wrap.style.display = 'none'; wrap.innerHTML = ''; }
}

// ── Repuebla el selector de "ítem real" según la categoría elegida ──
async function _eventosOnCategoriaRecursoChange() {
  const categoria = document.getElementById('rec_categoria')?.value;
  const sel = document.getElementById('rec_item');
  if (!sel) return;
  sel.innerHTML = '<option value="">Cargando...</option>';

  try {
    if (categoria === 'herramienta') {
      const { data, error } = await supabaseAYCA.from('herramientas').select('codigo, nombre').order('nombre');
      if (error) throw error;
      sel.innerHTML = '<option value="">— Sin ítem específico —</option>' +
        (data || []).map(h => `<option value="${h.codigo}">${h.nombre} [${h.codigo}]</option>`).join('');
    } else if (categoria === 'instrumento' || categoria === 'equipo_apoyo') {
      const { data, error } = await supabaseAYCA.from('equipos_bodega').select('id, codigo, nombre').order('nombre');
      if (error) throw error;
      sel.innerHTML = '<option value="">— Sin ítem específico —</option>' +
        (data || []).map(eq => `<option value="${eq.id}">${eq.nombre} [${eq.codigo}]</option>`).join('');
    } else {
      // epp / repuesto / consumible / material — insumos_bodega.categoria usa
      // el mismo vocabulario (trigger fn_validar_categoria_evento_recursos lo exige).
      const { data, error } = await supabaseAYCA
        .from('insumos_bodega').select('codigo, nombre').eq('categoria', categoria).order('nombre');
      if (error) throw error;
      sel.innerHTML = '<option value="">— Sin ítem específico —</option>' +
        (data || []).map(i => `<option value="${i.codigo}">${i.nombre} [${i.codigo}]</option>`).join('');
    }
  } catch (e) {
    sel.innerHTML = `<option value="">Error al cargar: ${e.message}</option>`;
  }
}

async function eventosGuardarRecursoManual() {
  const categoria = document.getElementById('rec_categoria')?.value;
  const nombre    = document.getElementById('rec_nombre')?.value?.trim();
  const cantidad  = parseFloat(document.getElementById('rec_cantidad')?.value);
  const itemVal   = document.getElementById('rec_item')?.value || null;

  if (!nombre) { alert('Ingresa un nombre para el recurso.'); return; }
  if (isNaN(cantidad) || cantidad <= 0) { alert('La cantidad sugerida debe ser mayor a 0.'); return; }

  const params = {
    p_evento_id: eventoActualId,
    p_categoria_recurso: categoria,
    p_nombre_generico: nombre,
    p_cantidad_sugerida: cantidad,
    p_herramienta_codigo: categoria === 'herramienta' ? itemVal : null,
    p_insumo_codigo: ['epp', 'repuesto', 'consumible', 'material'].includes(categoria) ? itemVal : null,
    p_equipo_bodega_id: (categoria === 'instrumento' || categoria === 'equipo_apoyo') ? itemVal : null
  };

  try {
    const { error } = await supabaseAYCA.rpc('fn_agregar_recurso_manual_evento', params);
    if (error) throw error;
    eventosOcultarFormRecurso();
    await eventosCargarRecursosDelEvento(_eventosRecursosEventoTerminal);
  } catch (e) {
    alert('❌ Error al agregar el recurso: ' + e.message);
    console.error('eventosGuardarRecursoManual:', e);
  }
}

// ══════════════════════════════════════════
// APROBAR / QUITAR / GENERAR VALE
// ══════════════════════════════════════════
async function eventosAprobarRecurso(id) {
  if (_eventosProcesandoRecurso) return;

  const linea = _eventosRecursosCache.find(r => r.id === id);
  const sugerida = linea ? linea.cantidad_sugerida : null;

  const ingresado = prompt('Cantidad a aprobar:', sugerida != null ? String(sugerida) : '1');
  if (ingresado === null) return; // canceló el prompt
  const cantidad = parseFloat(ingresado);
  if (isNaN(cantidad) || cantidad < 0) { alert('Cantidad inválida.'); return; }

  _eventosProcesandoRecurso = true;
  try {
    const { error } = await supabaseAYCA.rpc('fn_aprobar_recurso_evento', {
      p_evento_recurso_id: id,
      p_cantidad_aprobada: cantidad
    });
    if (error) throw error;
    await eventosCargarRecursosDelEvento(_eventosRecursosEventoTerminal);
  } catch (e) {
    alert('❌ Error al aprobar: ' + e.message);
    console.error('eventosAprobarRecurso:', e);
  } finally {
    _eventosProcesandoRecurso = false;
  }
}

async function eventosAprobarTodoRecursos() {
  if (_eventosProcesandoRecurso) return;
  if (!confirm('¿Aprobar todas las líneas de recursos pendientes con su cantidad sugerida?')) return;

  _eventosProcesandoRecurso = true;
  try {
    const { error } = await supabaseAYCA.rpc('fn_aprobar_evento_recursos', { p_evento_id: eventoActualId });
    if (error) throw error;
    await eventosCargarRecursosDelEvento(_eventosRecursosEventoTerminal);
  } catch (e) {
    alert('❌ Error al aprobar todo: ' + e.message);
    console.error('eventosAprobarTodoRecursos:', e);
  } finally {
    _eventosProcesandoRecurso = false;
  }
}

async function eventosQuitarRecurso(id, nombre) {
  if (_eventosProcesandoRecurso) return;

  const motivo = prompt(`Motivo para quitar "${nombre}" (obligatorio):`, '');
  if (motivo === null) return; // canceló
  if (!motivo.trim()) { alert('Debes indicar un motivo.'); return; }

  _eventosProcesandoRecurso = true;
  try {
    const { error } = await supabaseAYCA.rpc('fn_quitar_recurso_evento', {
      p_evento_recurso_id: id,
      p_motivo_modificacion: motivo.trim()
    });
    if (error) throw error;
    await eventosCargarRecursosDelEvento(_eventosRecursosEventoTerminal);
  } catch (e) {
    alert('❌ Error al quitar: ' + e.message);
    console.error('eventosQuitarRecurso:', e);
  } finally {
    _eventosProcesandoRecurso = false;
  }
}

async function eventosGenerarValeRecursos() {
  if (_eventosProcesandoRecurso) return;
  if (!confirm('¿Generar un vale de Bodega con las líneas aprobadas y con ítem asignado?\n\nEsto NO mueve stock todavía — Bodega deberá confirmarlo.')) return;

  _eventosProcesandoRecurso = true;
  try {
    const { data, error } = await supabaseAYCA.rpc('fn_generar_vale_desde_recursos', {
      p_evento_id: eventoActualId
    });
    if (error) throw error;

    const fila = Array.isArray(data) ? data[0] : data;
    alert(
      `✅ Vale N° ${fila?.numero_vale ?? '—'} generado (pendiente de confirmar por Bodega).\n` +
      `Ítems incluidos: ${fila?.items_incluidos ?? '—'}` +
      (fila?.items_omitidos ? `\nÍtems que quedaron fuera (sin ítem asignado, o categoría EPP/repuesto/consumible/material): ${fila.items_omitidos}` : '')
    );
    await eventosCargarRecursosDelEvento(_eventosRecursosEventoTerminal);
  } catch (e) {
    alert('❌ Error al generar el vale: ' + e.message);
    console.error('eventosGenerarValeRecursos:', e);
  } finally {
    _eventosProcesandoRecurso = false;
  }
}
