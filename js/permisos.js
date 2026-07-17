// ===============================
// AYCA SMART MAINTENANCE — PERMISOS.JS
// Módulo único de perfiles, roles, menú y control de acceso a pantallas.
// Requiere: supabaseAYCA (database.js), mostrar() (app.js).
// ===============================

const ROLES_AYCA = ['tecnico', 'supervisor', 'planificador', 'bodega', 'gerencia', 'administrador'];

// Pantallas siempre accesibles para cualquier usuario autenticado (incluso sin rol asignado)
const PANTALLAS_LIBRES = ['login', 'panel'];

// Grupos de roles reutilizados en el mapeo de esta fase de transición
const ROLES_PROTOCOLOS = ['tecnico', 'supervisor', 'planificador', 'gerencia', 'administrador'];
const ROLES_BODEGA     = ['bodega', 'administrador'];

// ── Única fuente de verdad del menú: genera grid del panel + sidebar de escritorio ──
const MENU_CONFIG = [
  { id: 'panel',          icon: '🏠', label: 'Panel principal', pantalla: 'panel',             roles: ROLES_AYCA,       en: ['sidebar'] },
  { id: 'nuevoProtocolo', icon: '📋', label: 'Nuevo Protocolo', pantalla: 'seleccionProtocolo', roles: ROLES_PROTOCOLOS, en: ['grid', 'sidebar'] },
  { id: 'misProtocolos',  icon: '📑', label: 'Mis Protocolos',  pantalla: 'protocolos',         roles: ROLES_PROTOCOLOS, en: ['grid', 'sidebar'] },
  // Tarjetas sin pantalla asociada todavía (igual que en el HTML original: visibles, sin onclick)
  { id: 'historial',      icon: '🕘', label: 'Historial',       pantalla: null,                 roles: ROLES_AYCA,       en: ['grid'] },
  { id: 'motores',        icon: '⚙️', label: 'Motores',         pantalla: null,                 roles: ROLES_AYCA,       en: ['grid'] },
  { id: 'herramientasCD', icon: '🛠️', label: 'Herramientas',    pantalla: 'herramientas',       roles: ROLES_PROTOCOLOS, en: ['grid'] },
  { id: 'sincronizacion', icon: '🔄', label: 'Sincronización',  pantalla: null,                 roles: ROLES_AYCA,       en: ['grid'] },
  { id: 'bodega',         icon: '📦', label: 'Bodega',          pantalla: 'bodega',             roles: ROLES_BODEGA,     en: ['grid', 'sidebar'] },

  // ── Accesos "en preparación" del panel de inicio por rol (Paso 1C) ──
  // Todos abren la misma pantalla reutilizable #provisional con texto propio.
  { id: 'sup_nuevaMantencion', icon: '🆕', label: 'Nueva mantención',        panelRol: 'supervisor',    provTitulo: 'Nueva mantención',        provDesc: 'Creación de mantenciones: módulo en preparación.',                     roles: ['supervisor'],    en: ['home'] },
  { id: 'sup_mantActivas',     icon: '📈', label: 'Mantenciones activas',    panelRol: 'supervisor',    provTitulo: 'Mantenciones activas',     provDesc: 'Seguimiento de mantenciones en curso: módulo en preparación.',         roles: ['supervisor'],    en: ['home'] },
  { id: 'sup_personal',        icon: '👷', label: 'Personal asignado',       panelRol: 'supervisor',    provTitulo: 'Personal asignado',        provDesc: 'Asignación de técnicos a la mantención: módulo en preparación.',       roles: ['supervisor'],    en: ['home'] },
  { id: 'sup_anexoA1',         icon: '📄', label: 'Actividades Anexo A1',    panelRol: 'supervisor',    provTitulo: 'Actividades del Anexo A1', provDesc: 'Selección y aprobación de actividades del Anexo A1: módulo en preparación.', roles: ['supervisor'], en: ['home'] },
  { id: 'sup_hallazgos',       icon: '⚠️', label: 'Hallazgos',               panelRol: 'supervisor',    provTitulo: 'Hallazgos',                provDesc: 'Registro y revisión de hallazgos: módulo en preparación.',             roles: ['supervisor'],    en: ['home'] },
  { id: 'sup_conclusiones',    icon: '✅', label: 'Conclusiones',            panelRol: 'supervisor',    provTitulo: 'Conclusiones',             provDesc: 'Revisión y aprobación de conclusiones: módulo en preparación.',        roles: ['supervisor'],    en: ['home'] },
  { id: 'sup_informes',        icon: '📘', label: 'Informes',                panelRol: 'supervisor',    provTitulo: 'Informes',                 provDesc: 'Informe de entrega e informe final: módulo en preparación.',           roles: ['supervisor'],    en: ['home'] },

  { id: 'pla_porPlanificar',   icon: '🗓️', label: 'Mantenciones por planificar', panelRol: 'planificador', provTitulo: 'Mantenciones por planificar', provDesc: 'Mantenciones a la espera de hoja de tiempo: módulo en preparación.', roles: ['planificador'], en: ['home'] },
  { id: 'pla_hojaTiempo',      icon: '⏱️', label: 'Hoja de tiempo',          panelRol: 'planificador',  provTitulo: 'Hoja de tiempo',           provDesc: 'Definición de fechas y duración de actividades: módulo en preparación.', roles: ['planificador'], en: ['home'] },
  { id: 'pla_gantt',           icon: '📊', label: 'Carta Gantt',             panelRol: 'planificador',  provTitulo: 'Carta Gantt',              provDesc: 'Carta Gantt de la mantención: módulo en preparación.',                 roles: ['planificador'], en: ['home'] },
  { id: 'pla_recursos',        icon: '🧰', label: 'Recursos',                panelRol: 'planificador',  provTitulo: 'Recursos',                 provDesc: 'Asignación de tiempos y recursos: módulo en preparación.',             roles: ['planificador'], en: ['home'] },
  { id: 'pla_desviaciones',    icon: '📉', label: 'Desviaciones',            panelRol: 'planificador',  provTitulo: 'Desviaciones',             provDesc: 'Causas de desviación de tiempo: módulo en preparación.',               roles: ['planificador'], en: ['home'] },
  { id: 'pla_cumplimiento',    icon: '🎯', label: 'Cumplimiento',            panelRol: 'planificador',  provTitulo: 'Cumplimiento',             provDesc: 'Avance programado vs. avance real: módulo en preparación.',            roles: ['planificador'], en: ['home'] },

  { id: 'ger_mantActivas',     icon: '📈', label: 'Mantenciones activas',    panelRol: 'gerencia',      provTitulo: 'Mantenciones activas',     provDesc: 'Sin datos disponibles. Módulo en preparación.', roles: ['gerencia'], en: ['home'] },
  { id: 'ger_cumplimiento',    icon: '🎯', label: 'Cumplimiento',            panelRol: 'gerencia',      provTitulo: 'Cumplimiento',             provDesc: 'Sin datos disponibles. Módulo en preparación.', roles: ['gerencia'], en: ['home'] },
  { id: 'ger_horasHombre',     icon: '⏳', label: 'Horas hombre',            panelRol: 'gerencia',      provTitulo: 'Horas hombre',             provDesc: 'Sin datos disponibles. Módulo en preparación.', roles: ['gerencia'], en: ['home'] },
  { id: 'ger_hallazgosCrit',   icon: '⚠️', label: 'Hallazgos críticos',      panelRol: 'gerencia',      provTitulo: 'Hallazgos críticos',       provDesc: 'Sin datos disponibles. Módulo en preparación.', roles: ['gerencia'], en: ['home'] },
  { id: 'ger_informes',        icon: '📘', label: 'Informes',                panelRol: 'gerencia',      provTitulo: 'Informes',                 provDesc: 'Sin datos disponibles. Módulo en preparación.', roles: ['gerencia'], en: ['home'] },
  { id: 'ger_historialEquipos',icon: '🗄️', label: 'Historial de equipos',    panelRol: 'gerencia',      provTitulo: 'Historial de equipos',     provDesc: 'Sin datos disponibles. Módulo en preparación.', roles: ['gerencia'], en: ['home'] },

  { id: 'adm_usuarios',        icon: '👤', label: 'Usuarios',                panelRol: 'administrador', provTitulo: 'Usuarios',                 provDesc: 'Administración de usuarios: módulo en preparación.',    roles: ['administrador'], en: ['home'] },
  { id: 'adm_roles',           icon: '🛡️', label: 'Roles',                   panelRol: 'administrador', provTitulo: 'Roles',                    provDesc: 'Administración de roles: módulo en preparación.',       roles: ['administrador'], en: ['home'] },
  { id: 'adm_configuracion',   icon: '⚙️', label: 'Configuración',           panelRol: 'administrador', provTitulo: 'Configuración',            provDesc: 'Parámetros de la aplicación: módulo en preparación.',   roles: ['administrador'], en: ['home'] },
  { id: 'adm_clientes',        icon: '🏢', label: 'Clientes',                panelRol: 'administrador', provTitulo: 'Clientes',                 provDesc: 'Catálogo de clientes: módulo en preparación.',           roles: ['administrador'], en: ['home'] },
  { id: 'adm_faenas',          icon: '⛏️', label: 'Faenas',                  panelRol: 'administrador', provTitulo: 'Faenas',                   provDesc: 'Catálogo de faenas: módulo en preparación.',             roles: ['administrador'], en: ['home'] },
  { id: 'adm_equipos',         icon: '🏭', label: 'Equipos',                 panelRol: 'administrador', provTitulo: 'Equipos',                  provDesc: 'Catálogo de equipos: módulo en preparación.',            roles: ['administrador'], en: ['home'] },
  { id: 'adm_plantillas',      icon: '🧩', label: 'Plantillas',              panelRol: 'administrador', provTitulo: 'Plantillas',               provDesc: 'Plantillas de actividades y protocolos: módulo en preparación.', roles: ['administrador'], en: ['home'] }
];

