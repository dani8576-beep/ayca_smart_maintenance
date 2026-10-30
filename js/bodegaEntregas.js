// ===============================
// AYCA SMART — MÓDULO BODEGA: VALE DE ENTREGA/DEVOLUCIÓN MÚLTIPLE
// ===============================
// Tablas/función Supabase (2026-08-02_bodega_entregas_fase1.sql):
//   bodega_entregas / bodega_entrega_detalle — solo lectura desde el cliente.
//   fn_confirmar_entrega_bodega(...) — única puerta de escritura: recibe la
//   cabecera + un array de ítems y hace todo (stock de herramientas, reserva/
//   liberación de equipos, inserción del vale) en una sola transacción.
// Requiere: supabaseAYCA (database.js), mostrar() (app.js).

let _valeTipo = 'entrega';   // 'entrega' | 'devolucion'
let _valeItems = [];         // { tipo, codigo|id, nombre, cantidad, estado_devuelto }

// ─── Navegar al vale y resetear todo el formulario ───
function irBodegaVale(tipo) {
  _valeTipo = tipo === 'devolucion' ? 'devolucion' : 'entrega';
  _valeItems = [];

  const esDev = _valeTipo === 'devolucion';
  const topbar = document.getElementById('val_tituloTopbar');
  const card   = document.getElementById('val_tituloCard');
  if (topbar) topbar.textContent = esDev ? '📦 Nueva Devolución (Vale)' : '📦 Nueva Entrega (Vale)';
  if (card)   card.textContent   = esDev ? '1. Datos de la devolución' : '1. Datos de la entrega';

  const banner = document.getElementById('val_bannerResultado');
  if (banner) { banner.style.display = 'none'; banner.textContent = ''; }

  ['val_tecnico', 'val_obs'].forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
  const protoSel = document.getElementById('val_protocolo');
  if (protoSel) protoSel.value = '';
  const ubiSel = document.getElementById('val_ubicacion');
  if (ubiSel) ubiSel.value = '';
  const fechaEl = document.getElementById('val_fecha');
  if (fechaEl) fechaEl.valueAsDate = new Date();
  const tipoItemSel = document.getElementById('val_tipoItem');
  if (tipoItemSel) tipoItemSel.value = 'herramienta';
  const estWrap = document.getElementById('val_estadoDevueltoWrap');
  if (estWrap) estWrap.style.display = esDev ? 'block' : 'none';

  mostrar('bodega-vale');
  _valeCargarProtocolos();
  _valeCargarUbicaciones();
  _valeOnTipoChange();
  _valeRenderTabla();
}

// ══════════════════════════════════════════
// CATÁLOGOS (protocolo / ubicación)
// ══════════════════════════════════════════
async function _valeCargarProtocolos() {
  const sel = document.getElementById('val_protocolo');
  if (!sel) return;
  try {
    const { data, error } = await supabaseAYCA
      .from('protocolos_ayca')
      .select('numero, cliente, faena, fecha')
      .order('creado_en', { ascending: false })
      .limit(200);
    if (error) throw error;
    sel.innerHTML = '<option value="">— Sin vincular a un protocolo —</option>' +
      (data || []).map(p => `<option value="${p.numero}">${p.numero} — ${p.cliente || p.faena || '—'} (${p.fecha || '—'})</option>`).join('');
  } catch (e) {
    console.error('_valeCargarProtocolos:', e);
  }
}

async function _valeCargarUbicaciones() {
  const sel = document.getElementById('val_ubicacion');
  if (!sel) return;
  try {
    const { data, error } = await supabaseAYCA
      .from('bodega_ubicaciones')
      .select('id, nombre')
      .eq('activo', true)
      .order('nombre');
    if (error) throw error;
    sel.innerHTML = '<option value="">— Sin especificar —</option>' +
      (data || []).map(u => `<option value="${u.id}">${u.nombre}</option>`).join('');
  } catch (e) {
    console.error('_valeCargarUbicaciones:', e);
  }
}

// ══════════════════════════════════════════
// SELECTOR DE ÍTEM (herramienta / equipo, según tipo y entrega/devolución)
// ══════════════════════════════════════════
function _valeOnTipoChange() {
  const tipo = document.getElementById('val_tipoItem')?.value || 'herramienta';
  const cantEl = document.getElementById('val_cantidad');
  if (cantEl) {
    // Un equipo es una unidad física indivisible — el vale siempre reserva
    // exactamente 1 (fn_confirmar_entrega_bodega ignora la cantidad para equipos).
    if (tipo === 'equipo') { cantEl.value = '1'; cantEl.disabled = true; }
    else { cantEl.disabled = false; }
  }
  _valeCargarItemsSelect();
}

