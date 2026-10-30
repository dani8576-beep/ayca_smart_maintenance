-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Ajuste: snapshot de área/sección en mantencion_actividades
--
-- CONTEXTO (confirmado contra la base de producción real, no contra las
-- migraciones de este repositorio):
-- public.plantilla_actividades YA tiene las columnas "area" y "seccion"
-- (agregadas manualmente en producción, con datos ya cargados para las
-- 125 actividades de la plantilla "Mantención anual estándar – Motor GMD").
-- public.mantencion_actividades NO las tiene — confirmado vía
-- information_schema.columns contra la base real. Sí tiene
-- "plantilla_actividad_id" (FK nullable hacia plantilla_actividades).
--
-- OBJETIVO:
-- Que cada mantención conserve su propio snapshot INDEPENDIENTE de
-- área/sección, igual criterio que el resto de columnas de
-- mantencion_actividades (codigo_actividad, descripcion, orden, etc.:
-- todas se copian al crear la mantención, ninguna se lee en vivo desde
-- la plantilla). Esto evita un JOIN permanente hacia plantilla_actividades
-- en tiempo de ejecución.
--
-- ALCANCE DE ESTE ARCHIVO:
-- 1. ALTER TABLE aditivo (2 columnas nullable) sobre mantencion_actividades.
-- 2. CREATE OR REPLACE de fn_crear_mantencion() y fn_agregar_equipo_evento()
--    — ÚNICO cambio real en ambas: agregar area/seccion a la copia de
--    actividades. Ninguna otra validación, regla de negocio, firma ni
--    retorno cambia. El resto del cuerpo es IDÉNTICO a:
--      fn_crear_mantencion       → 2026-07-17_mantenciones_etapa2c_fix_ambiguedad_fn_crear_mantencion.sql
--      fn_agregar_equipo_evento  → 2026-07-18_mantenciones_etapa2d_08_rollup_estados.sql (versión vigente)
-- 3. Backfill idempotente (UPDATE, no INSERT — no duplica nada al
--    reejecutarse) para las mantenciones ya existentes, usando
--    mantencion_actividades.plantilla_actividad_id para encontrar el
--    area/seccion de origen en plantilla_actividades.
--
-- NO modifica: RLS, triggers, otras funciones, otras tablas.
-- NO destructivo: columnas nuevas nullable, backfill es UPDATE puro.
-- NO se ejecuta automáticamente — este archivo se entrega para revisión.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regclass('public.mantencion_actividades') is null then
    raise exception 'Falta la tabla mantencion_actividades.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'plantilla_actividades' and column_name = 'area'
  ) then
    raise exception 'plantilla_actividades.area no existe — este ajuste asume que ya fue agregada manualmente en producción.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'plantilla_actividades' and column_name = 'seccion'
  ) then
    raise exception 'plantilla_actividades.seccion no existe — este ajuste asume que ya fue agregada manualmente en producción.';
  end if;
end $$;

-- ── 1. Columnas nuevas en mantencion_actividades (nullable, aditivo, idempotente) ──
alter table mantencion_actividades add column if not exists area    text;
alter table mantencion_actividades add column if not exists seccion text;

