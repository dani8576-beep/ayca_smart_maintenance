// ===============================
// AYCA SMART — MÓDULO BODEGA
// ===============================
// Tablas Supabase requeridas:
//   herramientas (codigo PK, nombre, marca, modelo, serie, categoria,
//                 estado, ubicacion, responsable, faena,
//                 cantidad_total, cantidad_disponible,
//                 fecha_ingreso, fecha_calibracion, fecha_vencimiento,
//                 observaciones, creado_en)
//   herramientas_movimientos (id serial PK, codigo_herramienta, tipo,
//                 cantidad, tecnico, faena, ubicacion, fecha, observaciones, creado_en)

const TABLA_HERR = 'herramientas';
const TABLA_MOV  = 'herramientas_movimientos';

// ─── Navegar a bodega-importar CSV ───
function irImportar() {
  mostrar('bodega-importar');
  _bodegaCSVDatos = [];
  const prev = document.getElementById('bod_impPreview');
  const res  = document.getElementById('bod_impResultado');
  const btn  = document.getElementById('bod_btnImportar');
  const inp  = document.getElementById('bod_impArchivo');
  if (prev) prev.innerHTML = '';
  if (res)  res.innerHTML  = '';
  if (inp)  inp.value      = '';
  if (btn)  { btn.disabled = true; btn.style.opacity = '0.5'; }
}

// ─── Navegar a bodega-inventario y cargar ───
function irInventario() {
  mostrar('bodega-inventario');
  bodegaCargarInventario();
}

// ─── Navegar a bodega-entregar y cargar selector ───
function irEntregar() {
  mostrar('bodega-entregar');
  bodegaCargarSelector('bod_entCodigo', 'entregar');
  const fechaEl = document.getElementById('bod_entFecha');
  if (fechaEl && !fechaEl.value) fechaEl.valueAsDate = new Date();
}

// ─── Navegar a bodega-devolver y cargar selector ───
function irDevolver() {
  mostrar('bodega-devolver');
  bodegaCargarSelector('bod_devCodigo', 'devolver');
  const fechaEl = document.getElementById('bod_devFecha');
  if (fechaEl && !fechaEl.value) fechaEl.valueAsDate = new Date();
}

// ─── Navegar a bodega-reporte y cargar ───
function irReporte() {
  mostrar('bodega-reporte');
  bodegaCargarReporte();
}

// ─── Navegar a bodega-registrar ───
function irRegistrar() {
  mostrar('bodega-registrar');
  const fechaEl = document.getElementById('bod_fechaIngreso');
  if (fechaEl && !fechaEl.value) fechaEl.valueAsDate = new Date();
}

// ══════════════════════════════════════════
// REGISTRAR HERRAMIENTA
// ══════════════════════════════════════════
async function bodegaRegistrar() {
  const g  = id => document.getElementById(id)?.value?.trim() || '';
  const cantidad = parseInt(g('bod_cantidad')) || 1;
  const herr = {
    codigo:             g('bod_codigo'),
    nombre:             g('bod_nombre'),
    marca:              g('bod_marca'),
    modelo:             g('bod_modelo'),
    serie:              g('bod_serie'),
    categoria:          g('bod_categoria'),
    estado:             g('bod_estado'),
    ubicacion:          g('bod_ubicacion'),
    responsable:        g('bod_responsable'),
    faena:              g('bod_faena'),
    cantidad_total:      cantidad,
    cantidad_disponible: cantidad,
    fecha_ingreso:      g('bod_fechaIngreso')       || null,
    fecha_calibracion:  g('bod_fechaCalibracion')   || null,
    fecha_vencimiento:  g('bod_fechaVencimiento')   || null,
    observaciones:      g('bod_observaciones'),
    creado_en:          new Date().toISOString()
  };

  if (!herr.codigo || !herr.nombre) {
    alert('El Código interno y el Nombre son obligatorios.');
    return;
  }

  try {
    const { error } = await supabaseAYCA
      .from(TABLA_HERR)
      .upsert([herr], { onConflict: 'codigo' });
    if (error) throw error;

    alert(`✅ Herramienta "${herr.nombre}" registrada correctamente.\nCódigo: ${herr.codigo}`);
    _bodegaLimpiarForm();
    mostrar('bodega');
  } catch (e) {
    alert('❌ Error al registrar: ' + e.message);
    console.error('bodegaRegistrar:', e);
  }
}

