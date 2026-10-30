// ===============================
// AYCA SMART MAINTENANCE — USUARIOS.JS
// Administración de usuarios (FASE 3.2) — 3.2B: lista.
//                                   3.2C: asignación de roles (admin).
// Requiere: supabaseAYCA (database.js), _etiquetaRol()/ROLES_AYCA (permisos.js).
// Tablas Supabase: perfiles_ayca, usuario_roles, evento_personal_asignado.
// No consulta auth.users. No usa Admin API, service_role ni Edge Functions.
// ===============================

let _usuariosDatosCache = []; // { id, nombre, activo, roles, rolesDesconocidos, disponible }

// ── Cargar perfiles + roles + disponibilidad y renderizar la lista ──
async function usuariosCargarLista() {
  const cont  = document.getElementById('usuariosListaCont');
  const aviso = document.getElementById('usu_aviso');
  if (aviso) { aviso.style.display = 'none'; aviso.textContent = ''; }
  if (!cont) return;

  cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Cargando usuarios...</p>';

  // 1) perfiles_ayca — si esta falla, no hay nada válido que mostrar.
  let perfiles;
  try {
    const { data, error } = await supabaseAYCA
      .from('perfiles_ayca')
      .select('id, nombre, activo')
      .order('nombre');
    if (error) throw error;
    perfiles = data || [];
  } catch (e) {
    console.error('usuariosCargarLista (perfiles_ayca):', e);
    cont.innerHTML = `<p style="color:#dc2626;padding:12px">Error al cargar usuarios: ${e.message}</p>`;
    _usuariosDatosCache = [];
    return;
  }

  const avisos = [];

  // 2) usuario_roles — best-effort: si falla, los roles quedan "desconocidos"
  //    (no se confunde con "el usuario realmente no tiene ningún rol").
  let rolesPorUsuario = {};
  try {
    const { data, error } = await supabaseAYCA.from('usuario_roles').select('usuario_id, rol');
    if (error) throw error;
    (data || []).forEach(r => { (rolesPorUsuario[r.usuario_id] ||= []).push(r.rol); });
  } catch (e) {
    console.warn('usuariosCargarLista (usuario_roles):', e.message);
    avisos.push('No se pudieron cargar los roles de los usuarios.');
    rolesPorUsuario = null;
  }

  // 3) evento_personal_asignado — best-effort: "vigente" = estado_asignacion
  //    <> 'liberado' (mismo criterio que fn_es_tecnico_vigente_evento, 2D-09).
  //    Vocabulario real de estado_asignacion (2D-03): propuesto, confirmado,
  //    en_terreno, liberado. Si falla, disponibilidad queda "—" (desconocida).
  let noDisponibles = null;
  try {
    const { data, error } = await supabaseAYCA
      .from('evento_personal_asignado')
      .select('usuario_id')
      .neq('estado_asignacion', 'liberado');
    if (error) throw error;
    noDisponibles = new Set((data || []).map(a => a.usuario_id));
  } catch (e) {
    console.warn('usuariosCargarLista (evento_personal_asignado):', e.message);
    avisos.push('No se pudo calcular la disponibilidad de los usuarios.');
    noDisponibles = null;
  }

  // Merge en JS por id/usuario_id — perfiles_ayca.id === usuario_roles.usuario_id
  // === evento_personal_asignado.usuario_id (los 3 referencian auth.users.id).
  _usuariosDatosCache = perfiles.map(p => ({
    id: p.id,
    nombre: p.nombre,
    activo: !!p.activo,
    roles: rolesPorUsuario ? (rolesPorUsuario[p.id] || []) : [],
    rolesDesconocidos: rolesPorUsuario === null,
    disponible: noDisponibles ? !noDisponibles.has(p.id) : null // null = desconocida
  }));

  if (aviso && avisos.length) {
    aviso.textContent = '⚠️ ' + avisos.join(' ');
    aviso.style.display = 'block';
  }

  _usuariosAplicarFiltros();
}