// ── Mapa pantalla → roles permitidos (incluye sub-pantallas no listadas en el menú) ──
const PANTALLA_ROLES = {
  login: ROLES_AYCA,
  panel: ROLES_AYCA,

  seleccionProtocolo: ROLES_PROTOCOLOS,
  protocolos:          ROLES_PROTOCOLOS,

  // Mediciones Dieléctricas
  dielectrico: ROLES_PROTOCOLOS,
  estator1:    ROLES_PROTOCOLOS,
  estator2:    ROLES_PROTOCOLOS,
  rotorDiel:   ROLES_PROTOCOLOS,

  // Control Dimensional
  datos:        ROLES_PROTOCOLOS,
  herramientas: ROLES_PROTOCOLOS,
  medicion:     ROLES_PROTOCOLOS,
  salida:       ROLES_PROTOCOLOS,
  resumen:      ROLES_PROTOCOLOS,

  // Carbones
  carbonesDatos:   ROLES_PROTOCOLOS,
  carbonesLargo:   ROLES_PROTOCOLOS,
  carbonesTension: ROLES_PROTOCOLOS,

  // Ventilador
  ventiladorDatos: ROLES_PROTOCOLOS,
  ventiladorPre:   ROLES_PROTOCOLOS,
  ventiladorPost:  ROLES_PROTOCOLOS,

  // Bodega
  'bodega':            ROLES_BODEGA,
  'bodega-registrar':  ROLES_BODEGA,
  'bodega-inventario': ROLES_BODEGA,
  'bodega-entregar':   ROLES_BODEGA,
  'bodega-devolver':   ROLES_BODEGA,
  'bodega-reporte':    ROLES_BODEGA,
  'bodega-importar':   ROLES_BODEGA,

  // Pantalla provisional compartida (Paso 1C) — sin datos sensibles, abierta a cualquier rol
  provisional: ROLES_AYCA
};

