-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2B (definitiva)
-- Tabla central "mantenciones", numeración anual y función de creación
-- Ejecutar DESPUÉS de 2026-07-17_perfiles_roles.sql,
-- 2026-07-17_mantenciones_etapa2a.sql y
-- 2026-07-17_mantenciones_etapa2a5.sql (requiere fn_tocar_auditoria(),
-- es_admin(), tiene_rol(), clientes, faenas, areas, equipos,
-- tipos_mantencion, plantillas_mantencion, correlativos_mantencion).
--
-- NO crea: mantencion_personal, mantencion_actividades, mantencion_protocolos,
-- mantencion_recursos, snapshot de plantilla, solicitudes_bodega,
-- solicitud_bodega_detalle, reservas, entregas, devoluciones, consumos.
-- NO modifica protocolos_ayca, herramientas, herramientas_movimientos,
-- clientes, faenas, areas, equipos (solo se leen).
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Tabla mantenciones ──
create table if not exists mantenciones (
  id                   uuid primary key default gen_random_uuid(),
  numero               text not null unique,
  cliente_id           uuid not null references public.clientes(id) on delete restrict,
  faena_id             uuid not null references public.faenas(id) on delete restrict,
  area_id              uuid not null references public.areas(id) on delete restrict,
  equipo_id            uuid not null references public.equipos(id) on delete restrict,
  tipo_mantencion_id   uuid not null references public.tipos_mantencion(id),
  plantilla_id         uuid not null references public.plantillas_mantencion(id),
  estado               text not null default 'borrador',
  planificacion_estado text not null default 'pendiente',
  recursos_estado      text not null default 'pendiente',
  ejecucion_estado     text not null default 'no_iniciada',
  revision_estado      text not null default 'pendiente',
  criticidad           text,
  fecha_plan_inicio    timestamptz,
  fecha_plan_termino   timestamptz,
  fecha_real_inicio    timestamptz,
  fecha_real_termino   timestamptz,
  supervisor_id        uuid not null references auth.users(id),
  planificador_id      uuid references auth.users(id),
  observaciones        text,
  creado_por           uuid not null references auth.users(id),
  creado_en            timestamptz not null default now(),
  actualizado_por      uuid references auth.users(id),
  actualizado_en       timestamptz,

  check (estado in ('borrador','pendiente_planificacion','planificada','pendiente_recursos',
                     'lista_para_ejecutar','en_ejecucion','pausada','en_revision','cerrada','cancelada')),
  check (planificacion_estado in ('pendiente','en_proceso','lista')),
  check (recursos_estado in ('pendiente','solicitados','parcial','completos')),
  check (ejecucion_estado in ('no_iniciada','en_curso','pausada','completada')),
  check (revision_estado in ('pendiente','en_revision','aprobada','observada')),
  check (criticidad is null or criticidad in ('baja','media','alta','critica')),
  check (fecha_plan_termino is null or fecha_plan_inicio is null or fecha_plan_termino >= fecha_plan_inicio),
  check (fecha_real_termino is null or fecha_real_inicio is null or fecha_real_termino >= fecha_real_inicio),
  check (estado <> 'cerrada' or (ejecucion_estado = 'completada' and revision_estado = 'aprobada')),
  check (estado <> 'en_ejecucion' or fecha_real_inicio is not null)
);

-- ── 2. Índices ──
create index if not exists idx_mantenciones_estado             on mantenciones(estado);
create index if not exists idx_mantenciones_cliente             on mantenciones(cliente_id);
create index if not exists idx_mantenciones_faena               on mantenciones(faena_id);
create index if not exists idx_mantenciones_area                on mantenciones(area_id);
create index if not exists idx_mantenciones_equipo              on mantenciones(equipo_id);
create index if not exists idx_mantenciones_tipo_mantencion     on mantenciones(tipo_mantencion_id);
create index if not exists idx_mantenciones_plantilla           on mantenciones(plantilla_id);
create index if not exists idx_mantenciones_supervisor          on mantenciones(supervisor_id);
create index if not exists idx_mantenciones_planificador        on mantenciones(planificador_id);
create index if not exists idx_mantenciones_fecha_plan_inicio   on mantenciones(fecha_plan_inicio);
create index if not exists idx_mantenciones_fecha_plan_termino  on mantenciones(fecha_plan_termino);
create index if not exists idx_mantenciones_creado_en           on mantenciones(creado_en);

