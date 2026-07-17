-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2C (definitiva)
-- Sistema Snapshot de Mantenciones
-- Ejecutar DESPUÉS de perfiles_roles.sql, mantenciones_etapa2a.sql,
-- mantenciones_etapa2a5.sql (+ tag_equipos), mantenciones_etapa2b.sql.
--
-- NO crea solicitudes_bodega ni tablas de 2D+. NO modifica la policy
-- mantenciones_select (técnico queda para 2D). NO modifica
-- protocolos_ayca, herramientas, herramientas_movimientos,
-- clientes/faenas/areas/equipos, plantillas_*.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Extender "mantenciones" (2B) con version_plantilla y nombre_plantilla ──
-- Idempotente: agrega las columnas solo si faltan.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='mantenciones' and column_name='version_plantilla'
  ) then
    alter table public.mantenciones add column version_plantilla int;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='mantenciones' and column_name='nombre_plantilla'
  ) then
    alter table public.mantenciones add column nombre_plantilla text;
  end if;
end $$;

-- Backfill de mantenciones ya existentes (si las hay), a partir de su propio
-- plantilla_id real — no se inventa nada, se deriva del vínculo ya existente.
update public.mantenciones m
set version_plantilla = pm.version,
    nombre_plantilla  = pm.nombre
from public.plantillas_mantencion pm
where pm.id = m.plantilla_id
  and (m.version_plantilla is null or m.nombre_plantilla is null);

-- Aplicar NOT NULL solo si el backfill dejó todo completo.
do $$
declare
  v_pendientes bigint;
begin
  select count(*) into v_pendientes from public.mantenciones
    where version_plantilla is null or nombre_plantilla is null;
  if v_pendientes = 0 then
    alter table public.mantenciones alter column version_plantilla set not null;
    alter table public.mantenciones alter column nombre_plantilla set not null;
    raise notice 'version_plantilla / nombre_plantilla quedaron NOT NULL.';
  else
    raise notice '% mantención(es) sin version_plantilla/nombre_plantilla tras el backfill — revisar antes de aplicar NOT NULL manualmente.', v_pendientes;
  end if;
end $$;

-- ── 2. mantencion_personal ──
create table if not exists mantencion_personal (
  id                     uuid primary key default gen_random_uuid(),
  mantencion_id          uuid not null references public.mantenciones(id) on delete cascade,
  plantilla_personal_id  uuid references public.plantilla_personal(id) on delete set null,
  perfil                 text not null,
  especialidad           text,
  usuario_id             uuid references auth.users(id),
  cantidad_original      int not null check (cantidad_original > 0),
  cantidad_actual        int not null check (cantidad_actual >= 0),
  obligatorio            boolean not null default true,
  origen                 text not null check (origen in ('plantilla','manual')),
  estado_fila            text not null default 'sugerido' check (estado_fila in ('sugerido','agregado','eliminado','modificado')),
  motivo_modificacion    text,
  modificado_por         uuid references auth.users(id),
  modificado_en          timestamptz,
  observaciones          text,
  fecha_snapshot         timestamptz not null default now(),
  creado_por             uuid references auth.users(id),
  creado_en              timestamptz not null default now(),
  actualizado_por        uuid references auth.users(id),
  actualizado_en         timestamptz,
  check (not (obligatorio and estado_fila = 'eliminado' and motivo_modificacion is null))
);

-- No se agrega UNIQUE en mantencion_personal a propósito: es legítimo tener varias
-- filas con el mismo perfil/especialidad (distintas personas reales cumpliendo el
-- mismo rol), así que forzar unicidad bloquearía un caso de negocio válido.

