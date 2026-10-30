-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.07.1
-- Asignación real de personas — evento_personal_asignado
--
-- PROPÓSITO:
-- Completar evento_personal_asignado (tabla creada en 2D-03, hasta ahora
-- sin ninguna vía de escritura) con las tres funciones controladas para
-- asignar/quitar/modificar personas reales a un evento, y con las
-- garantías de inmutabilidad/historial que le faltaban a nivel de tabla.
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-17_perfiles_roles.sql                    (perfiles_ayca, es_admin(), tiene_rol())
--   - 2026-07-18_mantenciones_etapa2d_03_personal.sql   (evento_personal_asignado,
--                                                          evento_personal_requerido)
--   - 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql
--                                                       (fn_validar_supervisor_evento())
--
-- NO modifica RLS (2D-09). NO toca evento_personal_requerido, evento_recursos
-- ni ninguna función de 2D-06/2D-07 — es un frente independiente sobre una
-- tabla que hasta ahora no tenía ninguna función propia.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regclass('public.perfiles_ayca') is null then
    raise exception 'Falta la tabla perfiles_ayca — ejecutar primero 2026-07-17_perfiles_roles.sql';
  end if;

  if to_regclass('public.evento_personal_asignado') is null then
    raise exception 'Falta la tabla evento_personal_asignado — ejecutar primero 2026-07-18_mantenciones_etapa2d_03_personal.sql';
  end if;

  if to_regprocedure('public.fn_validar_supervisor_evento(uuid)') is null then
    raise exception 'Falta fn_validar_supervisor_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN A — Garantías de tabla que faltaban desde 2D-03
-- ═══════════════════════════════════════════════════════════════

-- ── A.1 Inmutabilidad de usuario_id/evento_mantencion_id ──
-- "No permitir cambiar usuario_id de una asignación existente: para
-- reemplazar una persona, retirar la anterior y crear una nueva." Se
-- aplica a nivel de trigger (no solo omitiendo el parámetro en las
-- funciones) para que la regla valga sin excepción, igual criterio que
-- ya se usó para equipo_id/area_id en mantenciones (2D-02) y para las
-- filas de origen (2D-05).
create or replace function fn_bloquear_cambio_usuario_asignacion()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if NEW.usuario_id <> OLD.usuario_id then
    raise exception 'No se puede cambiar el usuario de una asignación ya creada. Libere esta asignación (fn_quitar_persona_evento) y cree una nueva para la persona correcta.';
  end if;

  if NEW.evento_mantencion_id <> OLD.evento_mantencion_id then
    raise exception 'No se puede cambiar el evento de una asignación ya creada.';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_bloquear_cambio_usuario_asignacion on evento_personal_asignado;
create trigger trg_bloquear_cambio_usuario_asignacion
  before update on evento_personal_asignado
  for each row execute function fn_bloquear_cambio_usuario_asignacion();

-- ── A.2 Prohibir DELETE físico — conserva historial para RLS futura ──
create or replace function fn_bloquear_delete_evento_personal_asignado()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'No se puede eliminar físicamente una asignación — libérela (fn_quitar_persona_evento) para conservar el historial.';
end;
$$;

drop trigger if exists trg_bloquear_delete_evento_personal_asignado on evento_personal_asignado;
create trigger trg_bloquear_delete_evento_personal_asignado
  before delete on evento_personal_asignado
  for each row execute function fn_bloquear_delete_evento_personal_asignado();

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN B — fn_asignar_persona_evento()
-- ═══════════════════════════════════════════════════════════════

