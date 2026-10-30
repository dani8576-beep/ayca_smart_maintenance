// ===============================
// AYCA SMART MAINTENANCE — EVENTOS.JS
// Módulo de Eventos de Mantención (FASE 3.1)
// Requiere: supabaseAYCA (database.js).
// Tablas Supabase: eventos_mantencion (lectura directa, sujeta a RLS),
//                  faenas (embebida por FK para mostrar el nombre),
//                  mantenciones (conteo de equipos por evento).
// ===============================

const EVENTOS_ESTADO_COLOR = {
  borrador:     '#6b7280',
  planificado:  '#0b5cc7',
  en_ejecucion: '#d97706',
  finalizado:   '#16a34a',
  cancelado:    '#dc2626'
};

const EVENTOS_ESTADO_LABEL = {
  borrador:     'Borrador',
  planificado:  'Planificado',
  en_ejecucion: 'En ejecución',
  finalizado:   'Finalizado',
  cancelado:    'Cancelado'
};

// Vocabulario compartido por ejecucion_estado / revision_estado / personal_estado /
// recursos_estado (2026-07-18_mantenciones_etapa2d_01, CHECK de cada columna).
const EVENTOS_SUBESTADO_COLOR = {
  sin_equipos:  '#6b7280',
  pendiente:    '#6b7280',
  en_ejecucion: '#d97706',
  en_revision:  '#d97706',
  parcial:      '#0b5cc7',
  completado:   '#16a34a',
  aprobado:     '#16a34a',
  no_aplica:    '#9ca3af'
};

const EVENTOS_SUBESTADO_LABEL = {
  sin_equipos:  'Sin equipos',
  pendiente:    'Pendiente',
  en_ejecucion: 'En ejecución',
  en_revision:  'En revisión',
  parcial:      'Parcial',
  completado:   'Completado',
  aprobado:     'Aprobado',
  no_aplica:    'No aplica'
};