-- ── 3. RLS ──
alter table mantenciones enable row level security;

create policy "mantenciones_select" on mantenciones
  for select using (
    es_admin()
    or auth.uid() = supervisor_id
    or auth.uid() = planificador_id
    or tiene_rol('bodega')
    or tiene_rol('gerencia')
  );

-- Sin policy de INSERT a propósito: toda creación pasa por fn_crear_mantencion (SECURITY DEFINER).

create policy "mantenciones_update" on mantenciones
  for update using (
    (auth.uid() = supervisor_id and estado <> 'cerrada')
    or es_admin()
  );

create policy "mantenciones_delete" on mantenciones
  for delete using (
    (es_admin() and estado in ('borrador','cancelada'))
    or (auth.uid() = supervisor_id and estado in ('borrador','cancelada'))
  );

-- cliente_id, faena_id, area_id, equipo_id, numero, tipo_mantencion_id, plantilla_id,
-- supervisor_id, creado_por, creado_en, id: INMUTABLES vía UPDATE directo (fuera del GRANT).
revoke all on mantenciones from authenticated;
grant select on mantenciones to authenticated;
grant update (
  criticidad,
  estado, planificacion_estado, recursos_estado, ejecucion_estado, revision_estado,
  fecha_plan_inicio, fecha_plan_termino, fecha_real_inicio, fecha_real_termino,
  planificador_id, observaciones
) on mantenciones to authenticated;
grant delete on mantenciones to authenticated;

