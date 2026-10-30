// ===============================
// AYCA SMART MAINTENANCE — ORDENTRABAJO.JS
// Pantalla "Orden de Trabajo" — núcleo de ejecución de una mantención.
// Esta misma pantalla se reutilizará en fases futuras (checkboxes,
// observaciones, fotografías, firmas, impresión, cierre de mantención).
//
// Requiere: supabaseAYCA (database.js), mostrar()/eventoActualId (app.js/eventos.js),
//           _eventosResolverSupervisor(), EVENTOS_MANTENCION_ESTADO_COLOR/LABEL (eventos.js).
//
// Tablas Supabase: mantenciones (encabezado, con embeds reales de
// clientes/faenas/equipos/areas/tipos_mantencion), mantencion_actividades
// (única fuente de actividades — snapshot propio de la mantención, SIN
// join ni lectura en vivo de plantilla_actividades en ejecución).
// ===============================

let otMantencionId = null; // id de la mantención actualmente abierta en #ordenTrabajo
let otMantencionActual = null;      // datos de encabezado ya cargados (evita releerlos para el PDF)
let otSupervisorNombreActual = '—'; // nombre del supervisor ya resuelto

// ── Abrir la Orden de Trabajo desde una tarjeta de "Equipos asociados" ──
async function otAbrir(mantencionId) {
  otMantencionId = mantencionId;
  mostrar('ordenTrabajo');
  await otCargarEncabezado();
  await otCargarActividades();
}

// ── Volver a la pantalla de detalle del evento, recargándola ──
function otVolverAlEvento() {
  mostrar('eventoDetalle');
  if (typeof eventosCargarDetalle === 'function') eventosCargarDetalle();
}