// ── Cargar y renderizar la lista de eventos de mantención (solo lectura) ──
async function eventosCargarLista() {
  const cont = document.getElementById('eventosListaCont');
  if (!cont) return;
  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando eventos...</p>';

  let eventos;
  try {
    const { data, error } = await supabaseAYCA
      .from('eventos_mantencion')
      .select('id, numero, codigo, nombre, estado, fecha_plan_inicio, faenas(nombre)')
      .order('creado_en', { ascending: false });

    if (error) throw error;
    eventos = data || [];
  } catch (e) {
    console.error('eventosCargarLista:', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar eventos: ${e.message}</p>`;
    return;
  }

  if (!eventos.length) {
    cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Sin eventos registrados.</p>';
    return;
  }

  const conteoEquipos = await _eventosContarEquipos(eventos.map(ev => ev.id));

  cont.innerHTML = eventos.map(ev => {
    const clr = EVENTOS_ESTADO_COLOR[ev.estado] || '#6b7280';
    const lbl = EVENTOS_ESTADO_LABEL[ev.estado] || ev.estado || '—';
    const nEquipos = conteoEquipos[ev.id]?.activos ?? 0;
    const faenaNombre = ev.faenas?.nombre || '—';
    const fechaInicio = ev.fecha_plan_inicio ? String(ev.fecha_plan_inicio).slice(0, 10) : '—';

    return `
      <div class="card" style="border-left:4px solid ${clr};padding:12px 14px;margin:6px 0;cursor:pointer"
           onclick="eventosAbrirDetalle('${ev.id}')">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:6px;margin-bottom:6px">
          <b style="color:#0b3158;font-size:14px">${ev.nombre || '—'}</b>
          <span style="flex-shrink:0;font-size:10px;background:${clr};color:white;padding:2px 8px;border-radius:99px">${lbl}</span>
        </div>
        <div style="font-size:12px;color:#6b7280">
          ${ev.numero || '—'} &nbsp;·&nbsp; ${faenaNombre}
          <br>📅 Inicio planificado: ${fechaInicio} &nbsp;·&nbsp; 🏭 Equipos: ${nEquipos}
        </div>
      </div>`;
  }).join('');
}

// ── Conteo de mantenciones (equipos) por evento — best-effort: si falla,
//    no bloquea la lista, solo deja el conteo en 0 para esos eventos.
//    Distingue activos (estado <> 'cancelada', mismo criterio que usan
//    fn_calcular_revision_estado_evento y fn_quitar_equipo_evento) de
//    cancelados, para no sobrecontar equipos retirados (FASE 3.1F). ──
async function _eventosContarEquipos(idsEvento) {
  const conteo = {}; // { [eventoId]: { activos, cancelados, total } }
  if (!idsEvento.length) return conteo;

  try {
    const { data, error } = await supabaseAYCA
      .from('mantenciones')
      .select('evento_mantencion_id, estado')
      .in('evento_mantencion_id', idsEvento);

    if (error) throw error;

    (data || []).forEach(m => {
      const c = conteo[m.evento_mantencion_id] || (conteo[m.evento_mantencion_id] = { activos: 0, cancelados: 0, total: 0 });
      c.total++;
      if (m.estado === 'cancelada') c.cancelados++; else c.activos++;
    });
  } catch (e) {
    console.warn('No se pudo calcular la cantidad de equipos por evento:', e.message);
  }

  return conteo;
}

// ═══════════════════════════════════════════
// CREAR EVENTO DE MANTENCIÓN (FASE 3.1C)
// ═══════════════════════════════════════════

let _eventosGuardando   = false; // evita doble clic en "Crear evento"
let _eventosUsuarioForm = null;  // { id, esAdmin } del usuario que abrió el formulario
let _eventosUltimoCreado = null; // { id, numero } del último evento creado en esta sesión

// ── Navegar al formulario y cargar catálogos ──
async function eventosIrForm() {
  mostrar('eventoForm');
  await _eventosInicializarForm();
}

async function _eventosInicializarForm() {
  const err = document.getElementById('evtFormError');
  if (err) { err.style.display = 'none'; err.textContent = ''; }

  ['evtNombre', 'evtFechaInicio', 'evtFechaTermino', 'evtObservaciones'].forEach(id => {
    const el = document.getElementById(id); if (el) el.value = '';
  });

  const btn = document.getElementById('evtBtnGuardar');
  if (btn) { btn.disabled = false; btn.textContent = '💾 Crear evento'; }
  _eventosGuardando = false;

  const selFaena = document.getElementById('evtFaena');
  if (selFaena) { selFaena.innerHTML = '<option value="">— Seleccione un cliente primero —</option>'; selFaena.disabled = true; }

  const { data: sesion } = await supabaseAYCA.auth.getSession();
  _eventosUsuarioForm = {
    id: sesion?.session?.user?.id || null,
    esAdmin: (typeof perfilActual !== 'undefined' && (perfilActual.roles || []).includes('administrador'))
  };

  await Promise.all([
    _eventosCargarClientes(),
    _eventosCargarTiposEvento(),
    _eventosCargarSupervisor()
  ]);
}

async function _eventosCargarClientes() {
  const sel = document.getElementById('evtCliente');
  if (!sel) return;
  sel.innerHTML = '<option value="">Cargando...</option>';
  try {
    const { data, error } = await supabaseAYCA
      .from('clientes').select('id, nombre').eq('activo', true).order('nombre');
    if (error) throw error;
    sel.innerHTML = '<option value="">— Seleccione cliente —</option>' +
      (data || []).map(c => `<option value="${c.id}">${c.nombre}</option>`).join('');
  } catch (e) {
    sel.innerHTML = '<option value="">Error al cargar clientes</option>';
    console.error('_eventosCargarClientes:', e);
  }
}

// ── Faenas dependientes del cliente seleccionado (sin filtro RLS por cliente:
//    el filtro es de negocio, vía .eq('cliente_id', ...)) ──
async function eventosCargarFaenasPorCliente() {
  const clienteId = document.getElementById('evtCliente')?.value || '';
  const sel = document.getElementById('evtFaena');
  if (!sel) return;

  if (!clienteId) {
    sel.innerHTML = '<option value="">— Seleccione un cliente primero —</option>';
    sel.disabled = true;
    return;
  }

  sel.disabled = false;
  sel.innerHTML = '<option value="">Cargando...</option>';
  try {
    const { data, error } = await supabaseAYCA
      .from('faenas').select('id, nombre').eq('cliente_id', clienteId).eq('activo', true).order('nombre');
    if (error) throw error;
    sel.innerHTML = '<option value="">— Seleccione faena —</option>' +
      (data || []).map(f => `<option value="${f.id}">${f.nombre}</option>`).join('');
  } catch (e) {
    sel.innerHTML = '<option value="">Error al cargar faenas</option>';
    console.error('eventosCargarFaenasPorCliente:', e);
  }
}

async function _eventosCargarTiposEvento() {
  const sel = document.getElementById('evtTipoEvento');
  if (!sel) return;
  sel.innerHTML = '<option value="">Cargando...</option>';
  try {
    const { data, error } = await supabaseAYCA
      .from('tipos_evento_mantencion').select('codigo, nombre').eq('activo', true).order('orden');
    if (error) throw error;
    sel.innerHTML = '<option value="">— Seleccione tipo —</option>' +
      (data || []).map(t => `<option value="${t.codigo}">${t.nombre}</option>`).join('');
  } catch (e) {
    sel.innerHTML = '<option value="">Error al cargar tipos de evento</option>';
    console.error('_eventosCargarTiposEvento:', e);
  }
}

// ── Supervisor: fn_crear_evento_mantencion prohíbe a un supervisor asignar
//    a otro supervisor (solo a sí mismo), y las políticas RLS de
//    perfiles_ayca/usuario_roles solo permiten leer la fila propia salvo
//    que el usuario sea administrador. Por eso NO se ramifica por rol acá:
//    se consulta siempre usuario_roles con rol='supervisor', y RLS devuelve
//    automáticamente la lista completa si es admin, o solo la fila propia
//    si es supervisor — ambos casos quedan cubiertos con la misma consulta. ──
async function _eventosCargarSupervisor() {
  const cont = document.getElementById('evtSupervisorCont');
  if (!cont) return;

  cont.innerHTML = '<p style="color:#6b7280;font-size:13px">Cargando...</p>';
  try {
    const { data: roles, error: errRoles } = await supabaseAYCA
      .from('usuario_roles').select('usuario_id').eq('rol', 'supervisor');
    if (errRoles) throw errRoles;

    const ids = (roles || []).map(r => r.usuario_id);
    let perfiles = [];
    if (ids.length) {
      const { data, error } = await supabaseAYCA.from('perfiles_ayca').select('id, nombre').in('id', ids);
      if (error) throw error;
      perfiles = data || [];
    }

    if (!_eventosUsuarioForm?.esAdmin) {
      // Supervisor: el motor solo permite asignarse a sí mismo — campo fijo, sin selector.
      const propio = perfiles.find(p => p.id === _eventosUsuarioForm?.id);
      cont.innerHTML = `
        <input type="hidden" id="evtSupervisorId" value="${_eventosUsuarioForm?.id || ''}">
        <p style="margin:4px 0;color:#374151">${propio?.nombre || 'Tú'} (tú)</p>`;
      return;
    }

    cont.innerHTML = `<select id="evtSupervisorId">
      <option value="">— Seleccione supervisor —</option>
      ${perfiles.map(p => `<option value="${p.id}">${p.nombre || p.id}</option>`).join('')}
    </select>`;
  } catch (e) {
    cont.innerHTML = '<p style="color:#dc2626;font-size:12px">Error al cargar supervisores.</p>';
    console.error('_eventosCargarSupervisor:', e);
  }
}

// ── Crear el evento exclusivamente mediante fn_crear_evento_mantencion (RPC) ──
async function eventosCrear() {
  if (_eventosGuardando) return; // evita doble clic

  const errEl = document.getElementById('evtFormError');
  const showErr = (msg) => { if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; } };
  if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }

  const g = id => document.getElementById(id)?.value?.trim() || '';
  const clienteId     = g('evtCliente');
  const faenaId       = g('evtFaena');
  const tipoEvento    = g('evtTipoEvento');
  const nombre        = g('evtNombre');
  const supervisorId  = g('evtSupervisorId');
  const fechaInicio   = g('evtFechaInicio');
  const fechaTermino  = g('evtFechaTermino');
  const observaciones = g('evtObservaciones');

  if (!clienteId)    { showErr('Selecciona un cliente.'); return; }
  if (!faenaId)      { showErr('Selecciona una faena.'); return; }
  if (!tipoEvento)   { showErr('Selecciona un tipo de evento.'); return; }
  if (!nombre)       { showErr('Ingresa un nombre para el evento.'); return; }
  if (!supervisorId) { showErr('Selecciona un supervisor.'); return; }
  if (fechaInicio && fechaTermino && fechaTermino < fechaInicio) {
    showErr('La fecha de término no puede ser anterior a la fecha de inicio.');
    return;
  }

  const btn = document.getElementById('evtBtnGuardar');
  _eventosGuardando = true;
  if (btn) { btn.disabled = true; btn.textContent = 'Guardando...'; }

  try {
    const { data, error } = await supabaseAYCA.rpc('fn_crear_evento_mantencion', {
      p_cliente_id:         clienteId,
      p_faena_id:           faenaId,
      p_tipo_evento:        tipoEvento,
      p_nombre:             nombre,
      p_supervisor_id:      supervisorId,
      p_fecha_plan_inicio:  fechaInicio  || null,
      p_fecha_plan_termino: fechaTermino || null,
      p_observaciones:      observaciones || null
    });

    if (error) throw error;

    // fn_crear_evento_mantencion() es "returns table (id uuid, numero text)":
    // supabase-js entrega un array de filas, no un objeto único.
    const fila = Array.isArray(data) ? data[0] : data;
    if (!fila?.id) {
      throw new Error('La creación no devolvió un identificador de evento válido.');
    }

    _eventosUltimoCreado = { id: fila.id, numero: fila.numero };

    alert(`✅ Evento creado correctamente.\nN°: ${fila.numero || fila.id}`);
    mostrar('eventosLista');
  } catch (e) {
    console.error('eventosCrear:', e);
    showErr('No se pudo crear el evento: ' + e.message);
  } finally {
    _eventosGuardando = false;
    if (btn) { btn.disabled = false; btn.textContent = '💾 Crear evento'; }
  }
}

// ═══════════════════════════════════════════
// DETALLE Y RESUMEN DEL EVENTO (FASE 3.1D)
// ═══════════════════════════════════════════

let eventoActualId = null; // id del evento actualmente abierto en #eventoDetalle

// ── Abrir el detalle de un evento desde la lista ──
async function eventosAbrirDetalle(id) {
  eventoActualId = id;
  mostrar('eventoDetalle');
  await eventosCargarDetalle();
}

// ── Cargar y renderizar el detalle (solo lectura) ──
async function eventosCargarDetalle() {
  const cont = document.getElementById('eventoDetalleCont');
  if (!cont) return;

  if (!eventoActualId) {
    cont.innerHTML = '<p style="color:#dc2626;padding:12px">No se especificó ningún evento.</p>';
    return;
  }

  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando detalle...</p>';

  let ev;
  try {
    // clientes/faenas/tipos_evento_mantencion sí tienen FK directa desde
    // eventos_mantencion, así que PostgREST los resuelve como embed normal.
    // supervisor_id, en cambio, referencia auth.users(id) — NO existe FK
    // directa entre eventos_mantencion y perfiles_ayca, por lo que su
    // nombre se resuelve aparte en _eventosResolverSupervisor().
    const { data, error } = await supabaseAYCA
      .from('eventos_mantencion')
      .select(`
        id, numero, codigo, nombre, descripcion, estado, ejecucion_estado, revision_estado,
        personal_estado, recursos_estado, fecha_plan_inicio, fecha_plan_termino, observaciones,
        supervisor_id, faena_id,
        clientes(nombre), faenas(nombre), tipos_evento_mantencion(nombre)
      `)
      .eq('id', eventoActualId)
      .maybeSingle();

    if (error) throw error;

    if (!data) {
      cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Evento no encontrado o no visible.</p>';
      return;
    }
    ev = data;
    _eventosFaenaEvento = data.faena_id || null; // usado por el formulario de agregar equipo
  } catch (e) {
    console.error('eventosCargarDetalle:', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar el evento: ${e.message}</p>`;
    return;
  }

  const [supervisorNombre, conteoEquipos] = await Promise.all([
    _eventosResolverSupervisor(ev.supervisor_id),
    _eventosContarEquipos([ev.id])
  ]);
  const conteo = conteoEquipos[ev.id] || { activos: 0, cancelados: 0, total: 0 };
  const nEquipos = conteo.activos;

  // "finalizado"/"cancelado" son los únicos estados terminales del EVENTO
  // (vocabulario de eventos_mantencion_estado_check, 2D-01/2D-08) — mismo
  // criterio que usa fn_validar_supervisor_evento() para bloquear
  // fn_agregar_equipo_evento()/fn_quitar_equipo_evento() en el backend.
  const eventoTerminal = ev.estado === 'finalizado' || ev.estado === 'cancelado';

  const filaTexto = (etiqueta, valor) => `
    <div style="display:flex;justify-content:space-between;gap:10px;padding:6px 0;border-bottom:1px solid #f1f5f9">
      <span style="color:#6b7280;font-size:13px">${etiqueta}</span>
      <span style="font-size:13px;color:#1f2937;text-align:right">${(valor === null || valor === undefined || valor === '') ? '—' : valor}</span>
    </div>`;

  const filaEstado = (etiqueta, valor) => {
    const clr = EVENTOS_SUBESTADO_COLOR[valor] || '#6b7280';
    const lbl = EVENTOS_SUBESTADO_LABEL[valor] || valor || '—';
    return `
      <div style="display:flex;justify-content:space-between;align-items:center;padding:6px 0;border-bottom:1px solid #f1f5f9">
        <span style="color:#6b7280;font-size:13px">${etiqueta}</span>
        <span style="font-size:11px;background:${clr};color:white;padding:2px 8px;border-radius:99px">${lbl}</span>
      </div>`;
  };

  const clrEstado = EVENTOS_ESTADO_COLOR[ev.estado] || '#6b7280';
  const lblEstado = EVENTOS_ESTADO_LABEL[ev.estado] || ev.estado || '—';

  cont.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px;margin-bottom:4px">
      <h2 style="margin:0">${ev.nombre || '—'}</h2>
      <span style="flex-shrink:0;font-size:11px;background:${clrEstado};color:white;padding:3px 10px;border-radius:99px">${lblEstado}</span>
    </div>
    <p style="color:#6b7280;font-size:13px;margin:0 0 14px">${ev.numero || '—'}</p>

    <p id="eventoDetalleError" style="color:#dc2626;font-size:13px;margin:0 0 10px;padding:8px 12px;background:#fef2f2;border:1px solid #fecaca;border-radius:8px;display:none"></p>

    ${filaTexto('Cliente', ev.clientes?.nombre)}
    ${filaTexto('Faena', ev.faenas?.nombre)}
    ${filaTexto('Tipo de evento', ev.tipos_evento_mantencion?.nombre)}
    ${filaTexto('Supervisor', supervisorNombre)}
    ${filaTexto('Fecha planificada de inicio', ev.fecha_plan_inicio ? String(ev.fecha_plan_inicio).slice(0, 10) : null)}
    ${filaTexto('Fecha planificada de término', ev.fecha_plan_termino ? String(ev.fecha_plan_termino).slice(0, 10) : null)}
    ${filaTexto('Equipos activos', nEquipos)}
    ${conteo.cancelados ? filaTexto('Equipos retirados/cancelados', conteo.cancelados) : ''}

    <h3 style="margin:16px 0 4px">Estados</h3>
    ${filaEstado('Ejecución', ev.ejecucion_estado)}
    ${filaEstado('Revisión', ev.revision_estado)}
    ${filaEstado('Personal', ev.personal_estado)}
    ${filaEstado('Recursos', ev.recursos_estado)}

    <h3 style="margin:16px 0 4px">Observaciones</h3>
    <p style="font-size:13px;color:#374151;white-space:pre-wrap;margin:0">${ev.observaciones || '—'}</p>

    <div style="display:flex;justify-content:space-between;align-items:center;margin:16px 0 4px">
      <h3 style="margin:0">Equipos asociados</h3>
      ${eventoTerminal ? '' : `<button class="btn-verde" onclick="eventosIrFormEquipo()" style="width:auto;padding:8px 14px;font-size:13px">+ Agregar equipo</button>`}
    </div>
    ${eventoTerminal ? `
    <p style="color:#92400e;background:#fffbeb;border:1px solid #fcd34d;border-radius:8px;padding:8px 12px;font-size:12px;margin:0 0 8px">
      ⚠️ Este evento está en estado "${lblEstado}" — no se pueden agregar ni quitar equipos.
    </p>` : ''}
    <div id="eventoEquiposCont">
      <p style="color:#6b7280;text-align:center;padding:16px">Cargando equipos...</p>
    </div>

    <div style="display:flex;justify-content:space-between;align-items:center;margin:20px 0 4px">
      <h3 style="margin:0">🧰 Recursos solicitados</h3>
    </div>
    <div id="eventoRecursosCont">
      <p style="color:#6b7280;text-align:center;padding:16px">Cargando recursos...</p>
    </div>
  `;

  await eventosCargarEquiposDelEvento(eventoTerminal);
  await eventosCargarRecursosDelEvento(eventoTerminal);
}

// Vocabulario propio de "mantenciones.estado" (2026-07-17_mantenciones_etapa2b.sql) —
// distinto del vocabulario de "eventos_mantencion.estado".
const EVENTOS_MANTENCION_ESTADO_COLOR = {
  borrador:                 '#6b7280',
  pendiente_planificacion:  '#6b7280',
  planificada:              '#0b5cc7',
  pendiente_recursos:       '#d97706',
  lista_para_ejecutar:      '#0b5cc7',
  en_ejecucion:             '#d97706',
  pausada:                  '#d97706',
  en_revision:              '#d97706',
  cerrada:                  '#16a34a',
  cancelada:                '#dc2626'
};

const EVENTOS_MANTENCION_ESTADO_LABEL = {
  borrador:                 'Borrador',
  pendiente_planificacion:  'Pendiente planificación',
  planificada:              'Planificada',
  pendiente_recursos:       'Pendiente recursos',
  lista_para_ejecutar:      'Lista para ejecutar',
  en_ejecucion:             'En ejecución',
  pausada:                  'Pausada',
  en_revision:              'En revisión',
  cerrada:                  'Cerrada',
  cancelada:                'Cancelada'
};

// ── Cargar y renderizar las mantenciones (equipos) hijas del evento actual.
//    "eventoTerminal" (evento finalizado/cancelado) oculta "Quitar equipo"
//    en TODAS las filas, sin importar el estado de cada mantención. ──
async function eventosCargarEquiposDelEvento(eventoTerminal) {
  const cont = document.getElementById('eventoEquiposCont');
  if (!cont || !eventoActualId) return;

  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:16px">Cargando equipos...</p>';

  try {
    // equipo_id/area_id/tipo_mantencion_id son FK reales → embebibles.
    // "plantilla" se muestra desde mantenciones.nombre_plantilla (copia
    // denormalizada guardada al crear la mantención, 2C/2D-06), no
    // necesita embed de plantillas_mantencion.
    const { data, error } = await supabaseAYCA
      .from('mantenciones')
      .select('id, numero, estado, fecha_plan_inicio, nombre_plantilla, equipos(tag, nombre), areas(nombre), tipos_mantencion(nombre)')
      .eq('evento_mantencion_id', eventoActualId)
      .order('creado_en', { ascending: true });

    if (error) throw error;

    const mants = data || [];
    if (!mants.length) {
      cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:16px">Sin equipos asociados.</p>';
      return;
    }

    cont.innerHTML = mants.map(m => {
      const clr = EVENTOS_MANTENCION_ESTADO_COLOR[m.estado] || '#6b7280';
      const lbl = EVENTOS_MANTENCION_ESTADO_LABEL[m.estado] || m.estado || '—';
      const fecha = m.fecha_plan_inicio ? String(m.fecha_plan_inicio).slice(0, 10) : '—';

      // Mismo criterio que fn_quitar_equipo_evento(): rechaza mantenciones
      // ya 'cancelada'/'cerrada', y fn_validar_supervisor_evento() rechaza
      // el evento si está 'finalizado'/'cancelado'.
      const puedeQuitar = !eventoTerminal && m.estado !== 'cancelada' && m.estado !== 'cerrada';
      const numeroAttr = (m.numero || '').replace(/'/g, "\\'");

      return `
        <div class="card" style="border-left:4px solid ${clr};padding:10px 12px;margin:6px 0;cursor:pointer"
             onclick="otAbrir('${m.id}')">
          <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:6px;margin-bottom:4px">
            <b style="color:#0b3158;font-size:13px">${m.equipos?.tag || '—'} — ${m.equipos?.nombre || '—'}</b>
            <span style="flex-shrink:0;font-size:10px;background:${clr};color:white;padding:2px 8px;border-radius:99px">${lbl}</span>
          </div>
          <div style="font-size:12px;color:#6b7280">
            ${m.areas?.nombre || '—'} &nbsp;·&nbsp; ${m.tipos_mantencion?.nombre || '—'}
            <br>📋 ${m.nombre_plantilla || '—'} &nbsp;·&nbsp; 📅 ${fecha}
          </div>
          ${puedeQuitar ? `
          <div style="margin-top:8px;text-align:right">
            <button class="btn-rojo quitar-equipo-btn" style="width:auto;padding:6px 12px;font-size:12px"
                    onclick="event.stopPropagation(); eventosQuitarEquipo('${m.id}', '${numeroAttr}')">✖ Quitar equipo</button>
          </div>` : ''}
        </div>`;
    }).join('');
  } catch (e) {
    console.error('eventosCargarEquiposDelEvento:', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar equipos: ${e.message}</p>`;
  }
}