-- ── 2. fn_crear_mantencion() — CREATE OR REPLACE.
--       Único cambio real respecto al original: se agregan "area, seccion"
--       / "pa.area, pa.seccion" al INSERT hacia mantencion_actividades. ──
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

  select tm.activo
    into v_tipo_activo
    from tipos_mantencion tm
    where tm.id = p_tipo_mantencion_id;
  if v_tipo_activo is null then
    raise exception 'Tipo de mantención no encontrado.';
  elsif not v_tipo_activo then
    raise exception 'El tipo de mantención está inactivo.';
  end if;

  select pm.activa, pm.tipo_mantencion_id, pm.nombre, pm.version
    into v_plantilla_activa, v_plantilla_tipo_id, v_plantilla_nombre, v_plantilla_version
    from plantillas_mantencion pm
    where pm.id = p_plantilla_id;
  if v_plantilla_tipo_id is null then
    raise exception 'Plantilla no encontrada.';
  elsif not v_plantilla_activa then
    raise exception 'La plantilla seleccionada está inactiva.';
  elsif v_plantilla_tipo_id <> p_tipo_mantencion_id then
    raise exception 'La plantilla no pertenece al tipo de mantención seleccionado.';
  end if;

  v_numero := fn_generar_numero_mantencion();

  insert into mantenciones as m (
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
  returning m.id into v_id;

  insert into mantencion_personal (
    mantencion_id, plantilla_personal_id, perfil, especialidad,
    cantidad_original, cantidad_actual, obligatorio, origen, estado_fila, creado_por
  )
  select v_id, pp.id, pp.perfil, pp.especialidad,
         pp.cantidad, pp.cantidad, pp.obligatorio, 'plantilla', 'sugerido', auth.uid()
  from plantilla_personal pp
  where pp.plantilla_id = p_plantilla_id;

  -- ÚNICO CAMBIO de este archivo respecto al original: se agregan
  -- "area, seccion" / "pa.area, pa.seccion" — mismo criterio que el resto
  -- de columnas ya copiadas (snapshot propio, no referencia viva a la plantilla).
  insert into mantencion_actividades (
    mantencion_id, plantilla_actividad_id, codigo_actividad, descripcion, orden,
    depende_de, duracion_estimada_horas, obligatoria, area, seccion, origen, estado_fila, creado_por
  )
  select v_id, pa.id, pa.codigo_actividad, pa.descripcion, pa.orden,
         pa.depende_de, pa.duracion_estimada_horas, pa.obligatoria, pa.area, pa.seccion, 'plantilla', 'sugerido', auth.uid()
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

-- ── 3. fn_agregar_equipo_evento() — CREATE OR REPLACE.
--       Mismo único cambio. Resto del cuerpo IDÉNTICO a la versión
--       vigente en 2026-07-18_mantenciones_etapa2d_08_rollup_estados.sql. ──
create or replace function fn_agregar_equipo_evento(
  p_evento_id          uuid,
  p_area_id            uuid,
  p_equipo_id          uuid,
  p_tipo_mantencion_id uuid,
  p_plantilla_id       uuid,
  p_criticidad         text default null,
  p_fecha_plan_inicio  timestamptz default null,
  p_fecha_plan_termino timestamptz default null,
  p_observaciones      text default null
)
returns table (mantencion_id uuid, numero text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_cliente_id  uuid;
  v_evento_faena_id    uuid;
  v_evento_estado      text;
  v_evento_supervisor  uuid;
  v_tipo_activo        boolean;
  v_plantilla_activa   boolean;
  v_plantilla_tipo_id  uuid;
  v_plantilla_nombre   text;
  v_plantilla_version  int;
  v_numero             text;
  v_mant_id            uuid;
begin
  if not (tiene_rol('supervisor') or es_admin()) then
    raise exception 'Solo supervisores o administradores pueden agregar equipos a un evento.';
  end if;

  select em.cliente_id, em.faena_id, em.estado, em.supervisor_id
    into v_evento_cliente_id, v_evento_faena_id, v_evento_estado, v_evento_supervisor
    from eventos_mantencion em
    where em.id = p_evento_id;

  if v_evento_faena_id is null then
    raise exception 'El evento de mantención indicado (%) no existe.', p_evento_id;
  end if;

  if v_evento_estado in ('finalizado','cancelado') then
    raise exception 'No se pueden agregar equipos a un evento en estado %.', v_evento_estado;
  end if;

  if auth.uid() <> v_evento_supervisor and not es_admin() then
    raise exception 'Solo el supervisor del evento o un administrador puede agregar equipos.';
  end if;

  perform fn_validar_jerarquia_equipo(v_evento_cliente_id, v_evento_faena_id, p_area_id, p_equipo_id);

  if exists (
    select 1 from mantenciones m
    where m.evento_mantencion_id = p_evento_id
      and m.equipo_id = p_equipo_id
      and m.estado <> 'cancelada'
  ) then
    raise exception 'Este equipo ya tiene una mantención activa dentro de este evento. Cancele la mantención existente antes de volver a agregarlo.';
  end if;

  select tm.activo into v_tipo_activo from tipos_mantencion tm where tm.id = p_tipo_mantencion_id;
  if v_tipo_activo is null then
    raise exception 'Tipo de mantención no encontrado.';
  elsif not v_tipo_activo then
    raise exception 'El tipo de mantención está inactivo.';
  end if;

  select pm.activa, pm.tipo_mantencion_id, pm.nombre, pm.version
    into v_plantilla_activa, v_plantilla_tipo_id, v_plantilla_nombre, v_plantilla_version
    from plantillas_mantencion pm
    where pm.id = p_plantilla_id;
  if v_plantilla_tipo_id is null then
    raise exception 'Plantilla no encontrada.';
  elsif not v_plantilla_activa then
    raise exception 'La plantilla seleccionada está inactiva.';
  elsif v_plantilla_tipo_id <> p_tipo_mantencion_id then
    raise exception 'La plantilla no pertenece al tipo de mantención seleccionado.';
  end if;

  v_numero := fn_generar_numero_mantencion();

  insert into mantenciones as m (
    numero, cliente_id, faena_id, area_id, equipo_id,
    tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
    evento_mantencion_id,
    estado, planificacion_estado, recursos_estado, ejecucion_estado, revision_estado,
    criticidad, fecha_plan_inicio, fecha_plan_termino,
    supervisor_id, observaciones, creado_por
  ) values (
    v_numero, v_evento_cliente_id, v_evento_faena_id, p_area_id, p_equipo_id,
    p_tipo_mantencion_id, p_plantilla_id, v_plantilla_nombre, v_plantilla_version,
    p_evento_id,
    'borrador', 'pendiente', 'pendiente', 'no_iniciada', 'pendiente',
    p_criticidad, p_fecha_plan_inicio, p_fecha_plan_termino,
    v_evento_supervisor, p_observaciones, auth.uid()
  )
  returning m.id into v_mant_id;

  -- ÚNICO CAMBIO de este archivo respecto a la versión vigente: se
  -- agregan "area, seccion" / "pa.area, pa.seccion".
  insert into mantencion_actividades (
    mantencion_id, plantilla_actividad_id, codigo_actividad, descripcion, orden,
    depende_de, duracion_estimada_horas, obligatoria, area, seccion, origen, estado_fila, creado_por
  )
  select v_mant_id, pa.id, pa.codigo_actividad, pa.descripcion, pa.orden,
         pa.depende_de, pa.duracion_estimada_horas, pa.obligatoria, pa.area, pa.seccion, 'plantilla', 'sugerido', auth.uid()
  from plantilla_actividades pa
  where pa.plantilla_id = p_plantilla_id;

  insert into mantencion_protocolos (
    mantencion_id, plantilla_protocolo_id, tipo_protocolo, obligatorio, origen, estado_fila, creado_por
  )
  select v_mant_id, ppr.id, ppr.tipo_protocolo, ppr.obligatorio, 'plantilla', 'sugerido', auth.uid()
  from plantilla_protocolos ppr
  where ppr.plantilla_id = p_plantilla_id;

  insert into evento_personal_origen (
    evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
  )
  select cp.evento_personal_requerido_id, v_mant_id, cp.plantilla_personal_id, cp.cantidad, auth.uid()
  from fn_consolidar_personal_evento(p_evento_id, p_plantilla_id) cp;

  insert into evento_recursos_origen (
    evento_recursos_id, mantencion_id, plantilla_recurso_id, cantidad_aportada, creado_por
  )
  select cr.evento_recursos_id, v_mant_id, cr.plantilla_recurso_id, cr.cantidad, auth.uid()
  from fn_consolidar_recursos_evento(p_evento_id, p_plantilla_id) cr;

  perform fn_recalcular_personal_evento(p_evento_id);
  perform fn_recalcular_recursos_evento(p_evento_id);

  perform fn_actualizar_estado_revision(p_evento_id, 'personal');
  perform fn_actualizar_estado_revision(p_evento_id, 'recursos');

  perform fn_recalcular_estados_evento(p_evento_id);

  return query select v_mant_id, v_numero;
end;
$$;

-- ── 4. Backfill idempotente para mantenciones ya existentes ──
-- UPDATE, no INSERT: no hay riesgo de duplicar filas al reejecutar.
-- Solo toca filas con origen='plantilla' y plantilla_actividad_id resoluble
-- (las de origen='manual' no tienen de dónde heredar area/seccion y quedan
-- correctamente en NULL — no se inventan valores para ellas).
update mantencion_actividades ma
set area    = pa.area,
    seccion = pa.seccion
from plantilla_actividades pa
where ma.plantilla_actividad_id = pa.id
  and ma.origen = 'plantilla'
  and (ma.area is distinct from pa.area or ma.seccion is distinct from pa.seccion);

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Columnas creadas:
-- select column_name, data_type, is_nullable
--   from information_schema.columns
--   where table_schema = 'public' and table_name = 'mantencion_actividades'
--   order by ordinal_position;
--
-- 2) Backfill completo — debe devolver 0 filas:
-- select ma.id, ma.mantencion_id, ma.codigo_actividad
--   from mantencion_actividades ma
--   join plantilla_actividades pa on pa.id = ma.plantilla_actividad_id
--   where ma.origen = 'plantilla' and (ma.area is null or ma.seccion is null);
--
-- 3) Conteo por mantención — debe seguir dando 125 para las 3 existentes,
--    ahora todas con area/seccion pobladas:
-- select m.numero,
--        count(*) filter (where ma.area is not null and ma.seccion is not null) as con_area_seccion,
--        count(*) as total
--   from mantenciones m
--   join mantencion_actividades ma on ma.mantencion_id = m.id
--   group by m.numero
--   order by m.numero;
--
-- 4) Confirmar que las funciones no cambiaron de firma:
-- select proname, pg_get_function_identity_arguments(oid)
--   from pg_proc
--   where proname in ('fn_crear_mantencion','fn_agregar_equipo_evento');
--
-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- Revertir fn_crear_mantencion()/fn_agregar_equipo_evento() a su versión
-- anterior requiere volver a ejecutar el CREATE OR REPLACE de:
--   2026-07-17_mantenciones_etapa2c_fix_ambiguedad_fn_crear_mantencion.sql
--   2026-07-18_mantenciones_etapa2d_08_rollup_estados.sql (bloque de fn_agregar_equipo_evento)
-- Las columnas nuevas pueden eliminarse (perdiendo los datos de backfill) con:
-- alter table mantencion_actividades drop column if exists area;
-- alter table mantencion_actividades drop column if exists seccion;
