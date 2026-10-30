// ===============================
// AYCA SMART MAINTENANCE — PLANIFICADOR.JS
// Pantallas del rol Planificador.
// 1) Mantenciones por planificar — eventos con planificacion_estado =
//    'pendiente'. fn_puede_ver_evento() ya le da a cualquier usuario con
//    rol 'planificador' acceso de lectura a TODOS los eventos (no solo a
//    los que tienen planificador_id = su propio id) — por diseño, así
//    cualquier planificador puede "tomar" una mantención sin asignar.
//    El badge de cada tarjeta distingue "asignada a vos" / "a otro" / "sin
//    asignar", pero no filtra la lista.
// Requiere: supabaseAYCA (database.js), mostrar() (app.js).
// ===============================

let _plaPorPlanCache = [];

// ── Abre la pantalla y dispara la carga ──
async function planificadorIrPorPlanificar() {
  mostrar('planificadorPorPlanificar');
  await planificadorCargarPorPlanificar();
}

// ── Carga eventos pendientes de planificar ──
async function planificadorCargarPorPlanificar() {
  const cont = document.getElementById('plaPorPlan_lista');
  if (!cont) return;
  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando mantenciones por planificar...</p>';

  let userId = null;
  try {
    const { data: userData } = await supabaseAYCA.auth.getUser();
    userId = userData?.user?.id || null;
  } catch (e) {
    // Si falla la verificación de usuario, seguimos igual — solo no vamos
    // a poder distinguir "asignada a vos" de "asignada a otro".
  }

  try {
    const { data, error } = await supabaseAYCA
      .from('eventos_mantencion')
      .select(`
        id, numero, nombre, tipo_evento, criticidad, estado, planificacion_estado,
        planificador_id, fecha_plan_inicio, fecha_plan_termino,
        clientes ( nombre ), faenas ( nombre )
      `)
      .eq('planificacion_estado', 'pendiente')
      .neq('estado', 'cancelado')
      .order('fecha_plan_inicio', { ascending: true, nullsFirst: false });

    if (error) throw error;
    _plaPorPlanCache = (data || []).map(ev => ({ ...ev, _esMio: !!(userId && ev.planificador_id === userId) }));
  } catch (e) {
    console.error('planificadorCargarPorPlanificar:', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar mantenciones: ${e.message}</p>`;
    _plaPorPlanCache = [];
    return;
  }

  if (!_plaPorPlanCache.length) {
    cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">No hay mantenciones pendientes de planificar por ahora.</p>';
    return;
  }

  cont.innerHTML = _plaPorPlanCache.map(_plaPorPlanRenderTarjeta).join('');
}

function _plaFmtFechaCorta(f) {
  if (!f) return '—';
  try { return new Date(f).toLocaleDateString('es-CL'); } catch (e) { return f; }
}

function _plaPorPlanRenderTarjeta(ev) {
  const cliente = ev.clientes?.nombre || '—';
  const faena   = ev.faenas?.nombre || '—';

  let badgeClr, badgeLbl;
  if (ev._esMio)               { badgeClr = '#0b5cc7'; badgeLbl = 'Asignada a vos'; }
  else if (ev.planificador_id) { badgeClr = '#6b7280'; badgeLbl = 'Asignada a otro planificador'; }
  else                         { badgeClr = '#d97706'; badgeLbl = 'Sin planificador asignado'; }

  return `
    <div class="card" style="border-left:4px solid ${badgeClr};padding:12px 14px;margin:6px 0">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:6px;margin-bottom:4px">
        <b style="color:#0b3158;font-size:14px">${ev.nombre || '(sin nombre)'}</b>
        <span style="flex-shrink:0;font-size:10px;background:${badgeClr};color:white;padding:2px 8px;border-radius:99px">${badgeLbl}</span>
      </div>
      <div style="font-size:12px;color:#6b7280;margin-bottom:4px">
        ${ev.numero || ''} · ${cliente} — ${faena} · ${ev.tipo_evento || ''}
      </div>
      <div style="font-size:12px;color:#6b7280">
        Criticidad: ${ev.criticidad || '—'}<br>
        Plan. del evento: ${_plaFmtFechaCorta(ev.fecha_plan_inicio)} → ${_plaFmtFechaCorta(ev.fecha_plan_termino)}
      </div>
    </div>`;
}