// ── Buscador + filtros, aplicados sobre los datos ya cargados (sin volver a consultar) ──
function _usuariosAplicarFiltros() {
  const cont = document.getElementById('usuariosListaCont');
  if (!cont) return;

  if (!_usuariosDatosCache.length) {
    cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Sin usuarios registrados.</p>';
    return;
  }

  const texto       = (document.getElementById('usu_buscar')?.value || '').toLowerCase().trim();
  const filtroRol   = document.getElementById('usu_filtroRol')?.value || '';
  const filtroEstado = document.getElementById('usu_filtroEstado')?.value || '';
  const filtroDisp  = document.getElementById('usu_filtroDisponibilidad')?.value || '';

  const filtrados = _usuariosDatosCache.filter(u => {
    if (texto && !(u.nombre || '').toLowerCase().includes(texto)) return false;
    if (filtroRol && !u.roles.includes(filtroRol)) return false;
    if (filtroEstado && (filtroEstado === 'activo') !== u.activo) return false;
    if (filtroDisp) {
      if (u.disponible === null) return false; // desconocida: no puede afirmarse ninguna de las dos
      if (filtroDisp === 'disponible' && !u.disponible) return false;
      if (filtroDisp === 'no_disponible' && u.disponible) return false;
    }
    return true;
  });

  if (!filtrados.length) {
    cont.innerHTML = '<p style="color:#6b7280;text-align:center;padding:20px">Ningún usuario coincide con los filtros aplicados.</p>';
    return;
  }

  cont.innerHTML = filtrados.map(_usuariosRenderTarjeta).join('');
}

// ── Tarjeta de un usuario: nombre, badges de rol, estado, disponibilidad, último acceso ──
function _usuariosRenderTarjeta(u) {
  const estadoClr = u.activo ? '#16a34a' : '#6b7280';
  const estadoLbl = u.activo ? 'Activo' : 'Inactivo';

  let dispClr, dispLbl;
  if (u.disponible === null) { dispClr = '#9ca3af'; dispLbl = '—'; }
  else if (u.disponible)     { dispClr = '#16a34a'; dispLbl = 'Disponible'; }
  else                       { dispClr = '#d97706'; dispLbl = 'No disponible'; }

  const rolesBadges = u.rolesDesconocidos
    ? `<span style="font-size:10px;background:#9ca3af;color:white;padding:2px 8px;border-radius:99px">—</span>`
    : (u.roles.length
        ? u.roles.map(r => `<span style="font-size:10px;background:#0b5cc7;color:white;padding:2px 8px;border-radius:99px;margin:0 4px 4px 0;display:inline-block">${_etiquetaRol(r)}</span>`).join('')
        : `<span style="font-size:10px;background:#9ca3af;color:white;padding:2px 8px;border-radius:99px">Sin rol asignado</span>`);

  return `
    <div class="card" style="border-left:4px solid ${estadoClr};padding:12px 14px;margin:6px 0">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:6px;margin-bottom:6px">
        <b style="color:#0b3158;font-size:14px">${u.nombre || '(sin nombre)'}</b>
        <span style="flex-shrink:0;font-size:10px;background:${estadoClr};color:white;padding:2px 8px;border-radius:99px">${estadoLbl}</span>
      </div>
      <div style="display:flex;justify-content:space-between;align-items:center;gap:6px;margin-bottom:6px">
        <div>${rolesBadges}</div>
        <button class="btn-gris" style="font-size:11px;padding:3px 8px;flex-shrink:0" onclick="usuariosToggleEditorRoles('${u.id}')">✏️ Editar roles</button>
      </div>
      <div style="font-size:12px;color:#6b7280">
        <span style="background:${dispClr};color:white;font-size:10px;padding:2px 8px;border-radius:99px">${dispLbl}</span>
        &nbsp;·&nbsp; Último acceso: —
      </div>
      <div id="rolesEditor-${u.id}" style="display:none"></div>
    </div>`;
}

// ===============================
// 3.2C — ASIGNACIÓN DE ROLES (admin)
//
// usuario_roles ya tiene RLS que permite INSERT/UPDATE/DELETE directo
// desde el cliente cuando quien llama es administrador (policies
// roles_insert_admin / roles_update_admin / roles_delete_admin, todas
// con es_admin()) — no hace falta ninguna función RPC nueva para esto.
// ===============================