async function _valeCargarItemsSelect() {
  const sel = document.getElementById('val_item');
  if (!sel) return;
  const tipo = document.getElementById('val_tipoItem')?.value || 'herramienta';
  sel.innerHTML = '<option value="">Cargando...</option>';

  try {
    if (tipo === 'herramienta') {
      const { data, error } = await supabaseAYCA
        .from('herramientas')
        .select('codigo, nombre, cantidad_total, cantidad_disponible')
        .order('nombre');
      if (error) throw error;

      let lista = data || [];
      if (_valeTipo === 'entrega')    lista = lista.filter(h => (h.cantidad_disponible ?? 1) > 0);
      if (_valeTipo === 'devolucion') lista = lista.filter(h => (h.cantidad_total ?? 1) - (h.cantidad_disponible ?? 1) > 0);

      sel.innerHTML = '<option value="">— Seleccione herramienta —</option>';
      lista.forEach(h => {
        const opt = document.createElement('option');
        opt.value = h.codigo;
        opt.textContent = `${h.nombre}  [${h.codigo}]`;
        opt.dataset.nombre = h.nombre;
        opt.dataset.disponible = h.cantidad_disponible ?? 1;
        opt.dataset.total = h.cantidad_total ?? 1;
        sel.appendChild(opt);
      });
    } else {
      const { data, error } = await supabaseAYCA
        .from('equipos_bodega')
        .select('id, codigo, nombre, estado_logistico')
        .order('nombre');
      if (error) throw error;

      let lista = data || [];
      if (_valeTipo === 'entrega')    lista = lista.filter(eq => eq.estado_logistico === 'disponible');
      if (_valeTipo === 'devolucion') lista = lista.filter(eq => eq.estado_logistico === 'reservado');

      sel.innerHTML = '<option value="">— Seleccione equipo —</option>';
      lista.forEach(eq => {
        const opt = document.createElement('option');
        opt.value = eq.id;
        opt.textContent = `${eq.nombre}  [${eq.codigo}]`;
        opt.dataset.nombre = eq.nombre;
        sel.appendChild(opt);
      });
    }
  } catch (e) {
    sel.innerHTML = `<option value="">Error al cargar: ${e.message}</option>`;
  }

  _valeOnItemChange();
}

function _valeOnItemChange() {
  const sel  = document.getElementById('val_item');
  const disp = document.getElementById('val_dispText');
  if (!sel || !disp) return;
  const opt  = sel.selectedOptions[0];
  const tipo = document.getElementById('val_tipoItem')?.value || 'herramienta';

  if (!opt || !opt.value) { disp.textContent = ''; return; }

  if (tipo === 'herramienta') {
    disp.textContent = `Disponible: ${opt.dataset.disponible} / ${opt.dataset.total}`;
  } else {
    disp.textContent = _valeTipo === 'entrega' ? 'Disponible para entregar' : 'Reservado — listo para devolver';
  }
}

// ══════════════════════════════════════════
// LISTA DE ÍTEMS DEL VALE
// ══════════════════════════════════════════
function valeAgregarItem() {
  const tipo = document.getElementById('val_tipoItem')?.value || 'herramienta';
  const sel  = document.getElementById('val_item');
  const val  = sel?.value || '';
  const opt  = sel?.selectedOptions[0];
  const cantidad = parseInt(document.getElementById('val_cantidad')?.value) || 1;
  const estadoDevuelto = _valeTipo === 'devolucion'
    ? (document.getElementById('val_estadoDevuelto')?.value || null)
    : null;

  if (!val) { alert('Selecciona un ítem.'); return; }

  if (tipo === 'herramienta') {
    const disponible = parseInt(opt.dataset.disponible) || 0;
    const total      = parseInt(opt.dataset.total) || 0;
    const fuera      = total - disponible;
    const yaAgregado = _valeItems
      .filter(it => it.tipo === 'herramienta' && it.codigo === val)
      .reduce((sum, it) => sum + it.cantidad, 0);

    if (_valeTipo === 'entrega' && (yaAgregado + cantidad) > disponible) {
      alert(`Solo hay ${disponible} unidad${disponible!==1?'es':''} disponible${disponible!==1?'s':''} de "${opt.dataset.nombre}"${yaAgregado ? ` (ya agregaste ${yaAgregado})` : ''}.`);
      return;
    }
    if (_valeTipo === 'devolucion' && (yaAgregado + cantidad) > fuera) {
      alert(`Solo hay ${fuera} unidad${fuera!==1?'es':''} fuera de bodega de "${opt.dataset.nombre}"${yaAgregado ? ` (ya agregaste ${yaAgregado})` : ''}.`);
      return;
    }

    _valeItems.push({
      tipo: 'herramienta', codigo: val, nombre: opt.dataset.nombre,
      cantidad, estado_devuelto: estadoDevuelto
    });
  } else {
    if (_valeItems.some(it => it.tipo === 'equipo' && it.id === val)) {
      alert('Ese equipo ya está en la lista.');
      return;
    }
    _valeItems.push({
      tipo: 'equipo', id: val, nombre: opt.dataset.nombre,
      cantidad: 1, estado_devuelto: estadoDevuelto
    });
  }

  _valeRenderTabla();

  sel.value = '';
  const disp = document.getElementById('val_dispText');
  if (disp) disp.textContent = '';
  const cantEl = document.getElementById('val_cantidad');
  if (cantEl && tipo === 'herramienta') cantEl.value = '1';
}

