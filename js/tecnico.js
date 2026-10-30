// ===============================
// AYCA SMART MAINTENANCE — TECNICO.JS
// Pantallas del rol Técnico.
// 1) Mis mantenciones asignadas — lista real de eventos donde el técnico
//    tiene una asignación vigente (evento_personal_asignado.usuario_id =
//    el usuario actual, estado_asignacion <> 'liberado'). RLS ya permite
//    esta lectura vía fn_puede_ver_evento() -> fn_es_tecnico_vigente_evento().
// Requiere: supabaseAYCA (database.js), mostrar() (app.js).
// ===============================

let _tecMisMantCache = [];

// ── Abre la pantalla y dispara la carga ──
async function tecnicoIrMisMantenciones() {
  mostrar('tecnicoMisMantenciones');
  await tecnicoCargarMisMantenciones();
}

// ── Carga las asignaciones vigentes del técnico actual con el evento embebido ──
async function tecnicoCargarMisMantenciones() {
  const cont = document.getElementById('tecMisMant_lista');
  if (!cont) return;
  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando tus mantenciones...</p>';

  try {
    const { data: userData, error: userErr } = await supabaseAYCA.auth.getUser();
    if (userErr) throw userErr;
    const user = userData?.user;
    if (!user) throw new Error('Sesión no encontrada.');

    const { data, error } = await supabaseAYCA
      .from('evento_personal_asignado')
      .select(`
        id, estado_asignacion, perfil, especialidad, fecha_desde, fecha_hasta,
        eventos_mantencion (
          id, numero, nombre, tipo_evento, criticidad, estado,
          fecha_plan_inicio, fecha_plan_termino,
          clientes ( nombre ), faenas ( nombre )
        )
      `)
      .eq('usuario_id', user.id)
      .neq('estado_asignacion', 'liberado')
      .order('fecha_desde', { ascending: true, nullsFirst: false });

    if (error) throw error;
    _tecMisMantCache = data || [];
  } catch (e) {
    console.error('tecnicoCargarMisMantenciones:', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar tus mantenciones: ${e.message}</p>`;
    _tecMisMantCache = [];
    return;
  }

  if (!_tecMisMantCache.length) {
    cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">No tienes mantenciones asignadas por ahora.</p>';
    return;
  }

  cont.innerHTML = _tecMisMantCache.map(_tecMisMantRenderTarjeta).join('');
}

function _tecEstadoAsigLabel(estado) {
  return {
    propuesto: 'Propuesto', confirmado: 'Confirmado',
    en_terreno: 'En terreno', liberado: 'Liberado'
  }[estado] || estado;
}

function _tecEstadoAsigColor(estado) {
  return {
    propuesto: '#d97706', confirmado: '#0b5cc7',
    en_terreno: '#16a34a', liberado: '#6b7280'
  }[estado] || '#6b7280';
}

function _tecFmtFechaCorta(f) {
  if (!f) return '—';
  try { return new Date(f).toLocaleDateString('es-CL'); } catch (e) { return f; }
}

function _tecMisMantRenderTarjeta(a) {
  const ev = a.eventos_mantencion || {};
  const clr = _tecEstadoAsigColor(a.estado_asignacion);
  const lbl = _tecEstadoAsigLabel(a.estado_asignacion);
  const cliente = ev.clientes?.nombre || '—';
  const faena   = ev.faenas?.nombre || '—';

  return `
    <div class="card" style="border-left:4px solid ${clr};padding:12px 14px;margin:6px 0">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:6px;margin-bottom:4px">
        <b style="color:#0b3158;font-size:14px">${ev.nombre || '(sin nombre)'}</b>
        <span style="flex-shrink:0;font-size:10px;background:${clr};color:white;padding:2px 8px;border-radius:99px">${lbl}</span>
      </div>
      <div style="font-size:12px;color:#6b7280;margin-bottom:4px">
        ${ev.numero || ''} · ${cliente} — ${faena}
      </div>
      <div style="font-size:12px;color:#6b7280">
        Tu rol: <b>${a.perfil || '—'}</b>${a.especialidad ? ' (' + a.especialidad + ')' : ''}<br>
        Fechas asignación: ${_tecFmtFechaCorta(a.fecha_desde)} → ${_tecFmtFechaCorta(a.fecha_hasta)}<br>
        Plan. del evento: ${_tecFmtFechaCorta(ev.fecha_plan_inicio)} → ${_tecFmtFechaCorta(ev.fecha_plan_termino)}
      </div>
    </div>`;
}

// ── Resumen para la tarjeta clickeable del panel de inicio del técnico (permisos.js) ──
async function tecnicoRenderResumenPanel() {
  const el = document.getElementById('tec_resumenMisMantenciones');
  if (!el) return;
  try {
    const { data: userData } = await supabaseAYCA.auth.getUser();
    const user = userData?.user;
    if (!user) return;

    const { count, error } = await supabaseAYCA
      .from('evento_personal_asignado')
      .select('id', { count: 'exact', head: true })
      .eq('usuario_id', user.id)
      .neq('estado_asignacion', 'liberado');
    if (error) throw error;

    el.textContent = count > 0
      ? `${count} mantención${count === 1 ? '' : 'es'} asignada${count === 1 ? '' : 's'}`
      : 'No tienes mantenciones asignadas.';
  } catch (e) {
    console.warn('tecnicoRenderResumenPanel:', e.message);
  }
}