// ── Tarjetas de estado vacías del panel de inicio del Técnico (Paso 1C) ──
const PANEL_ESTADO_TECNICO = [
  { icon: '🗂️', titulo: 'Mis mantenciones asignadas', mensaje: 'No tienes mantenciones asignadas.' },
  { icon: '⏳', titulo: 'Protocolos pendientes',        mensaje: 'No tienes mantenciones asignadas.' },
  { icon: '🔧', titulo: 'Protocolos en proceso',        mensaje: 'No tienes mantenciones asignadas.' },
  { icon: '✅', titulo: 'Protocolos completados',       mensaje: 'No tienes mantenciones asignadas.' },
  { icon: '📷', titulo: 'Informe fotográfico',          mensaje: 'No tienes mantenciones asignadas.' },
  { icon: '⚠️', titulo: 'Hallazgos reportados',         mensaje: 'No tienes mantenciones asignadas.' }
];

// ── Perfil del usuario autenticado ──
let perfilActual = { nombre: '', roles: [] };

async function cargarPerfilActual(userId) {
  perfilActual = { nombre: '', roles: [] };
  if (!userId || typeof supabaseAYCA === 'undefined') return perfilActual;

  try {
    const [{ data: perfil }, { data: roles }] = await Promise.all([
      supabaseAYCA.from('perfiles_ayca').select('nombre').eq('id', userId).maybeSingle(),
      supabaseAYCA.from('usuario_roles').select('rol').eq('usuario_id', userId)
    ]);
    perfilActual.nombre = perfil?.nombre || '';
    perfilActual.roles  = (roles || []).map(r => r.rol);
  } catch (e) {
    // Tablas nuevas aún no creadas o sin conexión: degradar a "sin rol", no romper el login.
    console.warn('No se pudo cargar el perfil de roles (¿ya ejecutaste el SQL de perfiles?):', e.message);
  }

  return perfilActual;
}