// ═══════════════════════════════════════════
// AGREGAR EQUIPO AL EVENTO (FASE 3.1E)
// ═══════════════════════════════════════════

let _eventosGuardandoEquipo = false; // evita doble clic en "Agregar equipo"
let _eventosFaenaEvento     = null;  // faena_id del evento actual, para filtrar áreas

// ── Navegar al formulario y cargar catálogos ──
async function eventosIrFormEquipo() {
  if (!eventoActualId) { alert('No hay un evento seleccionado.'); return; }
  mostrar('eventoAgregarEquipo');
  await _eventosInicializarFormEquipo();
}

async function _eventosInicializarFormEquipo() {
  const err = document.getElementById('eqFormError');
  if (err) { err.style.display = 'none'; err.textContent = ''; }

  ['eqFechaInicio', 'eqFechaTermino', 'eqObservaciones'].forEach(id => {
    const el = document.getElementById(id); if (el) el.value = '';
  });

  const btn = document.getElementById('eqBtnGuardar');
  if (btn) { btn.disabled = false; btn.textContent = '💾 Agregar equipo'; }
  _eventosGuardandoEquipo = false;

  const selEquipo = document.getElementById('eqEquipo');
  if (selEquipo) { selEquipo.innerHTML = '<option value="">— Seleccione un área primero —</option>'; selEquipo.disabled = true; }

  const selPlantilla = document.getElementById('eqPlantilla');
  if (selPlantilla) { selPlantilla.innerHTML = '<option value="">— Seleccione un tipo de mantención primero —</option>'; selPlantilla.disabled = true; }

  await Promise.all([
    _eventosCargarAreas(),
    _eventosCargarTiposMantencion()
  ]);
}

