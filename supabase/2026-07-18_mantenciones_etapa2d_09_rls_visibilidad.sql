-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.09
-- RLS y visibilidad por rol — cierre de seguridad de la Fase 2D
--
-- PROPÓSITO:
-- Reemplazar el "deny-all" temporal (RLS habilitado sin políticas) de
-- eventos_mantencion (2D-01), evento_personal_requerido/evento_recursos
-- (2D-03/2D-04) y evento_personal_origen/evento_recursos_origen (2D-05)
-- por políticas reales, y EXTENDER (no reemplazar) las políticas ya
-- existentes de mantenciones/mantencion_actividades/mantencion_protocolos
-- (2B/2C) para sumar la visibilidad de técnico y de supervisor-por-evento.
--
-- ── MATRIZ DE PERMISOS ──
--   Administrador : acceso total (ya cubierto por es_admin() en todas
--                   las políticas existentes; no requiere cambios).
--   Supervisor    : gestiona los eventos donde es supervisor_id, y por
--                   extensión TODAS las tablas hijas de esos eventos —
--                   verificado contra el supervisor ACTUAL del evento
--                   (fn_es_supervisor_evento), no contra una copia
--                   posiblemente desactualizada en la fila hija.
--   Técnico       : solo lectura, y solo si tiene una fila VIGENTE
--                   (estado_asignacion <> 'liberado') en
--                   evento_personal_asignado para ese evento — nunca
--                   escritura administrativa.
--   Planificador  : lectura amplia de eventos y mantenciones (ya lo
--                   tenía mantenciones desde 2B); sin escritura nueva.
--   Bodega        : lectura de evento_recursos y datos del evento/equipo
--                   (equipos ya es de lectura pública para todo
--                   autenticado desde 2A.5) — nada del "motor"
--                   (evento_personal_*, evento_recursos_origen).
--   Gerencia      : lectura global (ya lo tenía mantenciones); sin
--                   escritura.
--
-- ── FUNCIONES HELPER (para no repetir subconsultas en cada política) ──
--   fn_es_supervisor_evento(evento_id)      → auth.uid() = supervisor
--                                              ACTUAL del evento.
--   fn_es_tecnico_vigente_evento(evento_id) → auth.uid() tiene una fila
--                                              vigente en
--                                              evento_personal_asignado
--                                              para ese evento.
--   fn_puede_ver_evento(evento_id)          → admin OR supervisor OR
--                                              planificador OR gerencia
--                                              OR técnico vigente. Cubre
--                                              7 de las 9 tablas; bodega
--                                              se agrega aparte solo en
--                                              eventos_mantencion y
--                                              evento_recursos (no en
--                                              el resto, según la matriz).
-- Las 3 son SECURITY DEFINER: se llaman desde políticas de las MISMAS
-- tablas que consultan (evento_personal_asignado, eventos_mantencion),
-- así que sin SECURITY DEFINER causarían recursión de RLS — mismo
-- motivo por el que tiene_rol()/es_admin() (perfiles_roles.sql) ya son
-- SECURITY DEFINER.
--
-- ── ESCRITURA ──
-- Ninguna tabla nueva de 2D (eventos_mantencion aparte, que sí tiene
-- UPDATE/DELETE con columnas acotadas, igual criterio que mantenciones)
-- recibe policies de INSERT/UPDATE/DELETE para "authenticated": toda
-- escritura de evento_personal_requerido/asignado/origen,
-- evento_recursos(_origen) ya pasa exclusivamente por las funciones
-- SECURITY DEFINER de 2D-06/2D-07/2D-07.1 — igual criterio que
-- mantencion_personal/actividades/protocolos/recursos desde 2C.
--
-- ── AUDITORÍA DE FUNCIONES SECURITY DEFINER ──
-- En vez de reconstruir a mano la lista de todas las funciones creadas
-- en 2D-01 a 2D-08 (con riesgo real de omitir alguna), esta migración
-- recorre pg_proc dinámicamente y corrige lo que encuentre:
--   - revoca EXECUTE de "public" en cualquier función SECURITY DEFINER
--     del esquema que todavía lo tenga (el default de PostgreSQL es
--     otorgar EXECUTE a PUBLIC al crear una función, así que cualquier
--     CREATE FUNCTION sin REVOKE explícito queda expuesto).
--   - fija search_path = public en cualquier función SECURITY DEFINER
--     que no lo tenga configurado.
-- El resto de la auditoría ("grant únicamente a authenticated cuando
-- corresponda", "validación interna de rol y pertenencia al evento") no
-- es mecánicamente corregible sin conocer la intención de cada función
-- (pública vs. privada) — se deja como consulta de verificación manual
-- al final de este archivo, más la revisión ya hecha función por función
-- a lo largo de 2D-01 a 2D-08.
--
-- DEPENDENCIAS: todas las migraciones de 2A a 2D.08.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regclass('public.eventos_mantencion') is null
     or to_regclass('public.evento_personal_requerido') is null
     or to_regclass('public.evento_personal_asignado') is null
     or to_regclass('public.evento_personal_origen') is null
     or to_regclass('public.evento_recursos') is null
     or to_regclass('public.evento_recursos_origen') is null then
    raise exception 'Faltan tablas de 2D-01/03/04/05 — ejecutar esas migraciones antes que esta.';
  end if;

  if to_regprocedure('public.fn_recalcular_estados_evento(uuid)') is null then
    raise exception 'Falta fn_recalcular_estados_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_08_rollup_estados.sql';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN A — Funciones helper de visibilidad
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_es_supervisor_evento(p_evento_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from eventos_mantencion em
    where em.id = p_evento_id and em.supervisor_id = auth.uid()
  );
$$;

revoke all on function fn_es_supervisor_evento(uuid) from public;
grant execute on function fn_es_supervisor_evento(uuid) to authenticated;

-- "liberada" (estado_asignacion) cubre el único estado terminal que
-- existe hoy en evento_personal_asignado. No existe un concepto de fila
-- "eliminada" en esta tabla (no tiene estado_fila, a diferencia de las
-- tablas Snapshot) — se documenta para que quede claro que no se omitió
-- por descuido.
create or replace function fn_es_tecnico_vigente_evento(p_evento_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from evento_personal_asignado epa
    where epa.evento_mantencion_id = p_evento_id
      and epa.usuario_id = auth.uid()
      and epa.estado_asignacion <> 'liberado'
  );
$$;

revoke all on function fn_es_tecnico_vigente_evento(uuid) from public;
grant execute on function fn_es_tecnico_vigente_evento(uuid) to authenticated;

-- Cubre admin/supervisor-del-evento/planificador/gerencia/técnico-vigente
-- — la combinación que se repite en 7 de las 9 tablas de esta etapa.
-- bodega NO está incluida aquí a propósito (solo ve eventos_mantencion y
-- evento_recursos, agregado aparte en esas 2 políticas).
create or replace function fn_puede_ver_evento(p_evento_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select es_admin()
    or fn_es_supervisor_evento(p_evento_id)
    or tiene_rol('planificador')
    or tiene_rol('gerencia')
    or fn_es_tecnico_vigente_evento(p_evento_id);
$$;

revoke all on function fn_puede_ver_evento(uuid) from public;
grant execute on function fn_puede_ver_evento(uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN B — eventos_mantencion
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "eventos_mantencion_select" on eventos_mantencion;
create policy "eventos_mantencion_select" on eventos_mantencion
  for select using (
    fn_puede_ver_evento(id) or tiene_rol('bodega')
  );

-- Sin policy de INSERT a propósito: toda creación pasa por
-- fn_crear_evento_mantencion (SECURITY DEFINER) — mismo criterio que
-- mantenciones desde 2B.
drop policy if exists "eventos_mantencion_update" on eventos_mantencion;
create policy "eventos_mantencion_update" on eventos_mantencion
  for update using (
    (fn_es_supervisor_evento(id) and estado not in ('finalizado','cancelado'))
    or es_admin()
  );

drop policy if exists "eventos_mantencion_delete" on eventos_mantencion;
create policy "eventos_mantencion_delete" on eventos_mantencion
  for delete using (
    (es_admin() and estado in ('borrador','cancelado'))
    or (fn_es_supervisor_evento(id) and estado in ('borrador','cancelado'))
  );

-- Igual criterio que mantenciones (2B): columnas de identidad/rollup
-- INMUTABLES vía UPDATE directo (fuera del GRANT). estado/ejecucion_estado/
-- revision_estado/personal_estado/recursos_estado son EXCLUSIVAMENTE
-- escritos por las funciones SECURITY DEFINER de 2D-06/07/08 — un
-- supervisor no puede "aprobarse a sí mismo" el evento saltándose esas
-- funciones.
revoke all on eventos_mantencion from authenticated;
grant select on eventos_mantencion to authenticated;
grant update (
  nombre, descripcion, codigo, criticidad,
  fecha_plan_inicio, fecha_plan_termino, fecha_real_inicio, fecha_real_termino,
  planificacion_estado, planificador_id, observaciones
) on eventos_mantencion to authenticated;
grant delete on eventos_mantencion to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN C — mantenciones (EXTIENDE, no reemplaza, 2B)
-- ═══════════════════════════════════════════════════════════════

-- select: se agregan 2 cláusulas nuevas — supervisor-por-evento (usa el
-- supervisor ACTUAL del evento, no la copia en mantenciones.supervisor_id,
-- que puede quedar desactualizada si el evento cambia de supervisor) y
-- técnico (vigente en el evento, si es mantención de evento; asignado
-- directo en mantencion_personal, si es mantención suelta — así queda
-- resuelto el "técnico queda para 2D" que 2C había dejado pendiente).
drop policy if exists "mantenciones_select" on mantenciones;
create policy "mantenciones_select" on mantenciones
  for select using (
    es_admin()
    or auth.uid() = supervisor_id
    or auth.uid() = planificador_id
    or tiene_rol('bodega')
    or tiene_rol('gerencia')
    or (evento_mantencion_id is not null and fn_puede_ver_evento(evento_mantencion_id))
    or (evento_mantencion_id is null and exists (
          select 1 from mantencion_personal mp
          where mp.mantencion_id = mantenciones.id
            and mp.usuario_id = auth.uid()
            and mp.estado_fila <> 'eliminado'
        ))
  );

-- update/delete: sin cambios de fondo — se agrega la variante
-- "supervisor actual del evento" junto a la ya existente
-- "supervisor_id propio", por si llegaran a divergir.
drop policy if exists "mantenciones_update" on mantenciones;
create policy "mantenciones_update" on mantenciones
  for update using (
    (auth.uid() = supervisor_id and estado <> 'cerrada')
    or (evento_mantencion_id is not null and fn_es_supervisor_evento(evento_mantencion_id) and estado <> 'cerrada')
    or es_admin()
  );

drop policy if exists "mantenciones_delete" on mantenciones;
create policy "mantenciones_delete" on mantenciones
  for delete using (
    (es_admin() and estado in ('borrador','cancelada'))
    or (auth.uid() = supervisor_id and estado in ('borrador','cancelada'))
    or (evento_mantencion_id is not null and fn_es_supervisor_evento(evento_mantencion_id) and estado in ('borrador','cancelada'))
  );

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN D — mantencion_actividades / mantencion_protocolos
-- (EXTIENDEN, no reemplazan, 2C — mismo criterio que mantenciones_select)
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "mantencion_actividades_select" on mantencion_actividades;
create policy "mantencion_actividades_select" on mantencion_actividades
  for select using (
    exists (
      select 1 from mantenciones m
      where m.id = mantencion_actividades.mantencion_id
        and (
          es_admin() or auth.uid() = m.supervisor_id or auth.uid() = m.planificador_id
          or tiene_rol('bodega') or tiene_rol('gerencia')
          or (m.evento_mantencion_id is not null and fn_puede_ver_evento(m.evento_mantencion_id))
          or (m.evento_mantencion_id is null and exists (
                select 1 from mantencion_personal mp
                where mp.mantencion_id = m.id and mp.usuario_id = auth.uid() and mp.estado_fila <> 'eliminado'
              ))
        )
    )
  );

drop policy if exists "mantencion_protocolos_select" on mantencion_protocolos;
create policy "mantencion_protocolos_select" on mantencion_protocolos
  for select using (
    exists (
      select 1 from mantenciones m
      where m.id = mantencion_protocolos.mantencion_id
        and (
          es_admin() or auth.uid() = m.supervisor_id or auth.uid() = m.planificador_id
          or tiene_rol('bodega') or tiene_rol('gerencia')
          or (m.evento_mantencion_id is not null and fn_puede_ver_evento(m.evento_mantencion_id))
          or (m.evento_mantencion_id is null and exists (
                select 1 from mantencion_personal mp
                where mp.mantencion_id = m.id and mp.usuario_id = auth.uid() and mp.estado_fila <> 'eliminado'
              ))
        )
    )
  );

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN E — evento_personal_requerido / evento_personal_asignado /
-- evento_personal_origen (RLS estaba habilitado sin políticas desde
-- 2D-03/2D-05 — se agregan aquí las políticas reales)
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "evento_personal_requerido_select" on evento_personal_requerido;
create policy "evento_personal_requerido_select" on evento_personal_requerido
  for select using (fn_puede_ver_evento(evento_mantencion_id));

drop policy if exists "evento_personal_asignado_select" on evento_personal_asignado;
create policy "evento_personal_asignado_select" on evento_personal_asignado
  for select using (fn_puede_ver_evento(evento_mantencion_id));

drop policy if exists "evento_personal_origen_select" on evento_personal_origen;
create policy "evento_personal_origen_select" on evento_personal_origen
  for select using (
    exists (
      select 1 from evento_personal_requerido epr
      where epr.id = evento_personal_origen.evento_personal_requerido_id
        and fn_puede_ver_evento(epr.evento_mantencion_id)
    )
  );

-- Sin policy de INSERT/UPDATE/DELETE en las 3: toda escritura pasa por
-- las funciones SECURITY DEFINER de 2D-06/2D-07/2D-07.1. Nunca se otorga
-- GRANT de escritura a "authenticated" sobre estas tablas.
revoke all on evento_personal_requerido, evento_personal_asignado, evento_personal_origen from authenticated;
grant select on evento_personal_requerido, evento_personal_asignado, evento_personal_origen to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN F — evento_recursos / evento_recursos_origen
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "evento_recursos_select" on evento_recursos;
create policy "evento_recursos_select" on evento_recursos
  for select using (fn_puede_ver_evento(evento_mantencion_id) or tiene_rol('bodega'));

drop policy if exists "evento_recursos_origen_select" on evento_recursos_origen;
create policy "evento_recursos_origen_select" on evento_recursos_origen
  for select using (
    exists (
      select 1 from evento_recursos er
      where er.id = evento_recursos_origen.evento_recursos_id
        and (fn_puede_ver_evento(er.evento_mantencion_id) or tiene_rol('bodega'))
    )
  );
-- Nota: evento_recursos_origen SÍ hereda la visibilidad de bodega desde
-- evento_recursos (ver la línea con tiene_rol('bodega') arriba) — bodega
-- puede ver de dónde salió cada cantidad de un recurso que ya puede ver
-- de todas formas. Esto es distinto de evento_personal_origen, donde
-- bodega NO tiene acceso a personal en ningún nivel (matriz de permisos).

revoke all on evento_recursos, evento_recursos_origen from authenticated;
grant select on evento_recursos, evento_recursos_origen to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN G — Auditoría automática de funciones SECURITY DEFINER
-- ═══════════════════════════════════════════════════════════════

do $$
declare
  v_rec record;
  v_total_revocados int := 0;
  v_total_search_path int := 0;
begin
  -- (a) Ninguna función SECURITY DEFINER del esquema debe conservar
  -- EXECUTE para "public" (el default de PostgreSQL al crear una función
  -- es otorgárselo a PUBLIC; cualquier CREATE FUNCTION sin REVOKE
  -- explícito queda expuesto sin que se note a simple vista).
  for v_rec in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prosecdef = true
      and has_function_privilege('public', p.oid, 'EXECUTE')
  loop
    execute format('revoke execute on function public.%I(%s) from public', v_rec.proname, v_rec.args);
    v_total_revocados := v_total_revocados + 1;
    raise notice 'Revocado EXECUTE de "public" sobre %(%) (SECURITY DEFINER).', v_rec.proname, v_rec.args;
  end loop;

  -- (b) Toda función SECURITY DEFINER debe fijar search_path
  -- explícitamente (evita que una función con privilegios elevados
  -- resuelva nombres de objetos según el search_path de quien la llama).
  for v_rec in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prosecdef = true
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, array[]::text[])) cfg
        where cfg like 'search_path=%'
      )
  loop
    execute format('alter function public.%I(%s) set search_path = public', v_rec.proname, v_rec.args);
    v_total_search_path := v_total_search_path + 1;
    raise notice 'search_path fijado a "public" en %(%) (no lo tenía configurado).', v_rec.proname, v_rec.args;
  end loop;

  raise notice 'Auditoría SECURITY DEFINER completa: % función(es) con EXECUTE de public revocado, % función(es) con search_path corregido.',
    v_total_revocados, v_total_search_path;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) RLS activo y con políticas en las 9 tablas de esta etapa:
-- select relname, relrowsecurity from pg_class
--   where relname in ('eventos_mantencion','mantenciones','mantencion_actividades',
--     'mantencion_protocolos','evento_personal_requerido','evento_personal_asignado',
--     'evento_personal_origen','evento_recursos','evento_recursos_origen');
-- select tablename, policyname, cmd from pg_policies
--   where tablename in ('eventos_mantencion','mantenciones','mantencion_actividades',
--     'mantencion_protocolos','evento_personal_requerido','evento_personal_asignado',
--     'evento_personal_origen','evento_recursos','evento_recursos_origen')
--   order by tablename, policyname;
--
-- 2) Todas las funciones SECURITY DEFINER del esquema, con su estado de
--    privilegios (para revisar "grant únicamente a authenticated cuando
--    corresponda" — las que deben ser privadas deben mostrar "false" en
--    ambas columnas; las públicas, "false" en public y "true" en
--    authenticated):
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args,
--        has_function_privilege('public', p.oid, 'EXECUTE') as public_puede_ejecutar,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace and p.prosecdef = true
--   order by p.proname;
-- -- NINGUNA fila debe mostrar "true" en public_puede_ejecutar.
--
-- 3) Todas las funciones SECURITY DEFINER tienen search_path fijado:
-- select p.proname
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace and p.prosecdef = true
--     and not exists (select 1 from unnest(coalesce(p.proconfig, array[]::text[])) cfg where cfg like 'search_path=%');
-- -- Debe devolver 0 filas.
--
-- 4) Pruebas RLS con roles simulados (dentro de una transacción que
--    termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_rls_visibilidad_etapa2d09.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop policy if exists "evento_recursos_origen_select" on public.evento_recursos_origen;
-- drop policy if exists "evento_recursos_select" on public.evento_recursos;
-- drop policy if exists "evento_personal_origen_select" on public.evento_personal_origen;
-- drop policy if exists "evento_personal_asignado_select" on public.evento_personal_asignado;
-- drop policy if exists "evento_personal_requerido_select" on public.evento_personal_requerido;
--
-- -- mantencion_actividades/mantencion_protocolos/mantenciones: volver a
-- -- ejecutar los CREATE POLICY originales de 2026-07-17_mantenciones_etapa2c.sql
-- -- y 2026-07-17_mantenciones_etapa2b.sql para restaurar la versión sin
-- -- técnico/supervisor-por-evento.
--
-- drop policy if exists "eventos_mantencion_delete" on public.eventos_mantencion;
-- drop policy if exists "eventos_mantencion_update" on public.eventos_mantencion;
-- drop policy if exists "eventos_mantencion_select" on public.eventos_mantencion;
--
-- drop function if exists public.fn_puede_ver_evento(uuid);
-- drop function if exists public.fn_es_tecnico_vigente_evento(uuid);
-- drop function if exists public.fn_es_supervisor_evento(uuid);
--
-- -- La auditoría de la SECCIÓN G no es reversible ni debería serlo
-- -- (revertirla significaría volver a exponer funciones SECURITY DEFINER
-- -- a "public", lo cual nunca es correcto).
