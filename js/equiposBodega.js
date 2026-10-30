// ===============================
// AYCA SMART — MÓDULO BODEGA: EQUIPOS (Fase 2)
// ===============================
// Tablas Supabase requeridas (2026-08-02_equipos_bodega_fase2.sql):
//   equipos_bodega (categoria_id/marca_id/ubicacion_id por FK, estado_logistico
//                    y estado_operacional independientes, reserva, calibración)
//   bodega_categorias / bodega_marcas / bodega_ubicaciones (catálogos, Fase 1.2)
//   perfiles_ayca (responsable — no se consulta auth.users directo)
//
// Toda escritura pasa por funciones SECURITY DEFINER: fn_crear_equipo_bodega,
// fn_editar_equipo_bodega, fn_dar_baja_equipo_bodega, fn_reactivar_equipo_bodega,
// fn_reservar_equipo_bodega, fn_liberar_reserva_equipo_bodega. Nunca UPDATE
// directo desde el navegador (la tabla solo tiene GRANT SELECT).
//
// Requiere: supabaseAYCA (database.js), mostrar() (app.js), _diasParaVencer() (bodega.js).

const TABLA_EQB = 'equipos_bodega';

let _eqbEditandoId = null; // null = registrando equipo nuevo; uuid = editando ese equipo

// ══════════════════════════════════════════
// NAVEGACIÓN
// ══════════════════════════════════════════
function irEquiposBodega() {
  mostrar('equiposBodega');
}

function irEquiposRegistrar() {
  _eqbEditandoId = null;
  _eqbLimpiarForm();
  const tit = document.getElementById('eqb_formTitulo');
  if (tit) tit.textContent = '➕ Registrar Equipo';
  const cod = document.getElementById('eqb_codigo');
  if (cod) cod.disabled = false;
  mostrar('equiposBodega-registrar');
  _eqbCargarCatalogosForm();
}

function irEquiposInventario() {
  mostrar('equiposBodega-inventario');
  _eqbCargarCatalogosFiltro();
  eqbCargarInventario();
}

function irEquiposReservar() {
  mostrar('equiposBodega-reservar');
  _eqbCargarSelectorReserva();
  const el = document.getElementById('eqb_resFechaInicio');
  if (el && !el.value) el.valueAsDate = new Date();
}