// ── Encabezado completo de la mantención (solo lectura) ──
async function otCargarEncabezado() {
  const cont = document.getElementById('otEncabezado');
  if (!cont) return;

  if (!otMantencionId) {
    cont.innerHTML = '<p style="color:#dc2626;padding:12px">No se especificó ninguna mantención.</p>';
    return;
  }

  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando orden de trabajo...</p>';

  let m;
  try {
    // cliente_id/faena_id/equipo_id/area_id/tipo_mantencion_id son FK reales
    // en mantenciones → embebibles. "Plantilla" se lee de nombre_plantilla
    // (columna ya denormalizada al crear la mantención), no requiere embed.
    const { data, error } = await supabaseAYCA
      .from('mantenciones')
      .select(`
        id, numero, estado, nombre_plantilla, fecha_plan_inicio, fecha_plan_termino, observaciones,
        supervisor_id,
        clientes(nombre), faenas(nombre), equipos(tag, nombre), areas(nombre), tipos_mantencion(nombre)
      `)
      .eq('id', otMantencionId)
      .maybeSingle();

    if (error) throw error;

    if (!data) {
      cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Mantención no encontrada o no visible.</p>';
      return;
    }
    m = data;
  } catch (e) {
    console.error('otCargarEncabezado:', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar la orden de trabajo: ${e.message}</p>`;
    return;
  }

  // supervisor_id referencia auth.users(id), sin FK directa a perfiles_ayca
  // (mismo caso ya resuelto para eventos_mantencion) — se reutiliza el
  // resolver ya existente en eventos.js en vez de duplicar la consulta.
  const supervisorNombre = (typeof _eventosResolverSupervisor === 'function')
    ? await _eventosResolverSupervisor(m.supervisor_id)
    : '—';

  // Cache — el generador de PDF (Anexo A1) lee de aquí, sin volver a consultar Supabase.
  otMantencionActual = m;
  otSupervisorNombreActual = supervisorNombre;

  const clr = EVENTOS_MANTENCION_ESTADO_COLOR[m.estado] || '#6b7280';
  const lbl = EVENTOS_MANTENCION_ESTADO_LABEL[m.estado] || m.estado || '—';

  const fila = (etiqueta, valor) => `
    <div style="display:flex;justify-content:space-between;gap:10px;padding:6px 0;border-bottom:1px solid #f1f5f9">
      <span style="color:#6b7280;font-size:13px">${etiqueta}</span>
      <span style="font-size:13px;color:#1f2937;text-align:right">${(valor === null || valor === undefined || valor === '') ? '—' : valor}</span>
    </div>`;

  cont.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px;margin-bottom:4px">
      <h2 style="margin:0">${m.equipos?.tag || '—'} — ${m.equipos?.nombre || '—'}</h2>
      <span style="flex-shrink:0;font-size:11px;background:${clr};color:white;padding:3px 10px;border-radius:99px">${lbl}</span>
    </div>
    <p style="color:#6b7280;font-size:13px;margin:0 0 14px">${m.numero || '—'}</p>

    ${fila('Cliente', m.clientes?.nombre)}
    ${fila('Faena', m.faenas?.nombre)}
    ${fila('Área', m.areas?.nombre)}
    ${fila('Tipo de mantención', m.tipos_mantencion?.nombre)}
    ${fila('Plantilla', m.nombre_plantilla)}
    ${fila('Supervisor', supervisorNombre)}
    ${fila('Fecha planificada de inicio', m.fecha_plan_inicio ? String(m.fecha_plan_inicio).slice(0, 10) : null)}
    ${fila('Fecha planificada de término', m.fecha_plan_termino ? String(m.fecha_plan_termino).slice(0, 10) : null)}

    <h3 style="margin:16px 0 4px">Observaciones</h3>
    <p style="font-size:13px;color:#374151;white-space:pre-wrap;margin:0">${m.observaciones || '—'}</p>
  `;
}

// ═══════════════════════════════════════════
// ACTIVIDADES + PROGRESO (Fase B)
// ═══════════════════════════════════════════

let otActividades   = [];        // cache en memoria de las actividades ya cargadas (evita releer las 125 filas en cada toggle)
let otGuardandoIds  = new Set(); // ids de actividades con un UPDATE en curso — evita dobles guardados simultáneos

// ── Slug simple para armar ids de DOM estables a partir de nombres de área/sección.
//    El rango de marcas diacríticas combinadas (U+0300–U+036F) se arma con
//    codePointAt en vez de un literal en el código fuente, para no depender
//    de caracteres combinados ambiguos dentro del archivo. ──
const _OT_DIACRITICOS = new RegExp('[' + String.fromCodePoint(0x0300) + '-' + String.fromCodePoint(0x036f) + ']', 'g');

function _otSlug(texto) {
  return String(texto)
    .toLowerCase()
    .normalize('NFD').replace(_OT_DIACRITICOS, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '') || 'x';
}

// ── Agrupa una lista de actividades en Área → Sección, preservando el
//    orden de aparición (Map conserva orden de inserción). Compartida
//    entre la pantalla (otCargarActividades) y el generador de PDF
//    (otGenerarAnexoA1Pdf) — misma lógica exacta en ambos casos. ──
function _otAgruparPorAreaSeccion(lista) {
  const areas = new Map();
  lista.forEach(a => {
    const areaKey    = a.area    || 'Sin área asignada';
    const seccionKey = a.seccion || 'Sin sección asignada';
    if (!areas.has(areaKey)) areas.set(areaKey, new Map());
    const secciones = areas.get(areaKey);
    if (!secciones.has(seccionKey)) secciones.set(seccionKey, []);
    secciones.get(seccionKey).push(a);
  });
  return areas;
}

// ── Actividades: fuente exclusiva mantencion_actividades, agrupadas
//    Área → Sección, ordenadas por "orden". Excluye estado_fila='eliminado'
//    (esas filas ya no forman parte del alcance vigente de la mantención,
//    ni se muestran ni se cuentan en el progreso). ──
async function otCargarActividades() {
  const cont = document.getElementById('otActividadesCont');
  if (!cont) return;

  if (!otMantencionId) return;

  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando actividades...</p>';

  try {
    const { data, error } = await supabaseAYCA
      .from('mantencion_actividades')
      .select('id, codigo_actividad, descripcion, orden, area, seccion, obligatoria, duracion_estimada_horas, estado_ejecucion, resultado, num_observacion')
      .eq('mantencion_id', otMantencionId)
      .neq('estado_fila', 'eliminado')
      .order('orden', { ascending: true });

    if (error) {
      console.error('otCargarActividades — error de Supabase:', error);
      throw error;
    }
    otActividades = data || [];
  } catch (e) {
    console.error('otCargarActividades:', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar las actividades: ${e.message}</p>`;
    otActividades = [];
    return;
  }

  if (!otActividades.length) {
    cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Esta mantención no tiene actividades activas registradas.</p>';
    return;
  }

  // Agrupar Área → Sección preservando el orden ya aplicado por la consulta
  // (función compartida con el generador de PDF — misma lógica exacta).
  const areas = _otAgruparPorAreaSeccion(otActividades);

  let html = '';
  for (const [areaNombre, secciones] of areas) {
    const areaKey    = _otSlug(areaNombre);
    const totalArea  = [...secciones.values()].reduce((n, arr) => n + arr.length, 0);

    html += `<details style="margin:8px 0;border:1px solid #e2e8f0;border-radius:10px;overflow:hidden">
      <summary style="background:#0b3158;color:white;padding:10px 14px;font-weight:bold;cursor:pointer;display:flex;justify-content:space-between;align-items:center;gap:8px">
        <span>${areaNombre} <span style="font-weight:normal;opacity:0.8;font-size:12px">(${totalArea} actividad${totalArea !== 1 ? 'es' : ''})</span></span>
        <span id="ot-area-progreso-${areaKey}" style="font-weight:normal;font-size:12px">…</span>
      </summary>
      <div style="padding:4px 14px 10px">`;

    for (const [seccionNombre, filas] of secciones) {
      const seccionKey = `${areaKey}-${_otSlug(seccionNombre)}`;

      html += `<details style="margin:8px 0" open>
        <summary style="font-weight:bold;color:#0b3158;cursor:pointer;padding:6px 0;display:flex;justify-content:space-between;align-items:center;gap:8px">
          <span>${seccionNombre} <span style="font-weight:normal;color:#6b7280;font-size:12px">(${filas.length})</span></span>
          <span id="ot-seccion-progreso-${seccionKey}" style="font-weight:normal;color:#6b7280;font-size:12px">…</span>
        </summary>
        <div style="padding:2px 0 8px 10px">`;

      filas.forEach(a => {
        const completada = a.estado_ejecucion === 'completada';
        const obsValor = a.num_observacion ? String(a.num_observacion).replace(/"/g, '&quot;') : '';
        html += `
          <div id="ot-fila-${a.id}" style="display:flex;gap:8px;align-items:flex-start;padding:8px 6px;border-bottom:1px solid #f1f5f9;border-radius:6px;background:${completada ? '#f0fdf4' : 'transparent'}">
            <input type="checkbox" id="ot-check-${a.id}" ${completada ? 'checked' : ''}
                   onchange="otToggleActividad('${a.id}', this)"
                   style="margin-top:3px;width:18px;height:18px;flex-shrink:0;cursor:pointer">
            <div style="flex:1">
              <div class="ot-texto-actividad" style="font-size:13px;color:${completada ? '#166534' : '#1f2937'}">
                <b class="ot-codigo-actividad" style="color:${completada ? '#166534' : '#0b3158'}">${a.codigo_actividad || '—'}</b> — ${a.descripcion || '—'}
                ${a.obligatoria ? '<span style="font-size:10px;background:#dc2626;color:white;padding:1px 6px;border-radius:99px;margin-left:6px">Obligatoria</span>' : ''}
              </div>
              ${a.duracion_estimada_horas ? `<div style="font-size:11px;color:#9ca3af;margin-top:2px">⏱ ${a.duracion_estimada_horas} h estimadas</div>` : ''}
              <div id="ot-guardando-${a.id}" style="display:none;font-size:11px;color:#0b5cc7;margin-top:2px">Guardando…</div>
              <div id="ot-error-${a.id}" style="display:none;font-size:11px;color:#dc2626;margin-top:2px"></div>

              <!-- Resultado corporativo (Sí/No/N/A) y N° Obs. — INDEPENDIENTES
                   de estado_ejecucion: no reutilizan el checkbox de arriba ni
                   su lógica. Botones .btn-sino/.sino-si/.sino-no/.sino-na:
                   mismas clases ya usadas en ventilador.js (verde/rojo/gris),
                   no se define ningún color nuevo. -->
              <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-top:6px;padding-top:6px;border-top:1px dashed #e5e7eb">
                <div style="display:flex;gap:6px;align-items:center">
                  <button type="button" id="ot-resultado-si-${a.id}" class="btn-sino${a.resultado === 'si' ? ' sino-si' : ''}"
                          onclick="otGuardarResultado('${a.id}', 'si', this)">SÍ</button>
                  <button type="button" id="ot-resultado-no-${a.id}" class="btn-sino${a.resultado === 'no' ? ' sino-no' : ''}"
                          onclick="otGuardarResultado('${a.id}', 'no', this)">NO</button>
                  <button type="button" id="ot-resultado-na-${a.id}" class="btn-sino${a.resultado === 'na' ? ' sino-na' : ''}"
                          onclick="otGuardarResultado('${a.id}', 'na', this)">N/A</button>
                  <span id="ot-guardando-resultado-${a.id}" style="display:none;font-size:11px;color:#0b5cc7">Guardando…</span>
                </div>
                <input type="text" id="ot-obs-${a.id}" placeholder="N° Obs." value="${obsValor}"
                       inputmode="decimal"
                       oninput="this.value = this.value.replace(/[^0-9.]/g, '')"
                       onblur="otGuardarObservacion('${a.id}', this)"
                       style="width:90px;padding:4px 6px;margin:0;font-size:11px;border:1px solid #cbd5e1;border-radius:6px">
                <span id="ot-guardando-obs-${a.id}" style="display:none;font-size:11px;color:#0b5cc7">Guardando…</span>
              </div>
              <div id="ot-error-resultado-${a.id}" style="display:none;font-size:11px;color:#dc2626;margin-top:2px"></div>
              <div id="ot-error-obs-${a.id}" style="display:none;font-size:11px;color:#dc2626;margin-top:2px"></div>
            </div>
          </div>`;
      });

      html += `</div></details>`;
    }

    html += `</div></details>`;
  }

  cont.innerHTML = html;
  otActualizarResumenProgreso();
}

// ── Cálculo puro del progreso general (no toca el DOM) ──
function otCalcularProgresoGeneral() {
  const total = otActividades.length;
  const completadas = otActividades.filter(a => a.estado_ejecucion === 'completada').length;
  const porcentaje = total > 0 ? Math.round((completadas / total) * 100) : 0;
  return { total, completadas, pendientes: total - completadas, porcentaje };
}

// ── Cálculo puro del progreso de un Área (no toca el DOM) ──
function otCalcularProgresoArea(areaNombre) {
  const filas = otActividades.filter(a => (a.area || 'Sin área asignada') === areaNombre);
  const total = filas.length;
  const completadas = filas.filter(a => a.estado_ejecucion === 'completada').length;
  const porcentaje = total > 0 ? Math.round((completadas / total) * 100) : 0;
  return { total, completadas, porcentaje };
}

// ── Cálculo puro del progreso de una Sección dentro de un Área (no toca el DOM) ──
function otCalcularProgresoSeccion(areaNombre, seccionNombre) {
  const filas = otActividades.filter(a =>
    (a.area || 'Sin área asignada') === areaNombre && (a.seccion || 'Sin sección asignada') === seccionNombre
  );
  const total = filas.length;
  const completadas = filas.filter(a => a.estado_ejecucion === 'completada').length;
  return { total, completadas };
}

// ── Repinta el resumen superior y los badges de progreso por Área/Sección
//    ya presentes en el DOM — nunca regenera los <details>, así que el
//    estado abierto/cerrado de los acordeones no se pierde. ──
function otActualizarResumenProgreso() {
  const resumen = otCalcularProgresoGeneral();
  const cont = document.getElementById('otResumen');
  if (cont) {
    cont.innerHTML = `
      <div style="display:flex;justify-content:space-between;flex-wrap:wrap;gap:10px;margin-bottom:10px">
        <div><b style="color:#0b3158;font-size:16px">${resumen.total}</b><br><span style="color:#6b7280;font-size:11px">Total</span></div>
        <div><b style="color:#16a34a;font-size:16px">${resumen.completadas}</b><br><span style="color:#6b7280;font-size:11px">Completadas</span></div>
        <div><b style="color:#d97706;font-size:16px">${resumen.pendientes}</b><br><span style="color:#6b7280;font-size:11px">Pendientes</span></div>
        <div><b style="color:#0b5cc7;font-size:16px">${resumen.porcentaje}%</b><br><span style="color:#6b7280;font-size:11px">Avance</span></div>
      </div>
      <div style="background:#e5e7eb;border-radius:99px;height:10px;overflow:hidden">
        <div style="background:#16a34a;height:100%;width:${resumen.porcentaje}%;transition:width 0.3s"></div>
      </div>`;
  }

  // Actualizar badges de Área/Sección ya renderizados, sin reconstruir el árbol.
  const gruposVistos = new Set();
  otActividades.forEach(a => {
    const areaNombre    = a.area    || 'Sin área asignada';
    const seccionNombre = a.seccion || 'Sin sección asignada';
    const areaKey    = _otSlug(areaNombre);
    const seccionKey = `${areaKey}-${_otSlug(seccionNombre)}`;

    if (!gruposVistos.has(areaKey)) {
      gruposVistos.add(areaKey);
      const pArea = otCalcularProgresoArea(areaNombre);
      const elArea = document.getElementById(`ot-area-progreso-${areaKey}`);
      if (elArea) elArea.textContent = `${pArea.completadas} / ${pArea.total} — ${pArea.porcentaje}%`;
    }

    if (!gruposVistos.has(seccionKey)) {
      gruposVistos.add(seccionKey);
      const pSeccion = otCalcularProgresoSeccion(areaNombre, seccionNombre);
      const elSeccion = document.getElementById(`ot-seccion-progreso-${seccionKey}`);
      if (elSeccion) elSeccion.textContent = `${pSeccion.completadas} / ${pSeccion.total}`;
    }
  });
}

// ── Aplica el estilo visual (fondo verde suave + texto verde) de una fila,
//    sin tocar el resto de su contenido. ──
function otAplicarEstadoVisualFila(actividadId, completada) {
  const fila = document.getElementById(`ot-fila-${actividadId}`);
  if (!fila) return;
  fila.style.background = completada ? '#f0fdf4' : 'transparent';

  const texto = fila.querySelector('.ot-texto-actividad');
  if (texto) texto.style.color = completada ? '#166534' : '#1f2937';

  const codigo = fila.querySelector('.ot-codigo-actividad');
  if (codigo) codigo.style.color = completada ? '#166534' : '#0b3158';
}

// ── Deshabilita/habilita TODOS los controles de una fila (checkbox,
//    botones de resultado y campo de observación) mientras cualquiera de
//    ellos tiene un guardado en curso — evita que dos operaciones
//    distintas escriban sobre la misma fila al mismo tiempo. ──
function otSetControlesDisabled(actividadId, disabled) {
  const checkbox = document.getElementById(`ot-check-${actividadId}`);
  if (checkbox) checkbox.disabled = disabled;

  ['si', 'no', 'na'].forEach(v => {
    const btn = document.getElementById(`ot-resultado-${v}-${actividadId}`);
    if (btn) btn.disabled = disabled;
  });

  const obs = document.getElementById(`ot-obs-${actividadId}`);
  if (obs) obs.disabled = disabled;
}

// ── Marca el botón correspondiente a "valor" ('si'/'no'/'na'/null) con su
//    color (verde/rojo/gris, clases .sino-*), quitando el color de los
//    otros dos — mismo patrón que setSinoVent() en ventilador.js. ──
function otMarcarBotonResultado(actividadId, valor) {
  ['si', 'no', 'na'].forEach(v => {
    const btn = document.getElementById(`ot-resultado-${v}-${actividadId}`);
    if (!btn) return;
    btn.classList.remove('sino-si', 'sino-no', 'sino-na');
    if (v === valor) btn.classList.add(`sino-${v}`);
  });
}

// ── Marcar/desmarcar una actividad — único punto que escribe en Supabase.
//    Optimista: refleja el cambio de inmediato y lo revierte si falla.
//    Solo toca estado_ejecucion (actualizado_por/actualizado_en los
//    completa automáticamente el trigger trg_auditoria_mantencion_actividades
//    ya existente — no hace falta enviarlos desde el cliente). ──
async function otToggleActividad(actividadId, checkboxEl) {
  if (otGuardandoIds.has(actividadId)) {
    // Ya hay un guardado en curso para esta misma actividad: revertir el
    // clic y salir, para evitar dos UPDATE simultáneos sobre la misma fila.
    checkboxEl.checked = !checkboxEl.checked;
    return;
  }

  const actividad = otActividades.find(a => a.id === actividadId);
  if (!actividad) return;

  const estadoAnterior = actividad.estado_ejecucion;
  const nuevoEstado = checkboxEl.checked ? 'completada' : 'pendiente';

  const errorEl = document.getElementById(`ot-error-${actividadId}`);
  if (errorEl) { errorEl.style.display = 'none'; errorEl.textContent = ''; }

  // Optimista: reflejar el cambio de inmediato, sin esperar la respuesta de red.
  actividad.estado_ejecucion = nuevoEstado;
  otAplicarEstadoVisualFila(actividadId, nuevoEstado === 'completada');
  otActualizarResumenProgreso();

  otGuardandoIds.add(actividadId);
  otSetControlesDisabled(actividadId, true);
  const guardandoEl = document.getElementById(`ot-guardando-${actividadId}`);
  if (guardandoEl) guardandoEl.style.display = 'block';

  try {
    // Solo estado_ejecucion en el SET: es la única columna que el GRANT de
    // columna (2026-07-22_mantencion_actividades_rls_update.sql) permite
    // tocar desde el navegador, junto con actualizado_por/actualizado_en,
    // que el trigger ya existente completa solo.
    const { data, error } = await supabaseAYCA
      .from('mantencion_actividades')
      .update({ estado_ejecucion: nuevoEstado })
      .eq('id', actividadId)
      .select('id, estado_ejecucion');

    if (error) {
      console.error('otToggleActividad — error de Supabase:', error);
      throw error;
    }

    if (!data || !data.length) {
      // 0 filas afectadas: RLS/columna rechazó el cambio en silencio (no es
      // un "error" de Postgres) — no autorizado sobre esta mantención, o
      // la mantención ya está cerrada. Se trata igual como un fallo.
      console.error('otToggleActividad — 0 filas afectadas (RLS rechazó el UPDATE):', { actividadId, nuevoEstado });
      throw new Error('No tienes permiso sobre esta mantención, o ya está cerrada.');
    }

    // Confirmar el estado local con lo que realmente quedó guardado.
    actividad.estado_ejecucion = data[0].estado_ejecucion;
  } catch (e) {
    console.error('otToggleActividad:', e);
    // Revertir: estado local, checkbox y estilo visual vuelven a lo anterior.
    actividad.estado_ejecucion = estadoAnterior;
    checkboxEl.checked = estadoAnterior === 'completada';
    otAplicarEstadoVisualFila(actividadId, estadoAnterior === 'completada');
    otActualizarResumenProgreso();
    if (errorEl) {
      errorEl.textContent = 'No se pudo guardar: ' + e.message;
      errorEl.style.display = 'block';
    }
  } finally {
    otGuardandoIds.delete(actividadId);
    otSetControlesDisabled(actividadId, false);
    if (guardandoEl) guardandoEl.style.display = 'none';
  }
}

// ── Guardar el resultado corporativo ('si'/'no'/'na') de una actividad.
//    Completamente independiente de estado_ejecucion: no lo lee, no lo
//    modifica, no reutiliza su checkbox ni su lógica. ──
async function otGuardarResultado(actividadId, valor, botonEl) {
  if (otGuardandoIds.has(actividadId)) {
    // Ya hay un guardado en curso sobre esta fila: no hacer nada más
    // (el botón, a diferencia de un radio nativo, no cambia de estado solo).
    return;
  }

  const actividad = otActividades.find(a => a.id === actividadId);
  if (!actividad) return;

  const resultadoAnterior = actividad.resultado;
  const errorEl = document.getElementById(`ot-error-resultado-${actividadId}`);
  if (errorEl) { errorEl.style.display = 'none'; errorEl.textContent = ''; }

  // Optimista: colorear de inmediato el botón elegido (verde/rojo/gris),
  // sin esperar la respuesta de red.
  actividad.resultado = valor;
  otMarcarBotonResultado(actividadId, valor);

  otGuardandoIds.add(actividadId);
  otSetControlesDisabled(actividadId, true);
  const guardandoEl = document.getElementById(`ot-guardando-resultado-${actividadId}`);
  if (guardandoEl) guardandoEl.style.display = 'inline';

  try {
    // Solo "resultado" en el SET — columna incluida en el GRANT ampliado
    // (2026-07-30_mantencion_actividades_rls_update_resultado.sql).
    // actualizado_por/actualizado_en los completa el trigger existente.
    const { data, error } = await supabaseAYCA
      .from('mantencion_actividades')
      .update({ resultado: valor })
      .eq('id', actividadId)
      .select('id, resultado');

    if (error) {
      console.error('otGuardarResultado — error de Supabase:', error);
      throw error;
    }

    if (!data || !data.length) {
      console.error('otGuardarResultado — 0 filas afectadas (RLS rechazó el UPDATE):', { actividadId, valor });
      throw new Error('No tienes permiso sobre esta mantención, o ya está cerrada.');
    }

    actividad.resultado = data[0].resultado;
  } catch (e) {
    console.error('otGuardarResultado:', e);
    actividad.resultado = resultadoAnterior;
    otMarcarBotonResultado(actividadId, resultadoAnterior);
    if (errorEl) {
      errorEl.textContent = 'No se pudo guardar: ' + e.message;
      errorEl.style.display = 'block';
    }
  } finally {
    otGuardandoIds.delete(actividadId);
    otSetControlesDisabled(actividadId, false);
    if (guardandoEl) guardandoEl.style.display = 'none';
  }
}

// ── Guardar el N° de observación de una actividad — se dispara al perder
//    el foco (onblur), no en cada tecla. Completamente independiente de
//    estado_ejecucion y de resultado. ──
async function otGuardarObservacion(actividadId, inputEl) {
  if (otGuardandoIds.has(actividadId)) {
    const actividadEnCurso = otActividades.find(a => a.id === actividadId);
    inputEl.value = actividadEnCurso ? (actividadEnCurso.num_observacion || '') : '';
    return;
  }

  const actividad = otActividades.find(a => a.id === actividadId);
  if (!actividad) return;

  const nuevoValor = inputEl.value.trim() || null;
  const valorAnterior = actividad.num_observacion || null;
  if (nuevoValor === valorAnterior) return; // sin cambios reales, no gastar una llamada a Supabase

  const errorEl = document.getElementById(`ot-error-obs-${actividadId}`);
  if (errorEl) { errorEl.style.display = 'none'; errorEl.textContent = ''; }

  actividad.num_observacion = nuevoValor; // optimista

  otGuardandoIds.add(actividadId);
  otSetControlesDisabled(actividadId, true);
  const guardandoEl = document.getElementById(`ot-guardando-obs-${actividadId}`);
  if (guardandoEl) guardandoEl.style.display = 'inline';

  try {
    // Solo "num_observacion" en el SET — misma columna incluida en el
    // GRANT ampliado; actualizado_por/actualizado_en los completa el trigger.
    const { data, error } = await supabaseAYCA
      .from('mantencion_actividades')
      .update({ num_observacion: nuevoValor })
      .eq('id', actividadId)
      .select('id, num_observacion');

    if (error) {
      console.error('otGuardarObservacion — error de Supabase:', error);
      throw error;
    }

    if (!data || !data.length) {
      console.error('otGuardarObservacion — 0 filas afectadas (RLS rechazó el UPDATE):', { actividadId, nuevoValor });
      throw new Error('No tienes permiso sobre esta mantención, o ya está cerrada.');
    }

    actividad.num_observacion = data[0].num_observacion;
    inputEl.value = actividad.num_observacion || '';
  } catch (e) {
    console.error('otGuardarObservacion:', e);
    actividad.num_observacion = valorAnterior;
    inputEl.value = valorAnterior || '';
    if (errorEl) {
      errorEl.textContent = 'No se pudo guardar: ' + e.message;
      errorEl.style.display = 'block';
    }
  } finally {
    otGuardandoIds.delete(actividadId);
    otSetControlesDisabled(actividadId, false);
    if (guardandoEl) guardandoEl.style.display = 'none';
  }
}

// ═══════════════════════════════════════════
// GENERADOR PDF — ANEXO A1 (réplica del formato corporativo)
// ═══════════════════════════════════════════
//
// Solo lectura: usa otMantencionActual y otActividades, ya cacheados por
// otCargarEncabezado()/otCargarActividades(). No ejecuta ningún select,
// update, insert ni delete adicional contra Supabase.
//
// Réplica estricta en blanco y negro (sin el banner azul que usan los
// demás PDF de la app — pdf.js/ventilador.js/carbones.js): encabezado de
// texto simple, líneas negras, sin relleno de color en encabezados de
// columna ni en filas de Área/Sección. Reutiliza únicamente el mecanismo
// técnico de jsPDF + autoTable ya cargado en index.html.

// ── Encabezado corporativo (ANEXO A1 / título / código / línea), marca de
//    agua y pie legal — se dibuja una vez a mano para la página 1, y luego
//    en cada página que autoTable cree internamente vía didDrawPage. ──
function _otDibujarEncabezadoYPiePdf(doc, margen, anguloMarcaAgua) {
  const anchoPagina = doc.internal.pageSize.getWidth();
  const altoPagina  = doc.internal.pageSize.getHeight();

  // Encabezado — texto negro sobre blanco, sin relleno de color.
  doc.setTextColor(0, 0, 0);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.text('ANEXO A1', margen.left, 10);

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  doc.text('ACTIVIDADES REALIZADAS EN MOTOR', margen.left, 16);

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.text('Código: PT-1001', anchoPagina - margen.right, 10, { align: 'right' });

  doc.setDrawColor(0, 0, 0);
  doc.setLineWidth(0.4);
  doc.line(margen.left, 20, anchoPagina - margen.right, 20);

  // Marca de agua — dibujada ANTES de que autoTable pinte las filas de esta
  // página (didDrawPage se dispara al iniciar la página, previo a las filas
  // de esa página), para que el texto de la tabla quede encima sin taparla.
  doc.saveGraphicsState();
  doc.setGState(new doc.GState({ opacity: 0.06 }));
  doc.setTextColor(11, 49, 88);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(46);
  doc.text('ACCIONAMIENTO Y CONTROL AUTOMÁTICO', anchoPagina / 2, altoPagina / 2, {
    align: 'center',
    angle: anguloMarcaAgua
  });
  doc.restoreGraphicsState();

  // Pie legal — sin numeración de página, sin "AYCA Smart Maintenance"
  // (a diferencia del pie que usan los demás PDF de la app).
  doc.setTextColor(0, 0, 0);
  doc.setDrawColor(0, 0, 0);
  doc.setLineWidth(0.3);
  doc.line(margen.left, altoPagina - 16, anchoPagina - margen.right, altoPagina - 16);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7);
  doc.text(
    [
      'Servicios en Accionamiento y Control Automático SpA. RUT 76.845.043-9',
      'Av. Pdte. Kennedy Lateral 7900, Oficina 502, Vitacura, Santiago, Chile. Teléfono +569 23266267'
    ],
    anchoPagina / 2, altoPagina - 11,
    { align: 'center' }
  );
}

// ── Genera y descarga el Anexo A1 en PDF con las 125 actividades de la
//    mantención actualmente abierta. Solo lectura — ningún UPDATE/INSERT/DELETE. ──
async function otGenerarAnexoA1Pdf() {
  if (typeof window.jspdf === 'undefined') {
    alert('No se pudo generar el PDF: la librería jsPDF no está disponible.');
    console.error('otGenerarAnexoA1Pdf: window.jspdf no está definido.');
    return;
  }
  if (!otMantencionActual || !otActividades.length) {
    alert('No hay datos cargados de la Orden de Trabajo todavía. Espera a que termine de cargar antes de generar el PDF.');
    return;
  }

  const btn = document.getElementById('otBtnPdf');
  if (btn) { btn.disabled = true; btn.textContent = 'Generando PDF...'; }

  try {
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF('p', 'mm', 'a4');

    // Márgenes reservados para que el encabezado/pie repetidos nunca se
    // superpongan con la tabla — mismos valores aprobados, ajustables tras
    // comparación visual con el original.
    const MARGEN = { top: 32, bottom: 18, left: 8, right: 8 };
    const ANGULO_MARCA_AGUA = 60; // más vertical que 45°; ajustar tras revisión visual
    const anchoPagina = doc.internal.pageSize.getWidth();
    const altoPagina  = doc.internal.pageSize.getHeight();
    const COLS = ['#', 'Actividad', 'Sí', 'No', 'N/A', 'N° Obs.'];

    // Suprime el texto horizontal por defecto de las 4 columnas angostas
    // del encabezado (Sí/No/N/A/N° Obs.) — se redibuja manualmente rotado
    // en didDrawCell. La columna "Actividad" (índice 1) y "#" (índice 0)
    // se muestran horizontales, como en el documento original.
    const didParseCell = (data) => {
      if (data.section === 'head' && data.column.index >= 2) {
        data.cell.text = [];
      }
    };
    const didDrawCell = (data) => {
      if (data.section === 'head' && data.column.index >= 2) {
        const texto = COLS[data.column.index];
        const cx = data.cell.x + data.cell.width / 2;
        const cy = data.cell.y + data.cell.height / 2;
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(7);
        doc.setTextColor(0, 0, 0);
        doc.text(texto, cx, cy, { align: 'center', baseline: 'middle', angle: 90 });
      }
    };
    // autoTable dispara didDrawPage solo cuando ÉL crea una página nueva a
    // mitad de una Sección larga — para la página 1 y para los saltos de
    // página manuales entre Secciones se llama aparte, más abajo.
    const didDrawPage = () => _otDibujarEncabezadoYPiePdf(doc, MARGEN, ANGULO_MARCA_AGUA);

    // Página 1: dibujar encabezado/pie a mano (didDrawPage no se dispara
    // retroactivamente para la primera página).
    _otDibujarEncabezadoYPiePdf(doc, MARGEN, ANGULO_MARCA_AGUA);

    // "1. Motor" — título raíz fijo del formato, fuera de cualquier tabla,
    // se imprime una sola vez al inicio del documento.
    let y = 26;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(13);
    doc.setTextColor(0, 0, 0);
    doc.text('1. Motor', MARGEN.left, y);
    y += 6;

    const grupos = _otAgruparPorAreaSeccion(otActividades);

    let indiceArea = 0;
    for (const [areaNombre, secciones] of grupos) {
      indiceArea++;

      // Evitar título de Área huérfano: si no alcanza el título + al menos
      // una línea, saltar de página ANTES de escribirlo. Control manual
      // entre bloques (no dentro de un hook interno de autoTable).
      if (y > altoPagina - MARGEN.bottom - 20) {
        doc.addPage();
        _otDibujarEncabezadoYPiePdf(doc, MARGEN, ANGULO_MARCA_AGUA);
        y = MARGEN.top;
      }

      doc.setFont('helvetica', 'bold');
      doc.setFontSize(11);
      doc.setTextColor(0, 0, 0);
      doc.text(`1.${indiceArea}  ${areaNombre}`, MARGEN.left, y);
      doc.setDrawColor(0, 0, 0);
      doc.setLineWidth(0.3);
      doc.line(MARGEN.left, y + 1.5, anchoPagina - MARGEN.right, y + 1.5);
      y += 7;

      let indiceSeccion = 0;
      for (const [seccionNombre, filas] of secciones) {
        indiceSeccion++;

        // Evitar título de Sección huérfano — misma técnica: verificar
        // espacio restante y saltar de página a mano antes de escribir el
        // título, no forzando addPage() desde didParseCell.
        if (y > altoPagina - MARGEN.bottom - 25) {
          doc.addPage();
          _otDibujarEncabezadoYPiePdf(doc, MARGEN, ANGULO_MARCA_AGUA);
          y = MARGEN.top;
        }

        doc.setFont('helvetica', 'bold');
        doc.setFontSize(10);
        doc.setTextColor(0, 0, 0);
        doc.text(`1.${indiceArea}.${indiceSeccion}  ${seccionNombre}`, MARGEN.left, y);
        doc.setLineWidth(0.2);
        doc.line(MARGEN.left, y + 1.2, anchoPagina - MARGEN.right, y + 1.2);
        y += 5;

        // Numeración visual 1,2,3... reiniciada en esta Sección — "orden"
        // solo se usó para el ORDER BY de la consulta; codigo_actividad
        // nunca se imprime como número de fila.
        const cuerpo = filas.map((a, i) => [
          String(i + 1),
          a.descripcion || a.codigo_actividad || '—',
          a.resultado === 'si' ? 'X' : '',
          a.resultado === 'no' ? 'X' : '',
          a.resultado === 'na' ? 'X' : '',
          a.num_observacion || ''
        ]);

        doc.autoTable({
          startY: y,
          head: [COLS],
          body: cuerpo,
          margin: MARGEN,
          theme: 'grid', // sin franjas de color alternadas
          styles: { fontSize: 8, textColor: [0, 0, 0], lineColor: [0, 0, 0], lineWidth: 0.15, cellPadding: 1.5 },
          headStyles: { fillColor: false, textColor: [0, 0, 0], lineColor: [0, 0, 0], lineWidth: 0.15 },
          columnStyles: {
            0: { cellWidth: 10, halign: 'center' },
            1: { cellWidth: 124, halign: 'left' },
            2: { cellWidth: 15, halign: 'center' },
            3: { cellWidth: 15, halign: 'center' },
            4: { cellWidth: 15, halign: 'center' },
            5: { cellWidth: 15, halign: 'center' }
          },
          didParseCell,
          didDrawCell,
          didDrawPage
        });

        y = doc.lastAutoTable.finalY + 4;
      }
    }

    const numeroLimpio = (otMantencionActual.numero || 'SIN_NUMERO').replace(/[^A-Za-z0-9-]/g, '_');
    doc.save(`${numeroLimpio}_Anexo_A1_Actividades_Motor.pdf`);
  } catch (e) {
    console.error('otGenerarAnexoA1Pdf:', e);
    alert('No se pudo generar el PDF: ' + e.message);
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = '📄 Generar Anexo A1 PDF'; }
  }
}