function valeQuitarItem(idx) {
  _valeItems.splice(idx, 1);
  _valeRenderTabla();
}

function _valeRenderTabla() {
  const tbody = document.getElementById('val_tablaBody');
  const countTipos     = document.getElementById('val_countTipos');
  const countUnidades  = document.getElementById('val_countUnidades');
  if (!tbody) return;

  tbody.innerHTML = _valeItems.length
    ? _valeItems.map((it, i) => `
      <tr>
        <td style="padding:6px">${it.tipo === 'herramienta' ? '🔧 Herramienta' : '📟 Equipo'}</td>
        <td style="padding:6px">${it.nombre}</td>
        <td style="padding:6px">${it.cantidad}</td>
        <td style="padding:6px"><button class="btn-rojo" style="padding:4px 10px;font-size:11px" onclick="valeQuitarItem(${i})">✖</button></td>
      </tr>`).join('')
    : '<tr><td colspan="4" style="text-align:center;color:#6b7280;padding:16px;font-style:italic">Aún no has agregado ítems</td></tr>';

  if (countTipos)    countTipos.textContent    = _valeItems.length;
  if (countUnidades) countUnidades.textContent = _valeItems.reduce((s, it) => s + it.cantidad, 0);
}

// ══════════════════════════════════════════
// CONFIRMAR VALE
// ══════════════════════════════════════════
async function valeConfirmar() {
  const g = id => document.getElementById(id)?.value?.trim() || '';
  const tecnico    = g('val_tecnico');
  const protocolo  = g('val_protocolo') || null;
  const ubicacion  = g('val_ubicacion') || null;
  const fecha      = g('val_fecha') || new Date().toISOString().slice(0, 10);
  const obs        = g('val_obs') || null;

  if (!tecnico)          { alert('Ingresa el técnico responsable.'); return; }
  if (!_valeItems.length) { alert('Agrega al menos un ítem al vale.'); return; }

  const items = _valeItems.map(it => it.tipo === 'herramienta'
    ? { tipo: 'herramienta', codigo: it.codigo, cantidad: it.cantidad, estado_devuelto: it.estado_devuelto }
    : { tipo: 'equipo', id: it.id, cantidad: it.cantidad, estado_devuelto: it.estado_devuelto }
  );

  const btn = document.getElementById('val_btnConfirmar');
  if (btn) btn.disabled = true;

  try {
    const { data, error } = await supabaseAYCA.rpc('fn_confirmar_entrega_bodega', {
      p_tipo: _valeTipo,
      p_tecnico_responsable: tecnico,
      p_items: items,
      p_protocolo_numero: protocolo,
      p_ubicacion_destino_id: ubicacion,
      p_fecha: fecha,
      p_observaciones: obs
    });
    if (error) throw error;

    const fila = Array.isArray(data) ? data[0] : data;
    const numeroVale = fila?.numero_vale ?? '—';

    const banner = document.getElementById('val_bannerResultado');
    if (banner) {
      banner.style.display = 'block';
      banner.textContent = `✅ Vale N° ${numeroVale} confirmado correctamente (${_valeItems.length} ítem${_valeItems.length !== 1 ? 's' : ''}).`;
    }

    _valeItems = [];
    _valeRenderTabla();
    ['val_tecnico', 'val_obs'].forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
    _valeCargarItemsSelect();
  } catch (e) {
    alert('❌ Error al confirmar el vale: ' + e.message);
    console.error('valeConfirmar:', e);
  } finally {
    if (btn) btn.disabled = false;
  }
}

// ══════════════════════════════════════════
// VALES PENDIENTES DE RETIRO (Fase C)
// ══════════════════════════════════════════
// Generados por fn_generar_vale_desde_recursos() (Fase B, eventosRecursos.js)
// en estado 'pendiente' — todavía NO movieron stock. Bodega los revisa aquí y
// los confirma con fn_confirmar_vale_pendiente(), que recién ahí valida
// stock/disponibilidad real y descuenta/reserva (o rechaza el vale entero si
// algo ya no alcanza).