-- ── 3. mantencion_actividades ──
create table if not exists mantencion_actividades (
  id                       uuid primary key default gen_random_uuid(),
  mantencion_id            uuid not null references public.mantenciones(id) on delete cascade,
  plantilla_actividad_id   uuid references public.plantilla_actividades(id) on delete set null,
  codigo_actividad         text not null,
  descripcion              text,
  orden                    int not null default 0,
  depende_de               text,
  duracion_estimada_horas  numeric check (duracion_estimada_horas > 0),
  obligatoria              boolean not null default true,
  origen                   text not null check (origen in ('plantilla','manual')),
  estado_fila              text not null default 'sugerido' check (estado_fila in ('sugerido','agregado','eliminado','modificado')),
  motivo_modificacion      text,
  modificado_por           uuid references auth.users(id),
  modificado_en            timestamptz,
  estado_ejecucion         text not null default 'pendiente' check (estado_ejecucion in ('pendiente','en_proceso','completada','no_realizada','no_aplica')),
  resultado                text check (resultado in ('si','no','na')),
  num_observacion          text,
  aprobado_por             uuid references auth.users(id),
  aprobado_en              timestamptz,
  fecha_snapshot           timestamptz not null default now(),
  creado_por               uuid references auth.users(id),
  creado_en                timestamptz not null default now(),
  actualizado_por          uuid references auth.users(id),
  actualizado_en           timestamptz,
  check (not (obligatoria and estado_fila = 'eliminado' and motivo_modificacion is null))
);

-- ── 4. mantencion_protocolos ──
create table if not exists mantencion_protocolos (
  id                       uuid primary key default gen_random_uuid(),
  mantencion_id            uuid not null references public.mantenciones(id) on delete cascade,
  plantilla_protocolo_id   uuid references public.plantilla_protocolos(id) on delete set null,
  tipo_protocolo           text not null references public.tipos_protocolo(codigo),
  obligatorio              boolean not null default true,
  origen                   text not null check (origen in ('plantilla','manual')),
  estado_fila              text not null default 'sugerido' check (estado_fila in ('sugerido','agregado','eliminado','modificado')),
  motivo_modificacion      text,
  modificado_por           uuid references auth.users(id),
  modificado_en            timestamptz,
  estado_ejecucion         text not null default 'pendiente' check (estado_ejecucion in ('pendiente','en_proceso','completado')),
  fecha_snapshot           timestamptz not null default now(),
  creado_por               uuid references auth.users(id),
  creado_en                timestamptz not null default now(),
  actualizado_por          uuid references auth.users(id),
  actualizado_en           timestamptz,
  check (not (obligatorio and estado_fila = 'eliminado' and motivo_modificacion is null))
);

-- ── 5. mantencion_recursos ──
create table if not exists mantencion_recursos (
  id                     uuid primary key default gen_random_uuid(),
  mantencion_id          uuid not null references public.mantenciones(id) on delete cascade,
  plantilla_recurso_id   uuid references public.plantilla_recursos(id) on delete set null,
  categoria_recurso      text not null check (categoria_recurso in
                            ('herramienta','instrumento','equipo_apoyo','epp','repuesto','consumible','material')),
  nombre_generico        text not null,
  herramienta_codigo     text references public.herramientas(codigo),
  insumo_codigo          text references public.insumos_bodega(codigo),
  cantidad_original      numeric not null check (cantidad_original > 0),
  cantidad_actual        numeric not null check (cantidad_actual >= 0),
  obligatorio            boolean not null default false,
  origen                 text not null check (origen in ('plantilla','manual')),
  estado_fila            text not null default 'sugerido' check (estado_fila in ('sugerido','agregado','eliminado','modificado')),
  motivo_modificacion    text,
  modificado_por         uuid references auth.users(id),
  modificado_en          timestamptz,
  observaciones          text,
  fecha_snapshot         timestamptz not null default now(),
  creado_por             uuid references auth.users(id),
  creado_en              timestamptz not null default now(),
  actualizado_por        uuid references auth.users(id),
  actualizado_en         timestamptz,
  check (
    (categoria_recurso in ('herramienta','instrumento','equipo_apoyo') and insumo_codigo is null)
    or
    (categoria_recurso in ('epp','repuesto','consumible','material') and herramienta_codigo is null)
  ),
  check (not (obligatorio and estado_fila = 'eliminado' and motivo_modificacion is null))
);

-- ── Índices compuestos (mantencion_id, estado_fila) — consulta más frecuente:
--    "filas vigentes (no eliminadas) de esta mantención". Cubren también las
--    búsquedas por solo mantencion_id (prefijo izquierdo del índice). ──
create index if not exists idx_mantencion_personal_mant_estado
  on mantencion_personal(mantencion_id, estado_fila);
create index if not exists idx_mantencion_actividades_mant_estado
  on mantencion_actividades(mantencion_id, estado_fila);
create index if not exists idx_mantencion_protocolos_mant_estado
  on mantencion_protocolos(mantencion_id, estado_fila);