// ── ¿El usuario actual puede acceder a esta pantalla? ──
function tieneAcceso(idPantalla) {
  if (PANTALLAS_LIBRES.includes(idPantalla)) return true;
  const permitidos = PANTALLA_ROLES[idPantalla];
  if (!permitidos) return true; // pantalla sin restricción definida: no bloquear por defecto
  return (perfilActual.roles || []).some(r => permitidos.includes(r));
}

// ── Reconstruye el grid del panel y el sidebar de escritorio según el rol ──
function renderMenus() {
  const grid    = document.getElementById('menuGrid');
  const sidebar = document.getElementById('sidebarNav');

  const visibles = MENU_CONFIG.filter(item =>
    (perfilActual.roles || []).some(r => item.roles.includes(r))
  );

  if (grid) {
    const items = visibles.filter(i => i.en.includes('grid'));
    grid.innerHTML = items.length
      ? items.map(i => `<div class="modulo"${i.pantalla ? ` onclick="mostrar('${i.pantalla}')"` : ''}>${i.icon}<br><b>${i.label}</b></div>`).join('')
      : '<p style="grid-column:1/-1;color:#6b7280;text-align:center;padding:12px">Tu cuenta no tiene un rol asignado todavía.<br>Contacta al administrador.</p>';
  }

  if (sidebar) {
    const items = visibles.filter(i => i.en.includes('sidebar'));
    sidebar.innerHTML = items.map(i =>
      `<div class="sidebar-item"${i.pantalla ? ` onclick="mostrar('${i.pantalla}')"` : ''}><span class="si-icon">${i.icon}</span> ${i.label}</div>`
    ).join('');
  }
}

// ===============================
// PANEL DE INICIO POR ROL (Paso 1C)
// ===============================