// ── Áreas de la faena del evento actual (fn_agregar_equipo_evento valida la
//    jerarquía área→faena→cliente del EVENTO, así que filtrar por esa faena
//    evita al usuario elegir combinaciones que el motor rechazará igual) ──
async function _eventosCargarAreas() {
  const sel = document.getElementById('eqArea');
  if (!sel) return;

  if (!_eventosFaenaEvento) {
    sel.innerHTML = '<option value="">No se pudo determinar la faena del evento</option>';
    return;
  }

  sel.innerHTML = '<option value="">Cargando...</option>';
  try {
    const { data, error } = await supabaseAYCA
      .from('areas').select('id, nombre').eq('faena_id', _eventosFaenaEvento).eq('activo', true).order('nombre');
    if (error) throw error;
    sel.innerHTML = '<option value="">— Seleccione área —</option>' +
      (data || []).map(a => `<option value="${a.id}">${a.nombre}</option>`).join('');
  } catch (e) {
    sel.innerHTML = '<option value="">Error al cargar áreas</option>';
    console.error('_eventosCargarAreas:', e);
  }
}

// ── Equipos filtrados por el área seleccionada ──
async function eventosCargarEquiposPorArea() {
  const areaId = document.getElementById('eqArea')?.value || '';
  const sel = document.getElementById('eqEquipo');
  if (!sel) return;

  if (!areaId) {
    sel.innerHTML = '<option value="">— Seleccione un área primero —</option>';
    sel.disabled = true;
    return;
  }

  sel.disabled = false;
  sel.innerHTML = '<option value="">Cargando...</option>';
  try {
    const { data, error } = await supabaseAYCA
      .from('equipos').select('id, tag, nombre').eq('area_id', areaId).eq('activo', true).order('nombre');
    if (error) throw error;
    sel.innerHTML = '<option value="">— Seleccione equipo —</option>' +
      (data || []).map(e => `<option value="${e.id}">${e.tag} — ${e.nombre}</option>`).join('');
  } catch (e) {
    sel.innerHTML = '<option value="">Error al cargar equipos</option>';
    console.error('eventosCargarEquiposPorArea:', e);
  }
}