function _bodegaLimpiarForm() {
  ['bod_codigo','bod_nombre','bod_marca','bod_modelo','bod_serie','bod_categoria',
   'bod_responsable','bod_faena','bod_fechaIngreso','bod_fechaCalibracion',
   'bod_fechaVencimiento','bod_observaciones'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  const cant = document.getElementById('bod_cantidad');
  if (cant) cant.value = '1';
  const est = document.getElementById('bod_estado');
  if (est) est.value = 'Disponible';
  const ub = document.getElementById('bod_ubicacion');
  if (ub) ub.value = 'Bodega';
}

// ══════════════════════════════════════════
// INVENTARIO
// ══════════════════════════════════════════
async function bodegaCargarInventario() {
  const cont = document.getElementById('bod_listaInventario');
  if (!cont) return;
  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando inventario...</p>';

  try {
    const filtro = document.getElementById('bod_filtroEstado')?.value || '';
    let query = supabaseAYCA.from(TABLA_HERR).select('*').order('nombre');
    if (filtro) query = query.eq('estado', filtro);
    const { data, error } = await query;
    if (error) throw error;

    if (!data || data.length === 0) {
      cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">No hay herramientas registradas.</p>';
      return;
    }

    const clr = { Disponible:'#16a34a', Asignada:'#0b5cc7', Dañada:'#dc2626', 'En reparación':'#d97706', Perdida:'#7c3aed' };

    cont.innerHTML = data.map(h => `
      <div style="background:white;border-radius:10px;padding:12px 14px;margin:8px 0;box-shadow:0 1px 4px #0002;border-left:4px solid ${clr[h.estado]||'#6b7280'}">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px">
          <b style="color:#0b3158;font-size:14px">${h.nombre}</b>
          <span style="flex-shrink:0;font-size:11px;background:${clr[h.estado]||'#6b7280'};color:white;padding:2px 8px;border-radius:99px">${h.estado||'—'}</span>
        </div>
        <div style="font-size:12px;color:#6b7280;margin-top:5px">
          <span>🔖 ${h.codigo||'—'}</span>&nbsp;·&nbsp;
          <span>📍 ${h.ubicacion||'—'}</span>&nbsp;·&nbsp;
          <span>👤 ${h.responsable||'—'}</span>
        </div>
        ${(h.cantidad_total||1) > 1 ? `
        <div style="font-size:12px;color:${(h.cantidad_disponible||0)===0?'#dc2626':'#166534'};margin-top:3px">
          📦 Disponible: <b>${h.cantidad_disponible ?? h.cantidad_total} / ${h.cantidad_total}</b>
        </div>` : ''}
        ${h.marca||h.modelo||h.serie ? `
        <div style="font-size:11px;color:#9ca3af;margin-top:3px">
          ${[h.marca,h.modelo,h.serie?'S/N:'+h.serie:''].filter(Boolean).join(' · ')}
        </div>` : ''}
        ${h.fecha_vencimiento ? `
        <div style="font-size:11px;margin-top:4px;color:${_diasParaVencer(h.fecha_vencimiento)<=30?'#d97706':'#6b7280'}">
          📅 Calibración vence: ${h.fecha_vencimiento}${_diasParaVencer(h.fecha_vencimiento)<=30?' ⚠️':''}
        </div>` : ''}
      </div>
    `).join('');

  } catch (e) {
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar: ${e.message}</p>`;
  }
}

function _diasParaVencer(fecha) {
  return Math.ceil((new Date(fecha) - new Date()) / 86400000);
}

// ══════════════════════════════════════════
// SELECTOR COMPARTIDO (entregar / devolver)
// ══════════════════════════════════════════
async function bodegaCargarSelector(selectId, modo) {
  const sel = document.getElementById(selectId);
  if (!sel) return;
  sel.innerHTML = '<option value="">Cargando herramientas...</option>';

  try {
    const { data, error } = await supabaseAYCA
      .from(TABLA_HERR)
      .select('codigo, nombre, estado, ubicacion, responsable, faena, cantidad_total, cantidad_disponible')
      .order('nombre');
    if (error) throw error;

    let lista = data || [];
    if (modo === 'entregar') lista = lista.filter(h => (h.cantidad_disponible ?? 1) > 0);
    if (modo === 'devolver') lista = lista.filter(h => (h.cantidad_total ?? 1) - (h.cantidad_disponible ?? 1) > 0);

    sel.innerHTML = '<option value="">— Seleccione herramienta —</option>';
    lista.forEach(h => {
      const opt = document.createElement('option');
      opt.value = h.codigo;
      const stock = (h.cantidad_total||1) > 1 ? ` — Disp: ${h.cantidad_disponible ?? h.cantidad_total}/${h.cantidad_total}` : '';
      opt.textContent = `${h.nombre}  [${h.codigo}]  — ${h.estado}${stock}`;
      opt.dataset.disponible = h.cantidad_disponible ?? 1;
      opt.dataset.total = h.cantidad_total ?? 1;
      sel.appendChild(opt);
    });
  } catch (e) {
    sel.innerHTML = `<option value="">Error al cargar: ${e.message}</option>`;
  }
}

// ── Helper: muestra "Disponible: X/Y" bajo el select al elegir una herramienta ──
function _bodegaMostrarDisponible(selectId, smallId) {
  const sel = document.getElementById(selectId);
  const small = document.getElementById(smallId);
  if (!sel || !small) return;
  const opt = sel.selectedOptions[0];
  if (!opt || !opt.value) { small.textContent = ''; return; }
  small.textContent = `Disponible: ${opt.dataset.disponible} / ${opt.dataset.total}`;
}

// ══════════════════════════════════════════
// ENTREGAR HERRAMIENTA
// ══════════════════════════════════════════
async function bodegaEntregar() {
  const g        = id => document.getElementById(id)?.value?.trim() || '';
  const codigo   = g('bod_entCodigo');
  const tecnico  = g('bod_entTecnico');
  const faena    = g('bod_entFaena');
  const ubicacion= document.getElementById('bod_entUbicacion')?.value || 'Faena';
  const fecha    = g('bod_entFecha') || new Date().toISOString().slice(0,10);
  const obs      = g('bod_entObs');
  const cantidad = parseInt(g('bod_entCantidad')) || 1;

  if (!codigo) { alert('Selecciona la herramienta a entregar.'); return; }
  if (!tecnico) { alert('Ingresa el nombre del técnico responsable.'); return; }

  try {
    const { data: actual, error: eGet } = await supabaseAYCA
      .from(TABLA_HERR).select('cantidad_total, cantidad_disponible').eq('codigo', codigo).single();
    if (eGet) throw eGet;

    const disponible = actual.cantidad_disponible ?? 1;
    if (cantidad > disponible) {
      alert(`Solo hay ${disponible} unidad${disponible!==1?'es':''} disponible${disponible!==1?'s':''}.`);
      return;
    }

    const nuevaDisponible = disponible - cantidad;
    const nuevoEstado = nuevaDisponible === 0 ? 'Asignada' : 'Disponible';

    const { error: e1 } = await supabaseAYCA
      .from(TABLA_HERR)
      .update({ estado: nuevoEstado, cantidad_disponible: nuevaDisponible, ubicacion, responsable: tecnico, faena })
      .eq('codigo', codigo);
    if (e1) throw e1;

    await supabaseAYCA.from(TABLA_MOV).insert([{
      codigo_herramienta: codigo,
      tipo:        'entrega',
      cantidad,
      tecnico, faena, ubicacion, fecha, observaciones: obs,
      creado_en:   new Date().toISOString()
    }]);

    alert(`✅ ${cantidad} unidad${cantidad!==1?'es':''} entregada${cantidad!==1?'s':''} correctamente.`);
    document.getElementById('bod_entCodigo').value  = '';
    document.getElementById('bod_entTecnico').value = '';
    document.getElementById('bod_entFaena').value   = '';
    document.getElementById('bod_entObs').value     = '';
    const cantEl = document.getElementById('bod_entCantidad');
    if (cantEl) cantEl.value = '1';
    mostrar('bodega');
  } catch (e) {
    alert('❌ Error al registrar entrega: ' + e.message);
    console.error('bodegaEntregar:', e);
  }
}

// ══════════════════════════════════════════
// DEVOLVER HERRAMIENTA
// ══════════════════════════════════════════
async function bodegaDevolver() {
  const g      = id => document.getElementById(id)?.value?.trim() || '';
  const codigo = g('bod_devCodigo');
  const estado = document.getElementById('bod_devEstado')?.value || 'Disponible';
  const fecha  = g('bod_devFecha') || new Date().toISOString().slice(0,10);
  const obs    = g('bod_devObs');
  const cantidad = parseInt(g('bod_devCantidad')) || 1;

  if (!codigo) { alert('Selecciona la herramienta a devolver.'); return; }

  try {
    const { data: actual, error: eGet } = await supabaseAYCA
      .from(TABLA_HERR).select('cantidad_total, cantidad_disponible').eq('codigo', codigo).single();
    if (eGet) throw eGet;

    const total = actual.cantidad_total ?? 1;
    const disponible = actual.cantidad_disponible ?? 1;
    const fuera = total - disponible;
    if (cantidad > fuera) {
      alert(`Solo hay ${fuera} unidad${fuera!==1?'es':''} fuera de bodega.`);
      return;
    }

    const nuevaDisponible = Math.min(disponible + cantidad, total);

    const { error: e1 } = await supabaseAYCA
      .from(TABLA_HERR)
      .update({ estado, cantidad_disponible: nuevaDisponible, ubicacion:'Bodega', responsable:'' })
      .eq('codigo', codigo);
    if (e1) throw e1;

    await supabaseAYCA.from(TABLA_MOV).insert([{
      codigo_herramienta: codigo,
      tipo:        'devolucion',
      cantidad,
      ubicacion:   'Bodega', fecha, observaciones: obs,
      creado_en:   new Date().toISOString()
    }]);

    alert(`✅ ${cantidad} unidad${cantidad!==1?'es':''} devuelta${cantidad!==1?'s':''} a Bodega.`);
    document.getElementById('bod_devCodigo').value = '';
    document.getElementById('bod_devObs').value    = '';
    const cantEl = document.getElementById('bod_devCantidad');
    if (cantEl) cantEl.value = '1';
    mostrar('bodega');
  } catch (e) {
    alert('❌ Error al registrar devolución: ' + e.message);
    console.error('bodegaDevolver:', e);
  }
}

// ══════════════════════════════════════════
// REPORTE
// ══════════════════════════════════════════
async function bodegaCargarReporte() {
  const cont = document.getElementById('bod_reporte');
  if (!cont) return;
  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Generando reporte...</p>';

  try {
    const { data: herr, error } = await supabaseAYCA
      .from(TABLA_HERR).select('*').order('estado');
    if (error) throw error;

    const total = herr?.length || 0;
    const clr   = { Disponible:'#16a34a', Asignada:'#0b5cc7', Dañada:'#dc2626', 'En reparación':'#d97706', Perdida:'#7c3aed' };
    const res   = { Disponible:0, Asignada:0, Dañada:0, 'En reparación':0, Perdida:0 };
    (herr||[]).forEach(h => { if (res[h.estado] !== undefined) res[h.estado]++; });

    const proxVencer = (herr||[]).filter(h => {
      if (!h.fecha_vencimiento) return false;
      const d = _diasParaVencer(h.fecha_vencimiento);
      return d >= 0 && d <= 30;
    }).sort((a,b) => new Date(a.fecha_vencimiento)-new Date(b.fecha_vencimiento));

    const vencidas = (herr||[]).filter(h =>
      h.fecha_vencimiento && _diasParaVencer(h.fecha_vencimiento) < 0
    );

    cont.innerHTML = `
      <div style="background:#0b3158;color:white;border-radius:12px;padding:18px;text-align:center;margin-bottom:14px">
        <div style="font-size:36px;font-weight:bold">${total}</div>
        <div style="font-size:13px;opacity:0.8">Herramientas registradas</div>
      </div>

      <h3 style="color:#0b3158;margin:0 0 8px">Estado del inventario</h3>
      ${Object.entries(res).map(([est,n])=>`
        <div style="display:flex;justify-content:space-between;align-items:center;background:white;padding:10px 16px;border-radius:8px;margin:5px 0;border-left:4px solid ${clr[est]||'#6b7280'}">
          <span style="color:#1f2937;font-weight:bold">${est}</span>
          <span style="font-size:22px;font-weight:bold;color:${clr[est]||'#6b7280'}">${n}</span>
        </div>
      `).join('')}

      ${vencidas.length ? `
      <h3 style="color:#dc2626;margin:16px 0 8px">⛔ Calibración vencida (${vencidas.length})</h3>
      ${vencidas.map(h=>`
        <div style="background:#fef2f2;border:1px solid #fecaca;border-radius:8px;padding:10px;margin:5px 0">
          <b style="color:#dc2626">${h.nombre}</b>
          <div style="font-size:12px;color:#6b7280">${h.codigo} · Venció: ${h.fecha_vencimiento}</div>
        </div>
      `).join('')}` : ''}

      <h3 style="color:#d97706;margin:16px 0 8px">⚠️ Calibraciones próximas a vencer (30 días)</h3>
      ${proxVencer.length
        ? proxVencer.map(h=>{
            const d=_diasParaVencer(h.fecha_vencimiento);
            return `<div style="background:#fffbeb;border:1px solid #fcd34d;border-radius:8px;padding:10px;margin:5px 0">
              <b>${h.nombre}</b> — vence en <b>${d} día${d!==1?'s':''}</b>
              <div style="font-size:12px;color:#6b7280">${h.codigo} · ${h.fecha_vencimiento} · ${h.faena||'—'}</div>
            </div>`;
          }).join('')
        : '<p style="color:#6b7280;font-size:13px;margin:0">Ninguna en los próximos 30 días.</p>'
      }
    `;
  } catch (e) {
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al generar reporte: ${e.message}</p>`;
  }
}

// ══════════════════════════════════════════
// IMPORTAR HERRAMIENTAS DESDE CSV
// ══════════════════════════════════════════

let _bodegaCSVDatos = [];  // filas parseadas del archivo cargado

// ── Generar y descargar plantilla CSV ──
function bodegaDescargarPlantilla() {
  const cab  = 'codigo,nombre,marca,modelo,serie,categoria,estado,ubicacion,cantidad,responsable,faena,fecha_ingreso,fecha_calibracion,fecha_vencimiento,observaciones,foto_url';
  const ej1  = 'HERR-001,Llave de torque 3/4,Stanley,FMHT0-80177,SN-123456,Herramienta de mano,Disponible,Bodega,1,Juan Pérez,Andina,2026-01-15,2026-01-15,2027-01-15,Revisada en mantención,';
  const ej2  = 'HERR-002,Multímetro digital,Fluke,117,FL-98765,Instrumento,Disponible,Bodega,1,,Chuquicamata,2025-06-01,2025-06-01,2026-06-01,,';
  const blob = new Blob([cab + '\n' + ej1 + '\n' + ej2], { type: 'text/csv;charset=utf-8;' });
  const url  = URL.createObjectURL(blob);
  const a    = Object.assign(document.createElement('a'), { href: url, download: 'plantilla_herramientas.csv' });
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// ── Parser CSV robusto: maneja coma/punto y coma, comillas, BOM, CRLF ──
function _parsearCSVTexto(texto) {
  if (texto.charCodeAt(0) === 0xFEFF) texto = texto.slice(1);          // Quitar BOM
  texto = texto.replace(/\r\n/g, '\n').replace(/\r/g, '\n');           // Normalizar saltos

  // Detectar delimitador: si la primera línea tiene más punto y coma que comas → Excel español
  const primeraLinea = texto.split('\n')[0];
  const sep = primeraLinea.split(';').length > primeraLinea.split(',').length ? ';' : ',';

  const filas = [];
  let i = 0, campo = '', fila = [], enComillas = false;

  while (i <= texto.length) {
    const c = texto[i];

    if (enComillas) {
      if (c === '"') {
        if (texto[i + 1] === '"') { campo += '"'; i += 2; continue; }  // comilla escapada ""
        enComillas = false;
      } else {
        campo += (c ?? '');
      }
    } else {
      if      (c === '"')  { enComillas = true; }
      else if (c === sep)  { fila.push(campo.trim()); campo = ''; }
      else if (c === '\n' || c === undefined) {
        fila.push(campo.trim()); campo = '';
        if (fila.some(f => f !== '')) filas.push(fila);
        fila = [];
        if (c === undefined) break;
        i++; continue;
      } else { campo += c; }
    }
    i++;
  }
  return filas;
}

// ── Convertir filas a array de objetos usando la primera fila como cabecera ──
function _csvAObjetos(filas) {
  if (filas.length < 2) return [];
  const cols = filas[0].map(h => h.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, ''));
  return filas.slice(1).map(fila => {
    const obj = {};
    cols.forEach((col, i) => { obj[col] = fila[i] ?? ''; });
    return obj;
  });
}

// ── Vista previa al seleccionar el archivo ──
function bodegaPreviewCSV(event) {
  const archivo = event.target.files[0];
  if (!archivo) return;

  const prev = document.getElementById('bod_impPreview');
  const btn  = document.getElementById('bod_btnImportar');
  const res  = document.getElementById('bod_impResultado');
  if (res)  res.innerHTML  = '';
  if (prev) prev.innerHTML = '<p style="color:#6b7280;padding:8px 0">Leyendo archivo...</p>';
  _bodegaCSVDatos = [];
  if (btn)  { btn.disabled = true; btn.style.opacity = '0.5'; }

  const reader = new FileReader();
  reader.onerror = () => {
    prev.innerHTML = '<p style="color:#dc2626">Error al leer el archivo. Verifica que sea un CSV válido.</p>';
  };
  reader.onload = e => {
    let filas, objs;
    try {
      filas = _parsearCSVTexto(e.target.result);
      objs  = _csvAObjetos(filas);
    } catch (err) {
      prev.innerHTML = `<p style="color:#dc2626">Error al parsear el CSV: ${err.message}</p>`;
      return;
    }

    if (!objs.length) {
      prev.innerHTML = '<p style="color:#dc2626">El archivo está vacío o el formato no es reconocido.</p>';
      return;
    }

    _bodegaCSVDatos = objs;

    const conCodigo  = objs.filter(o => (o.codigo || '').trim()).length;
    const sinCodigo  = objs.length - conCodigo;
    const muestraMax = Math.min(objs.length, 25);
    const COLS_PREV  = ['codigo', 'nombre', 'marca', 'cantidad', 'estado', 'ubicacion', 'faena', 'fecha_vencimiento'];

    prev.innerHTML = `
      <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:10px 14px;margin-bottom:10px;font-size:13px">
        <b style="color:#166534">✅ ${objs.length} fila${objs.length!==1?'s':''} detectada${objs.length!==1?'s':''}</b>
        &nbsp;·&nbsp; ${conCodigo} importable${conCodigo!==1?'s':''}
        ${sinCodigo ? `&nbsp;·&nbsp;<span style="color:#d97706">⚠️ ${sinCodigo} sin código (serán omitidas)</span>` : ''}
        ${objs.length > 25 ? `<br><span style="color:#6b7280;font-size:11px">Vista previa: primeras 25 filas</span>` : ''}
      </div>
      <div style="overflow-x:auto;border-radius:8px;border:1px solid #e2e8f0">
        <table style="font-size:11px;min-width:420px">
          <thead>
            <tr style="background:#0b3158;color:white">
              <th style="padding:6px 10px">#</th>
              ${COLS_PREV.map(c=>`<th style="padding:6px 10px;white-space:nowrap">${c}</th>`).join('')}
            </tr>
          </thead>
          <tbody>
            ${objs.slice(0, muestraMax).map((o, i) => {
              const sinCod = !(o.codigo || '').trim();
              return `<tr style="background:${sinCod?'#fef2f2':i%2?'#f8fafc':'white'}">
                <td style="padding:5px 10px;color:#9ca3af;font-size:10px">${i+2}</td>
                ${COLS_PREV.map(c=>`<td style="padding:5px 10px;max-width:140px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap"
                  title="${String(o[c]||'').replace(/"/g,'&quot;')}">${o[c]||'<span style="color:#d1d5db">—</span>'}</td>`).join('')}
              </tr>`;
            }).join('')}
          </tbody>
        </table>
      </div>`;

    if (conCodigo > 0 && btn) {
      btn.disabled     = false;
      btn.style.opacity = '1';
    }
  };
  reader.readAsText(archivo, 'UTF-8');
}

// ── Ejecutar la importación a Supabase ──
async function bodegaImportar() {
  const btn = document.getElementById('bod_btnImportar');
  const res = document.getElementById('bod_impResultado');

  if (!_bodegaCSVDatos.length) { alert('Primero selecciona un archivo CSV.'); return; }

  // Filtrar filas válidas (deben tener código)
  const validos = _bodegaCSVDatos.filter(o => (o.codigo || '').trim());
  const omitidos = _bodegaCSVDatos.length - validos.length;

  if (!validos.length) { alert('No hay herramientas válidas: todas carecen de código interno.'); return; }

  if (!confirm(
    `¿Importar ${validos.length} herramienta${validos.length!==1?'s':''}?` +
    (omitidos ? `\n(${omitidos} fila${omitidos!==1?'s':''} sin código serán omitidas)` : '') +
    '\n\nCódigos existentes serán actualizados.\nCódigos nuevos serán creados.'
  )) return;

  if (btn) { btn.disabled = true; btn.style.opacity = '0.5'; }
  if (res) res.innerHTML = '<p style="color:#0b5cc7;padding:8px 0">⏳ Iniciando importación...</p>';

  const FECHAS = ['fecha_ingreso', 'fecha_calibracion', 'fecha_vencimiento'];
  const ESTADOS_VALIDOS   = ['Disponible', 'Asignada', 'Dañada', 'En reparación', 'Perdida'];
  const UBICACIONES_VALIDAS = ['Bodega', 'Camión', 'Faena', 'Técnico'];

  // Normalizar cada fila
  const herramientas = validos.map(o => {
    const cantidad = parseInt(o.cantidad) || 1;
    const h = {
      codigo:        (o.codigo        || '').trim(),
      nombre:        (o.nombre        || '').trim(),
      marca:         (o.marca         || '').trim(),
      modelo:        (o.modelo        || '').trim(),
      serie:         (o.serie         || '').trim(),
      categoria:     (o.categoria     || '').trim(),
      estado:        ESTADOS_VALIDOS.find(e => e.toLowerCase() === (o.estado||'').toLowerCase().trim()) || 'Disponible',
      ubicacion:     UBICACIONES_VALIDAS.find(u => u.toLowerCase() === (o.ubicacion||'').toLowerCase().trim()) || 'Bodega',
      cantidad_total:      cantidad,
      cantidad_disponible: cantidad,
      responsable:   (o.responsable   || '').trim(),
      faena:         (o.faena         || '').trim(),
      observaciones: (o.observaciones || '').trim(),
      creado_en:     new Date().toISOString(),
    };
    FECHAS.forEach(f => {
      const v = (o[f] || '').trim();
      h[f] = /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null;
    });
    return h;
  });

  // Upsert en lotes de 50
  const LOTE = 50;
  let ok = 0, errores = [];

  for (let i = 0; i < herramientas.length; i += LOTE) {
    const lote = herramientas.slice(i, i + LOTE);
    const progreso = Math.min(i + LOTE, herramientas.length);
    if (res) res.innerHTML = `
      <div style="background:#eff6ff;border:1px solid #bfdbfe;border-radius:8px;padding:12px 14px;margin-top:12px">
        <p style="color:#1d4ed8;font-size:13px;margin:0">⏳ Procesando ${progreso} / ${herramientas.length}...</p>
        <div style="background:#dbeafe;border-radius:4px;height:6px;margin-top:8px">
          <div style="background:#1d4ed8;border-radius:4px;height:100%;width:${Math.round(progreso/herramientas.length*100)}%;transition:width 0.3s"></div>
        </div>
      </div>`;
    try {
      const { error } = await supabaseAYCA
        .from(TABLA_HERR)
        .upsert(lote, { onConflict: 'codigo' });
      if (error) { errores.push(`Lote ${i/LOTE+1}: ${error.message}`); }
      else { ok += lote.length; }
    } catch (e) {
      errores.push(`Lote ${i/LOTE+1}: ${e.message}`);
    }
  }

  // Resultado final
  const exito = errores.length === 0;
  res.innerHTML = `
    <div style="background:${exito?'#f0fdf4':'#fef3c7'};border:1px solid ${exito?'#86efac':'#fcd34d'};border-radius:10px;padding:16px 18px;margin-top:12px">
      <div style="font-size:17px;font-weight:bold;color:${exito?'#166534':'#92400e'};margin-bottom:10px">
        ${exito ? '✅ Importación completada' : '⚠️ Importación con errores'}
      </div>
      <div style="font-size:13px;color:#374151;display:flex;flex-direction:column;gap:4px">
        <div>✔️ Herramientas guardadas: <b style="font-size:16px;color:#166534">${ok}</b></div>
        ${omitidos ? `<div style="color:#6b7280">⏭️ Filas omitidas (sin código): <b>${omitidos}</b></div>` : ''}
        ${errores.length ? `<div style="color:#dc2626">❌ Lotes con error: <b>${errores.length}</b></div>` : ''}
      </div>
      ${errores.length ? `
        <details style="margin-top:10px">
          <summary style="font-size:12px;color:#dc2626;cursor:pointer">Ver detalle de errores</summary>
          <pre style="font-size:11px;color:#dc2626;white-space:pre-wrap;margin:6px 0 0">${errores.join('\n')}</pre>
        </details>` : ''}
      ${ok > 0 ? `
        <button onclick="irInventario()" class="btn-verde" style="margin-top:12px;width:100%">
          📋 Ver inventario actualizado
        </button>` : ''}
    </div>`;

  if (btn) { btn.disabled = false; btn.style.opacity = '1'; }
  _bodegaCSVDatos = [];
}