// ── Abre/cierra el editor inline de roles de un usuario ──
function usuariosToggleEditorRoles(usuarioId) {
  const cont = document.getElementById('rolesEditor-' + usuarioId);
  if (!cont) return;

  const abierto = cont.style.display !== 'none' && cont.innerHTML.trim() !== '';
  if (abierto) {
    cont.style.display = 'none';
    cont.innerHTML = '';
    return;
  }

  const u = _usuariosDatosCache.find(x => x.id === usuarioId);
  if (!u) return;

  cont.innerHTML = _usuariosRenderEditorRolesHTML(u);
  cont.style.display = 'block';
}

function _usuariosRenderEditorRolesHTML(u) {
  if (u.rolesDesconocidos) {
    return `
      <div style="border-top:1px solid #e5e7eb;margin-top:8px;padding-top:8px;font-size:12px;color:#92400e">
        ⚠️ No se pudieron cargar los roles actuales de este usuario, así que no se puede editar con seguridad ahora mismo. Recargá la página (Ctrl+Shift+R) e intentá de nuevo.
      </div>`;
  }

  const checks = ROLES_AYCA.map(rol => {
    const marcado = u.roles.includes(rol) ? 'checked' : '';
    return `<label style="display:inline-flex;align-items:center;gap:4px;margin:2px 10px 2px 0;font-size:12px">
      <input type="checkbox" value="${rol}" ${marcado} style="width:auto">${_etiquetaRol(rol)}
    </label>`;
  }).join('');

  return `
    <div style="border-top:1px solid #e5e7eb;margin-top:8px;padding-top:8px">
      <div id="rolesEditorErr-${u.id}" style="color:#dc2626;font-size:11px;margin-bottom:6px;display:none"></div>
      <div style="margin-bottom:8px">${checks}</div>
      <button class="btn-verde" style="font-size:12px;padding:6px 10px" onclick="usuariosGuardarRoles('${u.id}')">💾 Guardar roles</button>
      <button class="btn-gris" style="font-size:12px;padding:6px 10px" onclick="usuariosToggleEditorRoles('${u.id}')">✖ Cancelar</button>
    </div>`;
}

// ── Guarda los cambios de roles marcados en el editor de un usuario ──
async function usuariosGuardarRoles(usuarioId) {
  const cont  = document.getElementById('rolesEditor-' + usuarioId);
  const errEl = document.getElementById('rolesEditorErr-' + usuarioId);
  if (!cont) return;
  if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }

  const u = _usuariosDatosCache.find(x => x.id === usuarioId);
  if (!u || u.rolesDesconocidos) return;

  const seleccionados = Array.from(cont.querySelectorAll('input[type=checkbox]:checked')).map(c => c.value);
  const actuales = u.roles || [];
  const aAgregar = seleccionados.filter(r => !actuales.includes(r));
  const aQuitar  = actuales.filter(r => !seleccionados.includes(r));

  if (!aAgregar.length && !aQuitar.length) {
    usuariosToggleEditorRoles(usuarioId);
    return;
  }

  // Si te estás quitando a vos mismo el rol de administrador, confirmá
  // aparte — después de guardar podrías perder acceso a esta pantalla.
  if (aQuitar.includes('administrador')) {
    try {
      const { data } = await supabaseAYCA.auth.getUser();
      if (data?.user?.id === usuarioId) {
        const ok = confirm('Te estás quitando el rol de Administrador a vos mismo. Después de guardar podrías perder acceso a esta pantalla. ¿Continuar?');
        if (!ok) return;
      }
    } catch (e) { /* si falla la verificación, seguimos igual */ }
  }

  const btns = cont.querySelectorAll('button');
  btns.forEach(b => b.disabled = true);

  try {
    if (aAgregar.length) {
      const { error } = await supabaseAYCA
        .from('usuario_roles')
        .insert(aAgregar.map(rol => ({ usuario_id: usuarioId, rol })));
      if (error) throw error;
    }
    if (aQuitar.length) {
      const { error } = await supabaseAYCA
        .from('usuario_roles')
        .delete()
        .eq('usuario_id', usuarioId)
        .in('rol', aQuitar);
      if (error) throw error;
    }
    await usuariosCargarLista();
  } catch (e) {
    console.error('usuariosGuardarRoles:', e);
    if (errEl) {
      errEl.textContent = '⚠️ No se pudo guardar: ' + e.message;
      errEl.style.display = 'block';
    }
    btns.forEach(b => b.disabled = false);
  }
}