async function _eventosCargarTiposMantencion() {
  const sel = document.getElementById('eqTipoMant');
  if (!sel) return;
  sel.innerHTML = '<option value="">Cargando...</option>';
  try {
    const { data, error } = await supabaseAYCA
      .from('tipos_mantencion').select('id, nombre').eq('activo', true).order('nombre');
    if (error) throw error;
    sel.innerHTML = '<option value="">— Seleccione tipo de mantención —</option>' +
      (data || []).map(t => `<option value="${t.id}">${t.nombre}</option>`).join('');
  } catch (e) {
    sel.innerHTML = '<option value="">Error al cargar tipos de mantención</option>';
    console.error('_eventosCargarTiposMantencion:', e);
  }
}

// ── Plantillas: dependen ÚNICAMENTE de tipo_mantencion_id (plantillas_mantencion
//    no tiene columna de cliente/faena/tipo_equipo). Además existe un índice único
//    parcial "una plantilla activa por tipo", así que normalmente habrá 0 o 1
//    opción activa por tipo elegido. ──
async function eventosCargarPlantillasPorTipo() {
  const tipoId = document.getElementById('eqTipoMant')?.value || '';
  const sel = document.getElementById('eqPlantilla');
  if (!sel) return;

  if (!tipoId) {
    sel.innerHTML = '<option value="">— Seleccione un tipo de mantención primero —</option>';
    sel.disabled = true;
    return;
  }

  sel.disabled = false;
  sel.innerHTML = '<option value="">Cargando...</option>';
  try {
    const { data, error } = await supabaseAYCA
      .from('plantillas_mantencion').select('id, nombre, version')
      .eq('tipo_mantencion_id', tipoId).eq('activa', true).order('version', { ascending: false });
    if (error) throw error;
    sel.innerHTML = '<option value="">— Seleccione plantilla —</option>' +
      (data || []).map(p => `<option value="${p.id}">${p.nombre} (v${p.version})</option>`).join('');
  } catch (e) {
    sel.innerHTML = '<option value="">Error al cargar plantillas</option>';
    console.error('eventosCargarPlantillasPorTipo:', e);
  }
}

