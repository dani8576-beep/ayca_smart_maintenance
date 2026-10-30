-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — RLS: permitir UPDATE acotado de estado_ejecucion
-- en public.mantencion_actividades (Orden de Trabajo — Fase B)
--
-- CONTEXTO:
-- public.mantencion_actividades tiene RLS habilitado desde su creación
-- (2026-07-17_mantenciones_etapa2c.sql) pero NUNCA se otorgó privilegio
-- de UPDATE a "authenticated" (solo GRANT SELECT, línea 264 de ese
-- archivo), y NUNCA existió una política de UPDATE — solo la de SELECT
-- ("mantencion_actividades_select", creada en 2C y extendida en
-- 2026-07-18_mantenciones_etapa2d_09_rls_visibilidad.sql). Confirmado por
-- búsqueda exhaustiva en todo el repositorio antes de escribir este archivo.
--
-- OBJETIVO:
-- Permitir que un supervisor marque/desmarque actividades de SUS PROPIAS
-- mantenciones (directas o de un evento que él supervisa) entre
-- 'pendiente'/'completada' en estado_ejecucion, y que un administrador
-- pueda hacerlo sobre cualquier mantención — pero SOLO mientras la
-- mantención no esté cerrada, y SOLO sobre las 3 columnas que la Orden
-- de Trabajo realmente necesita tocar desde el navegador.
--
-- AJUSTES respecto a la versión anterior de este archivo (revisión pedida):
-- 1. El GRANT ya NO es de tabla completa. Se revoca cualquier UPDATE
--    general y se otorga UPDATE únicamente sobre (estado_ejecucion,
--    actualizado_por, actualizado_en). La app nunca podrá modificar desde
--    el navegador mantencion_id, descripcion, codigo_actividad, area,
--    seccion, orden, obligatoria ni estado_fila — Postgres rechaza a nivel
--    de privilegio cualquier UPDATE que intente tocar una columna fuera
--    de esa lista, independientemente de la política RLS.
-- 2. USING y WITH CHECK ahora exigen además "m.estado <> 'cerrada'". El
--    valor 'cerrada' se confirmó como miembro real del CHECK de
--    mantenciones.estado (2026-07-17_mantenciones_etapa2b.sql: check
--    (estado in ('borrador','pendiente_planificacion','planificada',
--    'pendiente_recursos','lista_para_ejecutar','en_ejecucion','pausada',
--    'en_revision','cerrada','cancelada'))) — no es un valor inventado.
--    El bloque de validaciones previas además lo reconfirma en vivo contra
--    pg_constraint antes de crear la política, por si el vocabulario
--    cambiara en el futuro.
-- 3. Se eliminó cualquier UPDATE de prueba contra datos reales. La
--    verificación funcional quedó como instrucciones de prueba manual
--    desde la aplicación (Fase B), no como SQL para correr en el editor.
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - es_admin(), tiene_rol()                     (2026-07-17_perfiles_roles.sql)
--   - tabla mantenciones, mantencion_actividades   (2026-07-17_mantenciones_etapa2b.sql, 2c.sql)
--   - fn_es_supervisor_evento(uuid)                (2026-07-18_mantenciones_etapa2d_09_rls_visibilidad.sql)
--
-- NO modifica: la política SELECT existente, ninguna otra tabla, ningún
-- otro GRANT, ninguna función. NO otorga INSERT ni DELETE. NO usa ninguna
-- función nueva — solo es_admin() y fn_es_supervisor_evento(), ambas
-- ya existentes.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
declare
  v_check_tiene_cerrada boolean;
begin
  if to_regclass('public.mantencion_actividades') is null then
    raise exception 'Falta la tabla mantencion_actividades — ejecutar primero 2026-07-17_mantenciones_etapa2c.sql';
  end if;

  if to_regclass('public.mantenciones') is null then
    raise exception 'Falta la tabla mantenciones — ejecutar primero 2026-07-17_mantenciones_etapa2b.sql';
  end if;

  if to_regprocedure('public.es_admin()') is null then
    raise exception 'Falta es_admin() — ejecutar primero 2026-07-17_perfiles_roles.sql';
  end if;

  if to_regprocedure('public.fn_es_supervisor_evento(uuid)') is null then
    raise exception 'Falta fn_es_supervisor_evento(uuid) — ejecutar primero 2026-07-18_mantenciones_etapa2d_09_rls_visibilidad.sql';
  end if;

  if not exists (
    select 1 from pg_class where relname = 'mantencion_actividades' and relrowsecurity = true
  ) then
    raise exception 'mantencion_actividades no tiene RLS habilitado — no debería llegar a este estado; revisar antes de continuar.';
  end if;

  -- Confirmación en vivo (no asumida) de que 'cerrada' es un valor real
  -- del CHECK de mantenciones.estado, antes de usarlo en la política.
  select bool_or(pg_get_constraintdef(oid) ilike '%cerrada%')
    into v_check_tiene_cerrada
    from pg_constraint
    where conrelid = 'public.mantenciones'::regclass and contype = 'c';

  if not coalesce(v_check_tiene_cerrada, false) then
    raise exception 'No se encontró el valor ''cerrada'' en ningún CHECK de mantenciones.estado — el vocabulario real no coincide con lo asumido; revisar antes de continuar.';
  end if;