-- "Habilitado" se define como: existe en auth.users Y tiene una fila en
-- perfiles_ayca con activo = true. Un usuario sin fila en perfiles_ayca
-- se trata como NO habilitado (falla cerrado) — perfiles_ayca es la
-- única fuente de "activo/inactivo" que existe hoy en el esquema.
create or replace function fn_asignar_persona_evento(
  p_evento_id                    uuid,
  p_usuario_id                   uuid,
  p_perfil                       text,
  p_especialidad                 text default null,
  p_evento_personal_requerido_id uuid default null,
  p_estado_asignacion            text default 'propuesto',
  p_fecha_desde                  timestamptz default null,
  p_fecha_hasta                  timestamptz default null,
  p_observaciones                text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario_activo  boolean;
  v_req_evento_id   uuid;
  v_req_estado_fila text;
  v_id              uuid;
begin
  -- Evento existe, quien llama es su supervisor/admin, evento no
  -- cerrado/cancelado — reutiliza fn_validar_supervisor_evento (2D-07),
  -- cubre "impedir asignaciones en eventos cancelados o cerrados".
  perform fn_validar_supervisor_evento(p_evento_id);

  if not exists (select 1 from auth.users u where u.id = p_usuario_id) then
    raise exception 'El usuario indicado no existe.';
  end if;

  select pa.activo into v_usuario_activo from perfiles_ayca pa where pa.id = p_usuario_id;
  if v_usuario_activo is null then
    raise exception 'El usuario indicado no tiene un perfil habilitado en el sistema (perfiles_ayca).';
  elsif not v_usuario_activo then
    raise exception 'El usuario indicado está inactivo.';
  end if;

  -- Validado aquí ADEMÁS del trigger de 2D-03 (fn_validar_evento_personal_asignado)
  -- — mismo criterio de no confiar solo en la restricción de base, con
  -- mensaje claro antes de intentar el insert.
  if p_evento_personal_requerido_id is not null then
    select epr.evento_mantencion_id, epr.estado_fila
      into v_req_evento_id, v_req_estado_fila
      from evento_personal_requerido epr
      where epr.id = p_evento_personal_requerido_id;

    if v_req_evento_id is null then
      raise exception 'La línea de personal requerido indicada (%) no existe.', p_evento_personal_requerido_id;
    end if;

    if v_req_evento_id <> p_evento_id then
      raise exception 'La línea de personal requerido indicada pertenece a otro evento.';
    end if;

    if v_req_estado_fila = 'eliminado' then
      raise exception 'No se puede asignar personal a una línea de personal requerido que fue eliminada.';
    end if;
  end if;
  -- Si p_evento_personal_requerido_id es null, no se valida nada más:
  -- es una asignación extraordinaria, permitida a propósito.

  if exists (
    select 1 from evento_personal_asignado epa
    where epa.evento_mantencion_id = p_evento_id
      and epa.usuario_id = p_usuario_id
      and epa.estado_asignacion <> 'liberado'
  ) then
    raise exception 'Este usuario ya tiene una asignación vigente en este evento. Libere la asignación existente antes de crear una nueva.';
  end if;

  if trim(coalesce(p_perfil, '')) = '' then
    raise exception 'Debe indicar un perfil.';
  end if;

  if p_estado_asignacion = 'liberado' then
    raise exception 'No se puede crear una asignación ya liberada — asigne normalmente y libere después si corresponde.';
  end if;

  insert into evento_personal_asignado (
    evento_mantencion_id, evento_personal_requerido_id, usuario_id, perfil, especialidad,
    estado_asignacion, fecha_desde, fecha_hasta, observaciones, creado_por
  ) values (
    p_evento_id, p_evento_personal_requerido_id, p_usuario_id, p_perfil, p_especialidad,
    coalesce(p_estado_asignacion, 'propuesto'), p_fecha_desde, p_fecha_hasta, p_observaciones, auth.uid()
  )
  returning evento_personal_asignado.id into v_id;

  return v_id;
end;
$$;

revoke all on function fn_asignar_persona_evento(uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text) from public;
grant execute on function fn_asignar_persona_evento(uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN C — fn_quitar_persona_evento()
-- ═══════════════════════════════════════════════════════════════

-- No existe una columna "motivo_retiro" en evento_personal_asignado (a
-- diferencia de evento_personal_origen, 2D-05) — el motivo exigido se
-- registra en "observaciones" (se concatena si ya había algo escrito).
-- fecha_hasta se fija a now() si todavía no tenía una, para que el
-- campo refleje cuándo terminó realmente la asignación.
create or replace function fn_quitar_persona_evento(
  p_asignacion_id uuid,
  p_motivo        text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id  uuid;
  v_estado     text;
  v_obs_actual text;
begin
  select evento_mantencion_id, estado_asignacion, observaciones
    into v_evento_id, v_estado, v_obs_actual
    from evento_personal_asignado where id = p_asignacion_id;

  if v_evento_id is null then
    raise exception 'La asignación indicada (%) no existe.', p_asignacion_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado = 'liberado' then
    raise exception 'Esta asignación ya fue liberada.';
  end if;

  if trim(coalesce(p_motivo, '')) = '' then
    raise exception 'Debe indicar un motivo para liberar esta asignación.';
  end if;

  update evento_personal_asignado
  set estado_asignacion = 'liberado',
      fecha_hasta = coalesce(fecha_hasta, now()),
      observaciones = case
        when v_obs_actual is null or trim(v_obs_actual) = '' then 'Retirado: ' || p_motivo
        else v_obs_actual || ' | Retirado: ' || p_motivo
      end
  where id = p_asignacion_id;
end;
$$;

revoke all on function fn_quitar_persona_evento(uuid, text) from public;
grant execute on function fn_quitar_persona_evento(uuid, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN D — fn_modificar_asignacion_evento()
-- ═══════════════════════════════════════════════════════════════

-- Actualiza SOLO estado_asignacion (excepto 'liberado' — eso es
-- responsabilidad exclusiva de fn_quitar_persona_evento, que exige
-- motivo), fecha_desde, fecha_hasta y observaciones. NO acepta
-- usuario_id como parámetro — ni siquiera existe la posibilidad de
-- pasarlo, coherente con el trigger de la Sección A.1.
create or replace function fn_modificar_asignacion_evento(
  p_asignacion_id     uuid,
  p_estado_asignacion text default null,
  p_fecha_desde       timestamptz default null,
  p_fecha_hasta       timestamptz default null,
  p_observaciones     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id uuid;
  v_estado    text;
begin
  select evento_mantencion_id, estado_asignacion into v_evento_id, v_estado
    from evento_personal_asignado where id = p_asignacion_id;

  if v_evento_id is null then
    raise exception 'La asignación indicada (%) no existe.', p_asignacion_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado = 'liberado' then
    raise exception 'No se puede modificar una asignación ya liberada.';
  end if;

  if p_estado_asignacion = 'liberado' then
    raise exception 'Use fn_quitar_persona_evento() para liberar una asignación — exige motivo.';
  end if;

  if p_estado_asignacion is not null and p_estado_asignacion not in ('propuesto','confirmado','en_terreno') then
    raise exception 'estado_asignacion inválido: %.', p_estado_asignacion;
  end if;

  update evento_personal_asignado
  set estado_asignacion = coalesce(p_estado_asignacion, estado_asignacion),
      fecha_desde       = coalesce(p_fecha_desde, fecha_desde),
      fecha_hasta       = coalesce(p_fecha_hasta, fecha_hasta),
      observaciones     = coalesce(p_observaciones, observaciones)
  where id = p_asignacion_id;
end;
$$;

revoke all on function fn_modificar_asignacion_evento(uuid, text, timestamptz, timestamptz, text) from public;
grant execute on function fn_modificar_asignacion_evento(uuid, text, timestamptz, timestamptz, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Funciones y privilegios:
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace
--     and p.proname in ('fn_asignar_persona_evento', 'fn_quitar_persona_evento', 'fn_modificar_asignacion_evento')
--   order by p.proname;
--
-- 2) Triggers activos sobre evento_personal_asignado (deben ser 4: la
--    auditoría y la validación de 2D-03, más las dos nuevas de aquí):
-- select tgname from pg_trigger
--   where tgrelid = 'public.evento_personal_asignado'::regclass and not tgisinternal
--   order by tgname;
--
-- 3) Prueba de punta a punta (con datos reales, dentro de una transacción
--    que termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_asignacion_personal_etapa2d071.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop function if exists public.fn_modificar_asignacion_evento(uuid, text, timestamptz, timestamptz, text);
-- drop function if exists public.fn_quitar_persona_evento(uuid, text);
-- drop function if exists public.fn_asignar_persona_evento(uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text);
-- drop trigger if exists trg_bloquear_delete_evento_personal_asignado on public.evento_personal_asignado;
-- drop function if exists public.fn_bloquear_delete_evento_personal_asignado();
-- drop trigger if exists trg_bloquear_cambio_usuario_asignacion on public.evento_personal_asignado;
-- drop function if exists public.fn_bloquear_cambio_usuario_asignacion();