function _eqbLimpiarForm() {
  ['eqb_codigo','eqb_nombre','eqb_descripcion','eqb_modelo','eqb_serie',
   'eqb_numeroCertificado','eqb_laboratorioCalibracion','eqb_intervaloCalibracion',
   'eqb_fotoUrl','eqb_fechaUltimaCalibracion','eqb_fechaVencimientoCalibracion'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  ['eqb_categoria','eqb_marca','eqb_ubicacion','eqb_responsable'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  const crit = document.getElementById('eqb_criticidad');
  if (crit) crit.value = 'media';
  const chk = document.getElementById('eqb_requiereCalibracion');
  if (chk) chk.checked = false;
}

// ══════════════════════════════════════════
// CATÁLOGOS (categoría / marca / ubicación / responsable)
// ══════════════════════════════════════════
async function _eqbCargarCatalogosForm() {
  const selCat  = document.getElementById('eqb_categoria');
  const selMar  = document.getElementById('eqb_marca');
  const selUbi  = document.getElementById('eqb_ubicacion');
  const selResp = document.getElementById('eqb_responsable');

  try {
    const [{ data: cats, error: e1 }, { data: marcas, error: e2 },
           { data: ubis, error: e3 }, { data: perfiles, error: e4 }] = await Promise.all([
      supabaseAYCA.from('bodega_categorias').select('id, nombre').eq('tipo_recurso', 'equipo').eq('activo', true).order('orden'),
      supabaseAYCA.from('bodega_marcas').select('id, nombre').eq('activo', true).order('nombre'),
      supabaseAYCA.from('bodega_ubicaciones').select('id, nombre').eq('activo', true).order('nombre'),
      supabaseAYCA.from('perfiles_ayca').select('id, nombre').eq('activo', true).order('nombre')
    ]);
    if (e1) throw e1;
    if (e2) throw e2;
    if (e3) throw e3;
    if (e4) throw e4;

    if (selCat) selCat.innerHTML = '<option value="">— Seleccione categoría —</option>' +
      (cats || []).map(c => `<option value="${c.id}">${c.nombre}</option>`).join('');
    if (selMar) selMar.innerHTML = '<option value="">— Sin marca —</option>' +
      (marcas || []).map(m => `<option value="${m.id}">${m.nombre}</option>`).join('');
    if (selUbi) selUbi.innerHTML = '<option value="">— Seleccione ubicación —</option>' +
      (ubis || []).map(u => `<option value="${u.id}">${u.nombre}</option>`).join('');
    if (selResp) selResp.innerHTML = '<option value="">— Sin responsable —</option>' +
      (perfiles || []).map(p => `<option value="${p.id}">${p.nombre}</option>`).join('');
  } catch (e) {
    console.error('_eqbCargarCatalogosForm:', e);
    alert('❌ Error al cargar categoría/marca/ubicación/responsable: ' + e.message);
  }
}

async function _eqbCargarCatalogosFiltro() {
  const selCat = document.getElementById('eqb_filtroCategoria');
  const selUbi = document.getElementById('eqb_filtroUbicacion');

  try {
    const [{ data: cats, error: e1 }, { data: ubis, error: e2 }] = await Promise.all([
      supabaseAYCA.from('bodega_categorias').select('id, nombre').eq('tipo_recurso', 'equipo').eq('activo', true).order('orden'),
      supabaseAYCA.from('bodega_ubicaciones').select('id, nombre').eq('activo', true).order('nombre')
    ]);
    if (e1) throw e1;
    if (e2) throw e2;

    if (selCat) selCat.innerHTML = '<option value="">Todas las categorías</option>' +
      (cats || []).map(c => `<option value="${c.id}">${c.nombre}</option>`).join('');
    if (selUbi) selUbi.innerHTML = '<option value="">Todas las ubicaciones</option>' +
      (ubis || []).map(u => `<option value="${u.id}">${u.nombre}</option>`).join('');
  } catch (e) {
    console.error('_eqbCargarCatalogosFiltro:', e);
  }
}

// ══════════════════════════════════════════
// REGISTRAR / EDITAR EQUIPO
// ══════════════════════════════════════════
async function eqbGuardar() {
  const g = id => document.getElementById(id)?.value?.trim() || '';
  const codigo      = g('eqb_codigo');
  const nombre      = g('eqb_nombre');
  const categoriaId = g('eqb_categoria');
  const ubicacionId = g('eqb_ubicacion');

  if (!_eqbEditandoId && !codigo) { alert('El código interno es obligatorio.'); return; }
  if (!nombre)      { alert('El nombre es obligatorio.'); return; }
  if (!categoriaId) { alert('Selecciona una categoría.'); return; }
  if (!ubicacionId) { alert('Selecciona una ubicación.'); return; }

  const intervalo = g('eqb_intervaloCalibracion');

  const params = {
    p_nombre:                         nombre,
    p_categoria_id:                   categoriaId,
    p_ubicacion_id:                   ubicacionId,
    p_marca_id:                       g('eqb_marca') || null,
    p_descripcion:                    g('eqb_descripcion') || null,
    p_modelo:                         g('eqb_modelo') || null,
    p_serie:                          g('eqb_serie') || null,
    p_responsable_id:                 g('eqb_responsable') || null,
    p_criticidad:                     document.getElementById('eqb_criticidad')?.value || 'media',
    p_requiere_calibracion:           !!document.getElementById('eqb_requiereCalibracion')?.checked,
    p_fecha_ultima_calibracion:       g('eqb_fechaUltimaCalibracion') || null,
    p_fecha_vencimiento_calibracion:  g('eqb_fechaVencimientoCalibracion') || null,
    p_numero_certificado:             g('eqb_numeroCertificado') || null,
    p_laboratorio_calibracion:        g('eqb_laboratorioCalibracion') || null,
    p_intervalo_calibracion_meses:    intervalo ? parseInt(intervalo, 10) : null,
    p_foto_principal_url:             g('eqb_fotoUrl') || null
  };

  try {
    if (_eqbEditandoId) {
      const { error } = await supabaseAYCA.rpc('fn_editar_equipo_bodega', { p_id: _eqbEditandoId, ...params });
      if (error) throw error;
      alert(`✅ Equipo "${nombre}" actualizado correctamente.`);
    } else {
      const { error } = await supabaseAYCA.rpc('fn_crear_equipo_bodega', { p_codigo: codigo, ...params });
      if (error) throw error;
      alert(`✅ Equipo "${nombre}" registrado correctamente.\nCódigo: ${codigo}`);
    }
    _eqbEditandoId = null;
    mostrar('equiposBodega');
  } catch (e) {
    alert('❌ Error al guardar: ' + e.message);
    console.error('eqbGuardar:', e);
  }
}

async function eqbEditar(id) {
  try {
    const { data, error } = await supabaseAYCA.from(TABLA_EQB).select('*').eq('id', id).single();
    if (error) throw error;

    _eqbEditandoId = id;
    mostrar('equiposBodega-registrar');
    const tit = document.getElementById('eqb_formTitulo');
    if (tit) tit.textContent = '✏️ Editar Equipo';

    await _eqbCargarCatalogosForm();

    const s = (elId, v) => { const el = document.getElementById(elId); if (el) el.value = v ?? ''; };
    s('eqb_codigo', data.codigo);
    const cod = document.getElementById('eqb_codigo');
    if (cod) cod.disabled = true;
    s('eqb_nombre', data.nombre);
    s('eqb_descripcion', data.descripcion);
    s('eqb_modelo', data.modelo);
    s('eqb_serie', data.serie);
    s('eqb_categoria', data.categoria_id);
    s('eqb_marca', data.marca_id);
    s('eqb_ubicacion', data.ubicacion_id);
    s('eqb_responsable', data.responsable_id);
    s('eqb_criticidad', data.criticidad || 'media');
    const chk = document.getElementById('eqb_requiereCalibracion');
    if (chk) chk.checked = !!data.requiere_calibracion;
    s('eqb_fechaUltimaCalibracion', data.fecha_ultima_calibracion);
    s('eqb_fechaVencimientoCalibracion', data.fecha_vencimiento_calibracion);
    s('eqb_numeroCertificado', data.numero_certificado);
    s('eqb_laboratorioCalibracion', data.laboratorio_calibracion);
    s('eqb_intervaloCalibracion', data.intervalo_calibracion_meses);
    s('eqb_fotoUrl', data.foto_principal_url);
  } catch (e) {
    alert('❌ Error al cargar el equipo: ' + e.message);
    console.error('eqbEditar:', e);
  }
}

// ══════════════════════════════════════════
// INVENTARIO
// ══════════════════════════════════════════
const _EQB_CLR_LOG  = { disponible:'#16a34a', asignado:'#0b5cc7', reservado:'#d97706', extraviado:'#7c3aed', baja:'#6b7280' };
const _EQB_LBL_LOG  = { disponible:'Disponible', asignado:'Asignado', reservado:'Reservado', extraviado:'Extraviado', baja:'Baja' };
const _EQB_LBL_OP   = { operativo:'Operativo', defectuoso:'Defectuoso', en_reparacion:'En reparación', obsoleto:'Obsoleto' };
const _EQB_LBL_CRIT = { alta:'Alta', media:'Media', baja:'Baja' };
const _EQB_CLR_CRIT = { alta:'#dc2626', media:'#d97706', baja:'#16a34a' };

async function eqbCargarInventario() {
  const cont = document.getElementById('eqb_listaInventario');
  if (!cont) return;
  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando inventario...</p>';

  try {
    const fCat    = document.getElementById('eqb_filtroCategoria')?.value || '';
    const fUbi    = document.getElementById('eqb_filtroUbicacion')?.value || '';
    const fEstLog = document.getElementById('eqb_filtroEstadoLog')?.value || '';
    const fEstOp  = document.getElementById('eqb_filtroEstadoOp')?.value || '';
    const fCrit   = document.getElementById('eqb_filtroCriticidad')?.value || '';

    let query = supabaseAYCA
      .from(TABLA_EQB)
      .select('*, categoria:bodega_categorias(nombre), marca:bodega_marcas(nombre), ubicacion:bodega_ubicaciones(nombre)')
      .order('nombre');
    if (fCat)    query = query.eq('categoria_id', fCat);
    if (fUbi)    query = query.eq('ubicacion_id', fUbi);
    if (fEstLog) query = query.eq('estado_logistico', fEstLog);
    if (fEstOp)  query = query.eq('estado_operacional', fEstOp);
    if (fCrit)   query = query.eq('criticidad', fCrit);

    const { data, error } = await query;
    if (error) throw error;

    if (!data || data.length === 0) {
      cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">No hay equipos registrados.</p>';
      return;
    }

    cont.innerHTML = data.map(_eqbRenderTarjeta).join('');
  } catch (e) {
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar: ${e.message}</p>`;
  }
}

function _eqbRenderTarjeta(eq) {
  const clrLog = _EQB_CLR_LOG[eq.estado_logistico] || '#6b7280';
  const lblLog = _EQB_LBL_LOG[eq.estado_logistico] || eq.estado_logistico || '—';

  // "baja" solo permite reactivar; el resto puede editarse y darse de baja
  // (además de liberar reserva, si corresponde).
  let acciones;
  if (eq.estado_logistico === 'baja') {
    acciones = `<button class="btn-verde" style="font-size:12px;padding:6px 10px" onclick="eqbReactivar('${eq.id}')">🔄 Reactivar</button>`;
  } else {
    acciones = `<button class="btn-gris" style="font-size:12px;padding:6px 10px" onclick="eqbEditar('${eq.id}')">✏️ Editar</button>`;
    if (eq.estado_logistico === 'reservado') {
      acciones += ` <button class="btn-gris" style="font-size:12px;padding:6px 10px" onclick="eqbLiberarReserva('${eq.id}')">🔓 Liberar reserva</button>`;
    }
    acciones += ` <button class="btn-rojo" style="font-size:12px;padding:6px 10px" onclick="eqbDarBaja('${eq.id}')">🗑️ Dar de baja</button>`;
  }

  return `
    <div style="background:white;border-radius:10px;padding:12px 14px;margin:8px 0;box-shadow:0 1px 4px #0002;border-left:4px solid ${clrLog}">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px">
        <b style="color:#0b3158;font-size:14px">${eq.nombre}</b>
        <span style="flex-shrink:0;font-size:11px;background:${clrLog};color:white;padding:2px 8px;border-radius:99px">${lblLog}</span>
      </div>
      <div style="font-size:12px;color:#6b7280;margin-top:5px">
        <span>🔖 ${eq.codigo || '—'}</span>&nbsp;·&nbsp;
        <span>📂 ${eq.categoria?.nombre || '—'}</span>&nbsp;·&nbsp;
        <span>📍 ${eq.ubicacion?.nombre || '—'}</span>
      </div>
      ${eq.marca?.nombre || eq.modelo || eq.serie ? `
      <div style="font-size:11px;color:#9ca3af;margin-top:3px">
        ${[eq.marca?.nombre, eq.modelo, eq.serie ? 'S/N:' + eq.serie : ''].filter(Boolean).join(' · ')}
      </div>` : ''}
      <div style="font-size:11px;margin-top:4px;color:#6b7280">
        ⚙️ ${_EQB_LBL_OP[eq.estado_operacional] || eq.estado_operacional || '—'}
        &nbsp;·&nbsp;
        <span style="color:${_EQB_CLR_CRIT[eq.criticidad] || '#6b7280'}">● Criticidad ${_EQB_LBL_CRIT[eq.criticidad] || eq.criticidad || '—'}</span>
      </div>
      ${eq.estado_logistico === 'reservado' ? `
      <div style="font-size:11px;margin-top:4px;color:#d97706">
        🔒 Reservado para: ${eq.reservado_para || '—'} (${eq.fecha_reserva || '—'}${eq.fecha_fin_reserva ? ' → ' + eq.fecha_fin_reserva : ''})
      </div>` : ''}
      ${eq.requiere_calibracion && eq.fecha_vencimiento_calibracion ? `
      <div style="font-size:11px;margin-top:4px;color:${_diasParaVencer(eq.fecha_vencimiento_calibracion) <= 30 ? '#d97706' : '#6b7280'}">
        📅 Calibración vence: ${eq.fecha_vencimiento_calibracion}${_diasParaVencer(eq.fecha_vencimiento_calibracion) <= 30 ? ' ⚠️' : ''}
      </div>` : ''}
      <div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap">${acciones}</div>
    </div>`;
}

// ══════════════════════════════════════════
// RESERVAR / LIBERAR RESERVA / BAJA / REACTIVAR
// ══════════════════════════════════════════
async function _eqbCargarSelectorReserva() {
  const sel = document.getElementById('eqb_resCodigo');
  if (!sel) return;
  sel.innerHTML = '<option value="">Cargando equipos...</option>';

  try {
    const { data, error } = await supabaseAYCA
      .from(TABLA_EQB)
      .select('id, codigo, nombre')
      .eq('estado_logistico', 'disponible')
      .order('nombre');
    if (error) throw error;

    sel.innerHTML = '<option value="">— Seleccione equipo —</option>';
    (data || []).forEach(eq => {
      const opt = document.createElement('option');
      opt.value = eq.id;
      opt.textContent = `${eq.nombre}  [${eq.codigo}]`;
      sel.appendChild(opt);
    });
  } catch (e) {
    sel.innerHTML = `<option value="">Error al cargar: ${e.message}</option>`;
  }
}

async function eqbReservar() {
  const id          = document.getElementById('eqb_resCodigo')?.value || '';
  const g           = elId => document.getElementById(elId)?.value?.trim() || '';
  const para        = g('eqb_resPara');
  const fechaInicio = g('eqb_resFechaInicio');
  const fechaFin    = g('eqb_resFechaFin') || null;

  if (!id)          { alert('Selecciona el equipo a reservar.'); return; }
  if (!para)        { alert('Indica para quién o qué se reserva el equipo.'); return; }
  if (!fechaInicio) { alert('Indica la fecha de inicio de la reserva.'); return; }

  try {
    const { error } = await supabaseAYCA.rpc('fn_reservar_equipo_bodega', {
      p_id: id, p_reservado_para: para, p_fecha_reserva: fechaInicio, p_fecha_fin_reserva: fechaFin
    });
    if (error) throw error;

    alert('✅ Equipo reservado correctamente.');
    document.getElementById('eqb_resPara').value     = '';
    document.getElementById('eqb_resFechaFin').value = '';
    mostrar('equiposBodega');
  } catch (e) {
    alert('❌ Error al reservar: ' + e.message);
    console.error('eqbReservar:', e);
  }
}

async function eqbLiberarReserva(id) {
  if (!confirm('¿Confirmas liberar la reserva de este equipo? Volverá a estado "disponible".')) return;
  try {
    const { error } = await supabaseAYCA.rpc('fn_liberar_reserva_equipo_bodega', { p_id: id });
    if (error) throw error;
    alert('✅ Reserva liberada.');
    eqbCargarInventario();
  } catch (e) {
    alert('❌ Error al liberar la reserva: ' + e.message);
    console.error('eqbLiberarReserva:', e);
  }
}

async function eqbDarBaja(id) {
  const motivo = prompt('Motivo de la baja (opcional). Cancelar para no continuar:', '');
  if (motivo === null) return;

  try {
    const { error } = await supabaseAYCA.rpc('fn_dar_baja_equipo_bodega', { p_id: id, p_motivo: motivo || null });
    if (error) throw error;
    alert('✅ Equipo dado de baja.');
    eqbCargarInventario();
  } catch (e) {
    alert('❌ Error al dar de baja: ' + e.message);
    console.error('eqbDarBaja:', e);
  }
}

async function eqbReactivar(id) {
  if (!confirm('¿Confirmas reactivar este equipo? Volverá a estado "disponible".')) return;
  try {
    const { error } = await supabaseAYCA.rpc('fn_reactivar_equipo_bodega', { p_id: id });
    if (error) throw error;
    alert('✅ Equipo reactivado.');
    eqbCargarInventario();
  } catch (e) {
    alert('❌ Error al reactivar: ' + e.message);
    console.error('eqbReactivar:', e);
  }
}

// ══════════════════════════════════════════
// IMPORTAR EQUIPOS DESDE CSV
// ══════════════════════════════════════════
// Reutiliza _parsearCSVTexto() y _csvAObjetos(), ya definidos en bodega.js.

let _eqbCSVDatos = [];       // filas parseadas del archivo
let _eqbCatMap = {};         // { 'lower(nombre)': id } — solo tipo_recurso='equipo'
let _eqbMarcaMap = {};       // { 'lower(nombre)': id }
let _eqbUbiMap = {};         // { 'lower(codigo o nombre)': id }

function irEquiposImportar() {
  mostrar('equiposBodega-importar');
  _eqbCSVDatos = [];
  const prev = document.getElementById('eqb_impPreview');
  const res  = document.getElementById('eqb_impResultado');
  const btn  = document.getElementById('eqb_btnImportar');
  const inp  = document.getElementById('eqb_impArchivo');
  if (prev) prev.innerHTML = '';
  if (res)  res.innerHTML  = '';
  if (inp)  inp.value      = '';
  if (btn)  { btn.disabled = true; btn.style.opacity = '0.5'; }
}

function eqbDescargarPlantilla() {
  const cab = 'codigo,nombre,descripcion,modelo,serie,categoria,marca,ubicacion,responsable,criticidad,requiere_calibracion,fecha_ultima_calibracion,fecha_vencimiento_calibracion,numero_certificado,laboratorio_calibracion,intervalo_calibracion_meses,foto_principal_url';
  const ej1 = 'EQ-001,Motor eléctrico 500HP,Motor principal molino,WEG-500HP-4P,SN-778899,Eléctrico,SKF,Bodega Central,,alta,si,2026-01-15,2027-01-15,CERT-2026-001,Labcal SPA,12,';
  const ej2 = 'EQ-002,Ventilador industrial,,V-200,SN-112233,Mecánico,,Laboratorio,,media,no,,,,,';
  const blob = new Blob([cab + '\n' + ej1 + '\n' + ej2], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = Object.assign(document.createElement('a'), { href: url, download: 'plantilla_equipos.csv' });
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

async function _eqbCargarMapasCatalogo() {
  const [{ data: cats, error: e1 }, { data: marcas, error: e2 }, { data: ubis, error: e3 }] = await Promise.all([
    supabaseAYCA.from('bodega_categorias').select('id,nombre').eq('tipo_recurso','equipo').eq('activo', true),
    supabaseAYCA.from('bodega_marcas').select('id,nombre').eq('activo', true),
    supabaseAYCA.from('bodega_ubicaciones').select('id,codigo,nombre').eq('activo', true)
  ]);
  if (e1 || e2 || e3) throw (e1 || e2 || e3);

  _eqbCatMap = {}; (cats || []).forEach(c => { _eqbCatMap[c.nombre.toLowerCase().trim()] = c.id; });
  _eqbMarcaMap = {}; (marcas || []).forEach(m => { _eqbMarcaMap[m.nombre.toLowerCase().trim()] = m.id; });
  _eqbUbiMap = {};
  (ubis || []).forEach(u => {
    _eqbUbiMap[u.codigo.toLowerCase().trim()] = u.id;
    _eqbUbiMap[u.nombre.toLowerCase().trim()] = u.id;
  });
}

function eqbPreviewCSV(event) {
  const archivo = event.target.files[0];
  if (!archivo) return;

  const prev = document.getElementById('eqb_impPreview');
  const btn  = document.getElementById('eqb_btnImportar');
  const res  = document.getElementById('eqb_impResultado');
  if (res)  res.innerHTML  = '';
  if (prev) prev.innerHTML = '<p style="color:#6b7280;padding:8px 0">Leyendo archivo...</p>';
  _eqbCSVDatos = [];
  if (btn)  { btn.disabled = true; btn.style.opacity = '0.5'; }

  const reader = new FileReader();
  reader.onerror = () => { prev.innerHTML = '<p style="color:#dc2626">Error al leer el archivo.</p>'; };
  reader.onload = async e => {
    let filas, objs;
    try {
      filas = _parsearCSVTexto(e.target.result);   // definida en bodega.js
      objs  = _csvAObjetos(filas);                 // definida en bodega.js
    } catch (err) {
      prev.innerHTML = `<p style="color:#dc2626">Error al parsear el CSV: ${err.message}</p>`;
      return;
    }
    if (!objs.length) {
      prev.innerHTML = '<p style="color:#dc2626">El archivo está vacío o el formato no es reconocido.</p>';
      return;
    }

    try {
      await _eqbCargarMapasCatalogo();
    } catch (err) {
      prev.innerHTML = `<p style="color:#dc2626">Error al cargar los catálogos: ${err.message}</p>`;
      return;
    }

    objs.forEach(o => {
      o._errores = [];
      if (!(o.codigo || '').trim())  o._errores.push('sin código');
      if (!(o.nombre || '').trim())  o._errores.push('sin nombre');

      const catKey = (o.categoria || '').toLowerCase().trim();
      if (!catKey) o._errores.push('sin categoría');
      else if (!_eqbCatMap[catKey]) o._errores.push(`categoría "${o.categoria}" no existe en el catálogo`);

      const ubiKey = (o.ubicacion || '').toLowerCase().trim();
      if (!ubiKey) o._errores.push('sin ubicación');
      else if (!_eqbUbiMap[ubiKey]) o._errores.push(`ubicación "${o.ubicacion}" no existe en el catálogo`);

      o._marcaNueva = !!(o.marca || '').trim() && !_eqbMarcaMap[(o.marca || '').toLowerCase().trim()];
    });

    _eqbCSVDatos = objs;

    const validos = objs.filter(o => o._errores.length === 0);
    const conError = objs.length - validos.length;
    const marcasNuevas = [...new Set(objs.filter(o => o._marcaNueva).map(o => o.marca))];
    const muestraMax = Math.min(objs.length, 25);
    const COLS_PREV = ['codigo','nombre','categoria','marca','ubicacion','criticidad'];

    prev.innerHTML = `
      <div style="background:${conError ? '#fffbeb' : '#f0fdf4'};border:1px solid ${conError ? '#fcd34d' : '#bbf7d0'};border-radius:8px;padding:10px 14px;margin-bottom:10px;font-size:13px">
        <b style="color:${conError ? '#92400e' : '#166534'}">${validos.length} de ${objs.length} fila${objs.length !== 1 ? 's' : ''} lista${validos.length !== 1 ? 's' : ''} para importar</b>
        ${conError ? `<br><span style="color:#dc2626">⚠️ ${conError} fila${conError !== 1 ? 's' : ''} con error (no se importarán)</span>` : ''}
        ${marcasNuevas.length ? `<br><span style="color:#1d4ed8">ℹ️ Se creará${marcasNuevas.length !== 1 ? 'n' : ''} en el catálogo: ${marcasNuevas.join(', ')}</span>` : ''}
        ${objs.length > 25 ? `<br><span style="color:#6b7280;font-size:11px">Vista previa: primeras 25 filas</span>` : ''}
      </div>
      <div style="overflow-x:auto;border-radius:8px;border:1px solid #e2e8f0">
        <table style="font-size:11px;min-width:420px">
          <thead>
            <tr style="background:#0b3158;color:white">
              <th style="padding:6px 10px">#</th>
              ${COLS_PREV.map(c => `<th style="padding:6px 10px;white-space:nowrap">${c}</th>`).join('')}
              <th style="padding:6px 10px">Estado</th>
            </tr>
          </thead>
          <tbody>
            ${objs.slice(0, muestraMax).map((o, i) => `
              <tr style="background:${o._errores.length ? '#fef2f2' : (i % 2 ? '#f8fafc' : 'white')}">
                <td style="padding:5px 10px;color:#9ca3af;font-size:10px">${i + 2}</td>
                ${COLS_PREV.map(c => `<td style="padding:5px 10px;max-width:140px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${o[c] || '<span style="color:#d1d5db">—</span>'}</td>`).join('')}
                <td style="padding:5px 10px;color:${o._errores.length ? '#dc2626' : '#16a34a'};font-size:10px">${o._errores.length ? o._errores.join('; ') : '✅ OK'}</td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>`;

    if (validos.length > 0 && btn) { btn.disabled = false; btn.style.opacity = '1'; }
  };
  reader.readAsText(archivo, 'UTF-8');
}

async function eqbImportarCSV() {
  const btn = document.getElementById('eqb_btnImportar');
  const res = document.getElementById('eqb_impResultado');

  const validos = _eqbCSVDatos.filter(o => o._errores.length === 0);
  const conError = _eqbCSVDatos.length - validos.length;
  if (!validos.length) { alert('No hay filas válidas para importar.'); return; }

  if (!confirm(
    `¿Importar ${validos.length} equipo${validos.length !== 1 ? 's' : ''}?` +
    (conError ? `\n(${conError} fila${conError !== 1 ? 's' : ''} con error serán omitidas)` : '') +
    '\n\nCódigos existentes serán actualizados. Códigos nuevos serán creados.'
  )) return;

  if (btn) { btn.disabled = true; btn.style.opacity = '0.5'; }

  let ok = 0, actualizados = 0, creados = 0, errores = [];

  for (let i = 0; i < validos.length; i++) {
    const o = validos[i];
    if (res) res.innerHTML = `
      <div style="background:#eff6ff;border:1px solid #bfdbfe;border-radius:8px;padding:12px 14px;margin-top:12px">
        <p style="color:#1d4ed8;font-size:13px;margin:0">⏳ Procesando ${i + 1} / ${validos.length}...</p>
        <div style="background:#dbeafe;border-radius:4px;height:6px;margin-top:8px">
          <div style="background:#1d4ed8;border-radius:4px;height:100%;width:${Math.round((i + 1) / validos.length * 100)}%;transition:width 0.3s"></div>
        </div>
      </div>`;

    try {
      let marcaId = null;
      const marcaTexto = (o.marca || '').trim();
      if (marcaTexto) {
        const key = marcaTexto.toLowerCase();
        marcaId = _eqbMarcaMap[key] || null;
        if (!marcaId) {
          const { data: nueva, error: eMarca } = await supabaseAYCA
            .from('bodega_marcas').insert({ nombre: marcaTexto }).select('id').single();
          if (eMarca) throw new Error('marca: ' + eMarca.message);
          marcaId = nueva.id;
          _eqbMarcaMap[key] = marcaId;
        }
      }

      const params = {
        p_nombre: o.nombre.trim(),
        p_categoria_id: _eqbCatMap[o.categoria.toLowerCase().trim()],
        p_ubicacion_id: _eqbUbiMap[o.ubicacion.toLowerCase().trim()],
        p_marca_id: marcaId,
        p_descripcion: (o.descripcion || '').trim() || null,
        p_modelo: (o.modelo || '').trim() || null,
        p_serie: (o.serie || '').trim() || null,
        p_responsable_id: null,
        p_criticidad: ['alta','media','baja'].includes((o.criticidad || '').toLowerCase().trim()) ? o.criticidad.toLowerCase().trim() : 'media',
        p_requiere_calibracion: ['si','sí','true','1','yes'].includes((o.requiere_calibracion || '').toLowerCase().trim()),
        p_fecha_ultima_calibracion: /^\d{4}-\d{2}-\d{2}$/.test((o.fecha_ultima_calibracion || '').trim()) ? o.fecha_ultima_calibracion.trim() : null,
        p_fecha_vencimiento_calibracion: /^\d{4}-\d{2}-\d{2}$/.test((o.fecha_vencimiento_calibracion || '').trim()) ? o.fecha_vencimiento_calibracion.trim() : null,
        p_numero_certificado: (o.numero_certificado || '').trim() || null,
        p_laboratorio_calibracion: (o.laboratorio_calibracion || '').trim() || null,
        p_intervalo_calibracion_meses: (o.intervalo_calibracion_meses || '').trim() ? Number(o.intervalo_calibracion_meses.trim()) : null,
        p_foto_principal_url: (o.foto_principal_url || '').trim() || null
      };

      const { data: existente } = await supabaseAYCA
        .from('equipos_bodega').select('id').ilike('codigo', o.codigo.trim()).maybeSingle();

      if (existente) {
        const { error } = await supabaseAYCA.rpc('fn_editar_equipo_bodega', { p_id: existente.id, ...params });
        if (error) throw error;
        actualizados++;
      } else {
        const { error } = await supabaseAYCA.rpc('fn_crear_equipo_bodega', { p_codigo: o.codigo.trim(), ...params });
        if (error) throw error;
        creados++;
      }
      ok++;
    } catch (e) {
      errores.push(`Fila ${i + 2} (${o.codigo || '—'}): ${e.message}`);
    }
  }

  const exito = errores.length === 0;
  res.innerHTML = `
    <div style="background:${exito ? '#f0fdf4' : '#fef3c7'};border:1px solid ${exito ? '#86efac' : '#fcd34d'};border-radius:10px;padding:16px 18px;margin-top:12px">
      <div style="font-size:17px;font-weight:bold;color:${exito ? '#166534' : '#92400e'};margin-bottom:10px">
        ${exito ? '✅ Importación completada' : '⚠️ Importación con errores'}
      </div>
      <div style="font-size:13px;color:#374151;display:flex;flex-direction:column;gap:4px">
        <div>✔️ Equipos creados: <b style="color:#166534">${creados}</b></div>
        <div>♻️ Equipos actualizados: <b style="color:#1d4ed8">${actualizados}</b></div>
        ${conError ? `<div style="color:#6b7280">⏭️ Filas omitidas (errores de validación): <b>${conError}</b></div>` : ''}
        ${errores.length ? `<div style="color:#dc2626">❌ Filas con error al guardar: <b>${errores.length}</b></div>` : ''}
      </div>
      ${errores.length ? `
        <details style="margin-top:10px">
          <summary style="font-size:12px;color:#dc2626;cursor:pointer">Ver detalle de errores</summary>
          <pre style="font-size:11px;color:#dc2626;white-space:pre-wrap;margin:6px 0 0">${errores.join('\n')}</pre>
        </details>` : ''}
      ${ok > 0 ? `
        <button onclick="irEquiposInventario()" class="btn-verde" style="margin-top:12px;width:100%">
          📋 Ver inventario actualizado
        </button>` : ''}
    </div>`;

  if (btn) { btn.disabled = false; btn.style.opacity = '1'; }
  _eqbCSVDatos = [];
}