let _valPendConfirmando = false; // evita doble clic en "Confirmar retiro"

function irBodegaValesPendientes() {
  mostrar('bodega-vales-pendientes');
  valPendCargarLista();
}

async function valPendCargarLista() {
  const cont = document.getElementById('valPend_lista');
  if (!cont) return;
  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando vales pendientes...</p>';

  try {
    const { data: vales, error } = await supabaseAYCA
      .from('bodega_entregas')
      .select('id, numero_vale, tipo, tecnico_responsable, fecha, observaciones, eventos_mantencion(numero, nombre), bodega_ubicaciones(nombre)')
      .eq('estado', 'pendiente')
      .order('creado_en', { ascending: true });
    if (error) throw error;

    if (!vales || !vales.length) {
      cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">No hay vales pendientes de retiro.</p>';
      return;
    }

    const valeIds = vales.map(v => v.id);
    const { data: detalles, error: eDet } = await supabaseAYCA
      .from('bodega_entrega_detalle')
      .select('entrega_id, herramienta_codigo, cantidad, herramientas(nombre), equipos_bodega(codigo, nombre)')
      .in('entrega_id', valeIds);
    if (eDet) throw eDet;

    const detallesPorVale = {};
    (detalles || []).forEach(d => { (detallesPorVale[d.entrega_id] ||= []).push(d); });

    cont.innerHTML = vales.map(v => _valPendTarjeta(v, detallesPorVale[v.id] || [])).join('');
  } catch (e) {
    console.error('valPendCargarLista:', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar: ${e.message}</p>`;
  }
}

function _valPendTarjeta(v, items) {
  const itemsHtml = items.length
    ? items.map(it => {
        const texto = it.herramienta_codigo
          ? `🔧 ${it.herramientas?.nombre || '—'} [${it.herramienta_codigo}] × ${it.cantidad}`
          : `📟 ${it.equipos_bodega?.nombre || '—'} [${it.equipos_bodega?.codigo || '—'}]`;
        return `<div style="font-size:12px;color:#374151;padding:2px 0">${texto}</div>`;
      }).join('')
    : '<div style="font-size:12px;color:#9ca3af">Sin ítems</div>';

  return `
    <div class="card" style="border-left:4px solid #d97706;padding:12px 14px;margin:8px 0">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:6px;margin-bottom:4px">
        <b style="color:#0b3158;font-size:14px">Vale N° ${v.numero_vale}</b>
        <span style="flex-shrink:0;font-size:10px;background:#d97706;color:white;padding:2px 8px;border-radius:99px">${v.tipo === 'entrega' ? 'Entrega' : 'Devolución'}</span>
      </div>
      <div style="font-size:12px;color:#6b7280;margin-bottom:6px">
        👤 ${v.tecnico_responsable || '—'} &nbsp;·&nbsp; 📅 ${v.fecha || '—'}
        ${v.eventos_mantencion ? `<br>🗓️ Evento: ${v.eventos_mantencion.numero || '—'} — ${v.eventos_mantencion.nombre || '—'}` : ''}
        ${v.bodega_ubicaciones?.nombre ? `<br>📍 ${v.bodega_ubicaciones.nombre}` : ''}
      </div>
      <div style="border-top:1px solid #f1f5f9;padding-top:6px;margin-top:4px">
        ${itemsHtml}
      </div>
      <div style="margin-top:10px;text-align:right">
        <button class="btn-verde" style="width:auto;padding:6px 14px;font-size:12px" onclick="valPendConfirmar('${v.id}')">✅ Confirmar retiro</button>
      </div>
    </div>`;
}

async function valPendConfirmar(entregaId) {
  if (_valPendConfirmando) return;
  if (!confirm('¿Confirmar este vale? Se validará stock/disponibilidad real y se descontará/reservará ahora.')) return;

  _valPendConfirmando = true;
  try {
    const { data, error } = await supabaseAYCA.rpc('fn_confirmar_vale_pendiente', { p_entrega_id: entregaId });
    if (error) throw error;

    const fila = Array.isArray(data) ? data[0] : data;
    alert(`✅ Vale N° ${fila?.numero_vale ?? '—'} confirmado correctamente.`);
    await valPendCargarLista();
  } catch (e) {
    alert('❌ Error al confirmar el vale: ' + e.message);
    console.error('valPendConfirmar:', e);
  } finally {
    _valPendConfirmando = false;
  }
}