-- ── 4. Validación de jerarquía cliente → faena → área → equipo ──
create or replace function fn_validar_jerarquia_equipo(
  p_cliente_id uuid, p_faena_id uuid, p_area_id uuid, p_equipo_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activo boolean;
  v_padre  uuid;
begin
  select activo into v_activo from public.clientes where id = p_cliente_id;
  if v_activo is null then raise exception 'Cliente no encontrado.';
  elsif not v_activo then raise exception 'El cliente está inactivo.'; end if;

  select activo, cliente_id into v_activo, v_padre from public.faenas where id = p_faena_id;
  if v_padre is null then raise exception 'Faena no encontrada.';
  elsif not v_activo then raise exception 'La faena está inactiva.';
  elsif v_padre <> p_cliente_id then raise exception 'La faena no pertenece al cliente seleccionado.'; end if;

  select activo, faena_id into v_activo, v_padre from public.areas where id = p_area_id;
  if v_padre is null then raise exception 'Área no encontrada.';
  elsif not v_activo then raise exception 'El área está inactiva.';
  elsif v_padre <> p_faena_id then raise exception 'El área no pertenece a la faena seleccionada.'; end if;

  select activo, area_id into v_activo, v_padre from public.equipos where id = p_equipo_id;
  if v_padre is null then raise exception 'Equipo no encontrado.';
  elsif not v_activo then raise exception 'El equipo está inactivo.';
  elsif v_padre <> p_area_id then raise exception 'El equipo no pertenece al área seleccionada.'; end if;
end;
$$;

revoke all on function fn_validar_jerarquia_equipo(uuid, uuid, uuid, uuid) from public, authenticated;

-- ── 5. Numeración anual ──
create or replace function fn_generar_numero_mantencion()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anio int := extract(year from now())::int;
  v_num  int;
begin
  insert into correlativos_mantencion (anio, ultimo_numero)
    values (v_anio, 0)
    on conflict (anio) do nothing;

  update correlativos_mantencion
    set ultimo_numero = ultimo_numero + 1
    where anio = v_anio
    returning ultimo_numero into v_num;

  return 'AYCA-' || v_anio || '-' || lpad(v_num::text, 6, '0');
end;
$$;

revoke all on function fn_generar_numero_mantencion() from public, authenticated;

-- ── 6. Función de creación controlada ──
create or replace function fn_crear_mantencion(
  p_cliente_id         uuid,
  p_faena_id           uuid,
  p_area_id            uuid,
  p_equipo_id          uuid,
  p_tipo_mantencion_id uuid,
  p_plantilla_id       uuid,
  p_supervisor_id      uuid default auth.uid(),
  p_planificador_id    uuid default null,
  p_criticidad         text default null,
  p_fecha_plan_inicio  timestamptz default null,
  p_fecha_plan_termino timestamptz default null,
  p_observaciones      text default null
)
returns table (id uuid, numero text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tipo_activo       boolean;
  v_plantilla_activa  boolean;
  v_plantilla_tipo_id uuid;
  v_numero            text;
  v_id                uuid;
begin
  if not (tiene_rol('supervisor') or es_admin()) then
    raise exception 'Solo supervisores o administradores pueden crear mantenciones.';
  end if;

  if p_supervisor_id <> auth.uid() and not es_admin() then
    raise exception 'No puede crear una mantención asignando a otro supervisor.';
  end if;

  perform fn_validar_jerarquia_equipo(p_cliente_id, p_faena_id, p_area_id, p_equipo_id);

  select activo into v_tipo_activo from tipos_mantencion where id = p_tipo_mantencion_id;
  if v_tipo_activo is null then
    raise exception 'Tipo de mantención no encontrado.';
  elsif not v_tipo_activo then
    raise exception 'El tipo de mantención está inactivo.';
  end if;

  select activa, tipo_mantencion_id into v_plantilla_activa, v_plantilla_tipo_id
    from plantillas_mantencion where id = p_plantilla_id;
  if v_plantilla_tipo_id is null then
    raise exception 'Plantilla no encontrada.';
  elsif not v_plantilla_activa then
    raise exception 'La plantilla seleccionada está inactiva.';
  elsif v_plantilla_tipo_id <> p_tipo_mantencion_id then
    raise exception 'La plantilla no pertenece al tipo de mantención seleccionado.';
  end if;

  v_numero := fn_generar_numero_mantencion();

  insert into mantenciones (
    numero, cliente_id, faena_id, area_id, equipo_id,
    tipo_mantencion_id, plantilla_id,
    estado, planificacion_estado, recursos_estado, ejecucion_estado, revision_estado,
    criticidad, fecha_plan_inicio, fecha_plan_termino,
    supervisor_id, planificador_id, observaciones, creado_por
  ) values (
    v_numero, p_cliente_id, p_faena_id, p_area_id, p_equipo_id,
    p_tipo_mantencion_id, p_plantilla_id,
    'borrador', 'pendiente', 'pendiente', 'no_iniciada', 'pendiente',
    p_criticidad, p_fecha_plan_inicio, p_fecha_plan_termino,
    p_supervisor_id, p_planificador_id, p_observaciones, auth.uid()
  )
  returning mantenciones.id into v_id;

  return query select v_id, v_numero;
end;
$$;

revoke all on function fn_crear_mantencion(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text
) from public;
grant execute on function fn_crear_mantencion(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text
) to authenticated;

-- ── 7. Actualización restringida para el Planificador ──
create or replace function fn_actualizar_planificacion(
  p_mantencion_id         uuid,
  p_fecha_plan_inicio     timestamptz default null,
  p_fecha_plan_termino    timestamptz default null,
  p_planificacion_estado  text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_planificador_id uuid;
  v_estado          text;
begin
  select planificador_id, estado into v_planificador_id, v_estado
    from mantenciones where id = p_mantencion_id;

  if v_planificador_id is null and v_estado is null then
    raise exception 'Mantención no encontrada.';
  end if;

  if auth.uid() <> v_planificador_id and not es_admin() then
    raise exception 'Solo el planificador asignado o un administrador puede actualizar la planificación.';
  end if;

  if v_estado = 'cerrada' then
    raise exception 'No se puede modificar la planificación de una mantención cerrada.';
  end if;

  update mantenciones set
    fecha_plan_inicio    = coalesce(p_fecha_plan_inicio, fecha_plan_inicio),
    fecha_plan_termino   = coalesce(p_fecha_plan_termino, fecha_plan_termino),
    planificacion_estado = coalesce(p_planificacion_estado, planificacion_estado)
  where id = p_mantencion_id;
end;
$$;

revoke all on function fn_actualizar_planificacion(uuid, timestamptz, timestamptz, text) from public;
grant execute on function fn_actualizar_planificacion(uuid, timestamptz, timestamptz, text) to authenticated;

-- ── 8. Auditoría — reutiliza fn_tocar_auditoria() de la ETAPA 2A.5, sin duplicar ──
create trigger trg_auditoria_mantenciones
  before update on mantenciones
  for each row execute function fn_tocar_auditoria();