// ── Agregar el equipo exclusivamente mediante fn_agregar_equipo_evento (RPC) ──
async function eventosAgregarEquipo() {
  if (_eventosGuardandoEquipo) return; // evita doble clic
  if (!eventoActualId) { alert('No hay un evento seleccionado.'); return; }

  const errEl = document.getElementById('eqFormError');
  const showErr = (msg) => { if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; } };
  if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }

  const g = id => document.getElementById(id)?.value?.trim() || '';
  const areaId        = g('eqArea');
  const equipoId      = g('eqEquipo');
  const tipoMantId    = g('eqTipoMant');
  const plantillaId   = g('eqPlantilla');
  const fechaInicio   = g('eqFechaInicio');
  const fechaTermino  = g('eqFechaTermino');
  const observaciones = g('eqObservaciones');

  if (!areaId)      { showErr('Selecciona un área.'); return; }
  if (!equipoId)    { showErr('Selecciona un equipo.'); return; }
  if (!tipoMantId)  { showErr('Selecciona un tipo de mantención.'); return; }
  if (!plantillaId) { showErr('Selecciona una plantilla.'); return; }
  if (fechaInicio && fechaTermino && fechaTermino < fechaInicio) {
    showErr('La fecha de término no puede ser anterior a la fecha de inicio.');
    return;
  }

  const btn = document.getElementById('eqBtnGuardar');
  _eventosGuardandoEquipo = true;
  if (btn) { btn.disabled = true; btn.textContent = 'Guardando...'; }

  try {
    const { data, error } = await supabaseAYCA.rpc('fn_agregar_equipo_evento', {
      p_evento_id:          eventoActualId,
      p_area_id:            areaId,
      p_equipo_id:          equipoId,
      p_tipo_mantencion_id: tipoMantId,
      p_plantilla_id:       plantillaId,
      p_fecha_plan_inicio:  fechaInicio  || null,
      p_fecha_plan_termino: fechaTermino || null,
      p_observaciones:      observaciones || null
    });

    if (error) throw error;

    // fn_agregar_equipo_evento() es "returns table (mantencion_id uuid, numero text)":
    // supabase-js entrega un array de filas, no un objeto único.
    const fila = Array.isArray(data) ? data[0] : data;
    if (!fila?.mantencion_id) {
      throw new Error('La operación no devolvió un identificador de mantención válido.');
    }

    alert(`✅ Equipo agregado correctamente.\nMantención N°: ${fila.numero || fila.mantencion_id}`);

    mostrar('eventoDetalle');
    await eventosCargarDetalle(); // recarga estados, conteo de equipos y la lista de equipos
  } catch (e) {
    console.error('eventosAgregarEquipo:', e);
    showErr('No se pudo agregar el equipo: ' + e.message);
  } finally {
    _eventosGuardandoEquipo = false;
    if (btn) { btn.disabled = false; btn.textContent = '💾 Agregar equipo'; }
  }
}