end $$;

-- ── 1. Privilegios — UPDATE acotado a 3 columnas, no a toda la tabla ──
-- Se revoca cualquier UPDATE general primero (defensivo/idempotente: si
-- nunca existió, esta sentencia no falla, solo no tiene efecto), y se
-- otorga UPDATE solo sobre las columnas que la Orden de Trabajo necesita
-- tocar desde el navegador. mantencion_id, descripcion, codigo_actividad,
-- orden, obligatoria, area, seccion y estado_fila quedan fuera de este
-- GRANT: cualquier intento de incluirlas en un UPDATE será rechazado por
-- Postgres a nivel de privilegio, antes incluso de evaluar RLS.
revoke update on public.mantencion_actividades from authenticated;

grant update (
  estado_ejecucion,
  actualizado_por,
  actualizado_en
)
on public.mantencion_actividades
to authenticated;

-- ── 2. Política de fila para UPDATE ──
-- drop + create (no existe "create policy if not exists" en Postgres):
-- idempotente y seguro de reejecutar. using() controla qué filas son
-- editables antes del cambio; with check() controla que el resultado del
-- UPDATE siga cumpliendo la misma condición. Se agrega "m.estado <>
-- 'cerrada'" en ambas cláusulas: una mantención cerrada no puede recibir
-- más cambios de ejecución desde esta pantalla.
drop policy if exists "mantencion_actividades_update" on mantencion_actividades;
create policy "mantencion_actividades_update" on mantencion_actividades
  for update using (
    exists (
      select 1 from mantenciones m
      where m.id = mantencion_actividades.mantencion_id
        and m.estado <> 'cerrada'
        and (
          es_admin()
          or auth.uid() = m.supervisor_id
          or (m.evento_mantencion_id is not null and fn_es_supervisor_evento(m.evento_mantencion_id))
        )
    )
  )
  with check (
    exists (
      select 1 from mantenciones m
      where m.id = mantencion_actividades.mantencion_id
        and m.estado <> 'cerrada'
        and (
          es_admin()
          or auth.uid() = m.supervisor_id
          or (m.evento_mantencion_id is not null and fn_es_supervisor_evento(m.evento_mantencion_id))
        )
    )
  );

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Privilegios de COLUMNA otorgados (no de tabla completa):
-- select grantee, column_name, privilege_type
--   from information_schema.column_privileges
--   where table_schema = 'public' and table_name = 'mantencion_actividades'
--     and grantee = 'authenticated' and privilege_type = 'UPDATE'
--   order by column_name;
-- -- Debe devolver EXACTAMENTE 3 filas: actualizado_en, actualizado_por,
-- -- estado_ejecucion. Si aparece cualquier otra columna, o si
-- -- information_schema.role_table_grants todavía muestra UPDATE a nivel
-- -- de tabla completa para "authenticated", algo salió mal.
--
-- 2) Confirmar que NO hay UPDATE de tabla completa:
-- select privilege_type from information_schema.role_table_grants
--   where table_schema = 'public' and table_name = 'mantencion_actividades'
--     and grantee = 'authenticated';
-- -- Debe mostrar SELECT únicamente (el UPDATE, si aparece, debe ser solo
-- -- a nivel de columna, visible en la consulta anterior, no aquí).
--
-- 3) Política creada, con el using/with check esperado (debe incluir
--    "estado <> 'cerrada'" en el texto de qual y with_check):
-- select policyname, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public' and tablename = 'mantencion_actividades'
--   order by policyname;
--
-- 4) RLS sigue habilitado (no se desactivó por accidente):
-- select relrowsecurity from pg_class where oid = 'public.mantencion_actividades'::regclass;
-- -- Debe devolver "true".
--
-- 5) La política SELECT existente sigue intacta (no se tocó en este archivo):
-- select policyname from pg_policies
--   where schemaname = 'public' and tablename = 'mantencion_actividades' and cmd = 'r';
--
-- ═══════════════════════════════════════════════════════════════
-- PRUEBA FUNCIONAL — hacer DESDE LA APLICACIÓN (Fase B), no con SQL
-- suelto contra datos reales. Casos a cubrir antes de dar por buena
-- esta migración:
-- ═══════════════════════════════════════════════════════════════
-- a) Supervisor autorizado: iniciar sesión como el supervisor real de
--    una de las 3 mantenciones existentes, abrir su Orden de Trabajo,
--    marcar y desmarcar una actividad — debe guardar correctamente y
--    reflejarse al volver a abrir la pantalla.
-- b) Supervisor NO autorizado: iniciar sesión como un supervisor que NO
--    administra esa mantención (ni directamente ni vía el evento) e
--    intentar el mismo cambio — debe fallar (0 filas afectadas / error
--    visible en la UI), sin romper el resto de la pantalla.
-- c) Mantención cerrada: cambiar el estado de una mantención de prueba a
--    'cerrada' (manualmente, en un entorno de prueba) e intentar marcar
--    una actividad como completada — debe ser rechazado por la política.
--
-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop policy if exists "mantencion_actividades_update" on public.mantencion_actividades;
-- revoke update (estado_ejecucion, actualizado_por, actualizado_en)
--   on public.mantencion_actividades from authenticated;
-- -- La política SELECT y el GRANT SELECT no se ven afectados por este rollback.