function _escJs(s) { return String(s).replace(/'/g, "\\'"); }

function _etiquetaRol(rol) {
  return {
    tecnico: 'Técnico', supervisor: 'Supervisor', planificador: 'Planificador',
    bodega: 'Bodega', gerencia: 'Gerencia', administrador: 'Administrador'
  }[rol] || rol;
}

// ── Abre la pantalla provisional compartida con el texto del módulo elegido ──
function abrirProvisional(titulo, descripcion, rol) {
  const tEl = document.getElementById('prov-titulo');
  const dEl = document.getElementById('prov-desc');
  const rEl = document.getElementById('prov-rol');
  if (tEl) tEl.textContent = titulo || '';
  if (dEl) dEl.textContent = descripcion || '';
  if (rEl) rEl.textContent = rol ? ('Rol responsable: ' + rol) : '';
  mostrar('provisional');
}

function _tarjetaMetricaBodega(icon, titulo, valor) {
  const mostrarValor = (valor === null || valor === undefined) ? 'Sin datos disponibles' : valor;
  return `<div class="card" style="text-align:center;padding:14px">
    <div style="font-size:22px">${icon}</div>
    <div style="font-size:12px;color:#6b7280;margin:4px 0">${titulo}</div>
    <div style="font-weight:bold;color:#0b3158">${mostrarValor}</div>
  </div>`;
}

// ── Resumen de Bodega con datos reales (solo lectura sobre "herramientas"; no toca bodega.js) ──
async function renderResumenBodega() {
  const cont = document.getElementById('resumenBodega');
  if (!cont) return;

  let disponibles = null, entregadas = null, pendientes = null, critico = null;

  if (typeof supabaseAYCA !== 'undefined') {
    try {
      const { data, error } = await supabaseAYCA.from('herramientas').select('estado, fecha_vencimiento');
      if (error) throw error;
      const items = data || [];
      if (items.length) {
        disponibles = items.filter(h => h.estado === 'Disponible').length;
        entregadas  = items.filter(h => h.estado === 'Asignada').length;
        pendientes  = entregadas; // en este esquema, "Asignada" = actualmente fuera de bodega
        critico     = items.filter(h => {
          if (!h.fecha_vencimiento) return false;
          const dias = Math.ceil((new Date(h.fecha_vencimiento) - new Date()) / 86400000);
          return dias <= 30;
        }).length;
      }
    } catch (e) {
      console.warn('No se pudo cargar el resumen de bodega:', e.message);
    }
  }

  cont.innerHTML = `<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
    ${_tarjetaMetricaBodega('✅', 'Herramientas disponibles', disponibles)}
    ${_tarjetaMetricaBodega('🚚', 'Herramientas entregadas', entregadas)}
    ${_tarjetaMetricaBodega('↩️', 'Pendientes de devolución', pendientes)}
    ${_tarjetaMetricaBodega('⚠️', 'Stock crítico (calibración)', critico)}
  </div>`;
}

// ── Arma el panel de inicio combinando los mecanismos según los roles del usuario ──
function renderPanelInicio() {
  const cont = document.getElementById('panelInicio');
  if (!cont) return;

  const roles = perfilActual.roles || [];
  if (!roles.length) { cont.innerHTML = ''; return; }

  let html = '';

  if (roles.includes('tecnico')) {
    html += '<h3 style="margin:10px 0 6px">Mi panel — Técnico</h3>';
    html += '<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:14px">';
    html += PANEL_ESTADO_TECNICO.map(c => `
      <div class="card" style="text-align:center;padding:14px">
        <div style="font-size:22px">${c.icon}</div>
        <div style="font-size:12px;color:#6b7280;margin:4px 0">${c.titulo}</div>
        <div style="font-size:12px;color:#9ca3af">${c.mensaje}</div>
      </div>`).join('');
    html += '</div>';
  }

  ['supervisor', 'planificador', 'gerencia', 'administrador'].forEach(rol => {
    if (!roles.includes(rol)) return;
    const items = MENU_CONFIG.filter(i => i.panelRol === rol);
    if (!items.length) return;
    html += `<h3 style="margin:10px 0 6px">Mi panel — ${_etiquetaRol(rol)}</h3>`;
    html += '<div class="grid" style="margin-bottom:14px">';
    html += items.map(i =>
      `<div class="modulo" onclick="abrirProvisional('${_escJs(i.provTitulo)}','${_escJs(i.provDesc)}','${_escJs(_etiquetaRol(rol))}')">${i.icon}<br><b>${i.label}</b></div>`
    ).join('');
    html += '</div>';
  });

  if (roles.includes('bodega')) {
    html += '<h3 style="margin:10px 0 6px">Resumen de Bodega</h3>';
    html += '<div id="resumenBodega"></div>';
  }

  cont.innerHTML = html;

  if (roles.includes('bodega') && typeof renderResumenBodega === 'function') {
    renderResumenBodega();
  }
}