create index if not exists idx_mantencion_recursos_mant_estado
  on mantencion_recursos(mantencion_id, estado_fila);

-- ── Índices adicionales (no cubiertos por el compuesto anterior) ──
create index if not exists idx_mantencion_personal_usuario     on mantencion_personal(usuario_id);
create index if not exists idx_mantencion_protocolos_tipo      on mantencion_protocolos(tipo_protocolo);
create index if not exists idx_mantencion_recursos_herramienta on mantencion_recursos(herramienta_codigo);
create index if not exists idx_mantencion_recursos_insumo      on mantencion_recursos(insumo_codigo);

-- ── Restricciones UNIQUE para evitar duplicados accidentales dentro de una misma
--    mantención. Son índices únicos PARCIALES (where estado_fila <> 'eliminado'):
--    si el supervisor elimina un ítem y luego decide volver a agregarlo, no debe
--    quedar bloqueado por la fila histórica eliminada (que se conserva para
--    auditoría, según el diseño ya aprobado). ──

-- Un mismo tipo de protocolo no debe repetirse vigente en la misma mantención.
create unique index if not exists uq_mantencion_protocolos_tipo
  on mantencion_protocolos (mantencion_id, tipo_protocolo)
  where estado_fila <> 'eliminado';

-- Un mismo código de actividad del Anexo A1 no debe repetirse vigente en la misma mantención.
create unique index if not exists uq_mantencion_actividades_codigo
  on mantencion_actividades (mantencion_id, codigo_actividad)
  where estado_fila <> 'eliminado';

-- Una misma herramienta individual no debe solicitarse dos veces (vigente) en la
-- misma mantención. No aplica a filas genéricas sin herramienta_codigo asignado.
create unique index if not exists uq_mantencion_recursos_herramienta
  on mantencion_recursos (mantencion_id, herramienta_codigo)
  where estado_fila <> 'eliminado' and herramienta_codigo is not null;

-- Mismo criterio para insumos: evita dos filas vigentes del mismo insumo
-- (si se necesitan cantidades adicionales, se ajusta cantidad_actual de la
-- fila existente en vez de duplicarla).
create unique index if not exists uq_mantencion_recursos_insumo
  on mantencion_recursos (mantencion_id, insumo_codigo)
  where estado_fila <> 'eliminado' and insumo_codigo is not null;

-- ── RLS: solo lectura por ahora (mismo criterio de visibilidad que la mantención padre).
--    Sin policy de INSERT/UPDATE/DELETE — la escritura de ajustes queda para una
--    función dedicada en la próxima etapa. ──
alter table mantencion_personal    enable row level security;
alter table mantencion_actividades enable row level security;
alter table mantencion_protocolos  enable row level security;
alter table mantencion_recursos    enable row level security;

create policy "mantencion_personal_select" on mantencion_personal
  for select using (
    exists (
      select 1 from public.mantenciones m
      where m.id = mantencion_personal.mantencion_id
        and (es_admin() or auth.uid() = m.supervisor_id or auth.uid() = m.planificador_id
             or tiene_rol('bodega') or tiene_rol('gerencia'))
    )
  );

create policy "mantencion_actividades_select" on mantencion_actividades
  for select using (
    exists (
      select 1 from public.mantenciones m
      where m.id = mantencion_actividades.mantencion_id
        and (es_admin() or auth.uid() = m.supervisor_id or auth.uid() = m.planificador_id
             or tiene_rol('bodega') or tiene_rol('gerencia'))
    )
  );

create policy "mantencion_protocolos_select" on mantencion_protocolos
  for select using (
    exists (
      select 1 from public.mantenciones m
      where m.id = mantencion_protocolos.mantencion_id
        and (es_admin() or auth.uid() = m.supervisor_id or auth.uid() = m.planificador_id
             or tiene_rol('bodega') or tiene_rol('gerencia'))
    )
  );

create policy "mantencion_recursos_select" on mantencion_recursos
  for select using (
    exists (
      select 1 from public.mantenciones m
      where m.id = mantencion_recursos.mantencion_id
        and (es_admin() or auth.uid() = m.supervisor_id or auth.uid() = m.planificador_id
             or tiene_rol('bodega') or tiene_rol('gerencia'))
    )
  );

revoke all on mantencion_personal, mantencion_actividades, mantencion_protocolos, mantencion_recursos from authenticated;
grant select on mantencion_personal, mantencion_actividades, mantencion_protocolos, mantencion_recursos to authenticated;