// ── Resolver el nombre del supervisor — no existe FK embebible entre
//    eventos_mantencion.supervisor_id y perfiles_ayca (ambos apuntan a
//    auth.users(id), pero no entre sí), así que se hace una segunda
//    consulta directa. RLS de perfiles_ayca solo permite leer la fila
//    propia o ser administrador — si no es visible, se degrada con un
//    texto informativo en vez de romper el detalle. ──
async function _eventosResolverSupervisor(supervisorId) {
  if (!supervisorId) return '—';
  try {
    const { data, error } = await supabaseAYCA
      .from('perfiles_ayca').select('nombre').eq('id', supervisorId).maybeSingle();
    if (error) throw error;
    return data?.nombre || 'Supervisor asignado (sin nombre visible)';
  } catch (e) {
    console.warn('_eventosResolverSupervisor:', e.message);
    return 'Supervisor asignado (no disponible)';
  }
}

// ═══════════════════════════════════════════
// QUITAR EQUIPO DEL EVENTO (FASE 3.1F)
// ═══════════════════════════════════════════

let _eventosQuitandoEquipo = false; // evita doble clic / llamadas repetidas

// ── Quitar (cancelar) una mantención del evento exclusivamente mediante
//    fn_quitar_equipo_evento (RPC). La función retorna void: el éxito se
//    determina solo por la ausencia de error, nunca se lee data[0]. ──
async function eventosQuitarEquipo(mantencionId, numeroMantencion) {
  if (_eventosQuitandoEquipo) return; // evita doble clic

  const errEl = document.getElementById('eventoDetalleError');
  if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }

  const confirmado = confirm(
    '¿Quitar este equipo del evento?' +
    (numeroMantencion ? `\nMantención: ${numeroMantencion}` : '') +
    '\n\nLa mantención quedará marcada como "Cancelada" (no se elimina; conserva su historial y puede volver a agregarse el mismo equipo más adelante).'
  );
  if (!confirmado) return;

  // Motivo opcional: si el usuario cancela el prompt o lo deja vacío, se
  // envía null y el motor usa su propio motivo por defecto.
  const motivoIngresado = prompt('Motivo del retiro (opcional):', '');
  const motivo = (motivoIngresado && motivoIngresado.trim()) ? motivoIngresado.trim() : null;

  _eventosQuitandoEquipo = true;
  document.querySelectorAll('.quitar-equipo-btn').forEach(b => b.disabled = true);

  try {
    const { error } = await supabaseAYCA.rpc('fn_quitar_equipo_evento', {
      p_mantencion_id: mantencionId,
      p_motivo: motivo
    });

    if (error) throw error;

    // fn_quitar_equipo_evento() retorna void — no hay data que leer, el
    // éxito es simplemente la ausencia de error.
    alert('✅ Equipo retirado correctamente del evento.');

    // eventoActualId no cambia: recarga estados, conteo (activos/cancelados)
    // y la lista de equipos en un solo llamado, igual que en 3.1E.
    await eventosCargarDetalle();
  } catch (e) {
    console.error('eventosQuitarEquipo:', e);
    if (errEl) {
      errEl.textContent = 'No se pudo quitar el equipo: ' + e.message;
      errEl.style.display = 'block';
    }
  } finally {
    _eventosQuitandoEquipo = false;
    document.querySelectorAll('.quitar-equipo-btn').forEach(b => b.disabled = false);
  }
}