-- ── Auditoría: reutiliza fn_tocar_auditoria() (2A.5); instalada ya para cuando
--    exista una vía de escritura (función dedicada, próxima etapa). ──
create trigger trg_auditoria_mantencion_personal
  before update on mantencion_personal
  for each row execute function fn_tocar_auditoria();

create trigger trg_auditoria_mantencion_actividades
  before update on mantencion_actividades
  for each row execute function fn_tocar_auditoria();

create trigger trg_auditoria_mantencion_protocolos
  before update on mantencion_protocolos
  for each row execute function fn_tocar_auditoria();

create trigger trg_auditoria_mantencion_recursos
  before update on mantencion_recursos
  for each row execute function fn_tocar_auditoria();

-- ── 6. Extender fn_crear_mantencion (2B) para copiar nombre/version de plantilla
--       y ejecutar el snapshot completo — misma firma, mismo contrato. ──
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
  v_plantilla_nombre  text;
  v_plantilla_version int;
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

  select activa, tipo_mantencion_id, nombre, version
    into v_plantilla_activa, v_plantilla_tipo_id, v_plantilla_nombre, v_plantilla_version
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
    tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
    estado, planificacion_estado, recursos_estado, ejecucion_estado, revision_estado,
    criticidad, fecha_plan_inicio, fecha_plan_termino,
    supervisor_id, planificador_id, observaciones, creado_por
  ) values (
    v_numero, p_cliente_id, p_faena_id, p_area_id, p_equipo_id,
    p_tipo_mantencion_id, p_plantilla_id, v_plantilla_nombre, v_plantilla_version,
    'borrador', 'pendiente', 'pendiente', 'no_iniciada', 'pendiente',
    p_criticidad, p_fecha_plan_inicio, p_fecha_plan_termino,
    p_supervisor_id, p_planificador_id, p_observaciones, auth.uid()
  )
  returning mantenciones.id into v_id;

  -- ── Snapshot: copia íntegra de las 4 sub-tablas de la plantilla ──
  insert into mantencion_personal (
    mantencion_id, plantilla_personal_id, perfil, especialidad,
    cantidad_original, cantidad_actual, obligatorio, origen, estado_fila, creado_por
  )
  select v_id, pp.id, pp.perfil, pp.especialidad,
         pp.cantidad, pp.cantidad, pp.obligatorio, 'plantilla', 'sugerido', auth.uid()
  from plantilla_personal pp
  where pp.plantilla_id = p_plantilla_id;

  insert into mantencion_actividades (
    mantencion_id, plantilla_actividad_id, codigo_actividad, descripcion, orden,
    depende_de, duracion_estimada_horas, obligatoria, origen, estado_fila, creado_por
  )
  select v_id, pa.id, pa.codigo_actividad, pa.descripcion, pa.orden,
         pa.depende_de, pa.duracion_estimada_horas, pa.obligatoria, 'plantilla', 'sugerido', auth.uid()
  from plantilla_actividades pa
  where pa.plantilla_id = p_plantilla_id;

  insert into mantencion_protocolos (
    mantencion_id, plantilla_protocolo_id, tipo_protocolo, obligatorio, origen, estado_fila, creado_por
  )
  select v_id, ppr.id, ppr.tipo_protocolo, ppr.obligatorio, 'plantilla', 'sugerido', auth.uid()
  from plantilla_protocolos ppr
  where ppr.plantilla_id = p_plantilla_id;

  insert into mantencion_recursos (
    mantencion_id, plantilla_recurso_id, categoria_recurso, nombre_generico,
    herramienta_codigo, insumo_codigo, cantidad_original, cantidad_actual,
    obligatorio, origen, estado_fila, creado_por
  )
  select v_id, prec.id, prec.categoria_recurso, prec.nombre_generico,
         prec.herramienta_codigo, prec.insumo_codigo, prec.cantidad_sugerida, prec.cantidad_sugerida,
         prec.obligatorio, 'plantilla', 'sugerido', auth.uid()
  from plantilla_recursos prec
  where prec.plantilla_id = p_plantilla_id;

  return query select v_id, v_numero;
end;
$$;

revoke all on function fn_crear_mantencion(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text
) from public;
grant execute on function fn_crear_mantencion(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text
) to authenticated;
