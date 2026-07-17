-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2C — corrección
-- Fix: referencia ambigua dentro de fn_crear_mantencion()
--
-- CAUSA RAÍZ: la función se declara "returns table (id uuid, numero
-- text)". Eso crea, dentro de todo el cuerpo de la función, DOS
-- variables OUT implícitas llamadas "id" y "numero" — con el mismo
-- nombre exacto que las columnas "id" de tipos_mantencion y
-- plantillas_mantencion (y "numero" de mantenciones). Cualquier
-- referencia SIN calificar a "id" dentro del cuerpo queda ambigua
-- entre la columna de la tabla y la variable OUT, y Postgres la
-- rechaza en tiempo de ejecución.
--
-- CORRECCIÓN: se agregan alias explícitos a TODAS las tablas
-- consultadas dentro de la función y se califican TODAS las
-- columnas usadas (tm.id, tm.activo, pm.id, pm.activa, etc.). No se
-- cambia ninguna regla de negocio, validación, orden de ejecución
-- ni el contrato de la función (misma firma, mismos parámetros,
-- mismo retorno).
--
-- Ejecutar en cualquier momento después de
-- mantenciones_etapa2c.sql (requiere que fn_crear_mantencion ya
-- exista). Es un CREATE OR REPLACE FUNCTION: idempotente por
-- naturaleza, seguro de correr más de una vez.
--
-- NO modifica ninguna tabla, RLS, índice ni otra función.
-- ═══════════════════════════════════════════════════════════════

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

  -- Antes: "where id = p_tipo_mantencion_id" (ambiguo con el OUT "id").
  select tm.activo
    into v_tipo_activo
    from tipos_mantencion tm
    where tm.id = p_tipo_mantencion_id;
  if v_tipo_activo is null then
    raise exception 'Tipo de mantención no encontrado.';
  elsif not v_tipo_activo then
    raise exception 'El tipo de mantención está inactivo.';
  end if;

  -- Antes: "where id = p_plantilla_id" (ambiguo con el OUT "id");
  -- columnas del SELECT también calificadas por consistencia.
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

  -- Alias "m" en el INSERT + RETURNING calificado (ya evitaba la ambigüedad
  -- de "numero" en el antes de la lista VALUES no aplica, pero se deja
  -- explícito por consistencia con el resto de la función).
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

  -- ── Snapshot: copia íntegra de las 4 sub-tablas de la plantilla ──
  -- (ya usaban alias pp/pa/ppr/prec — se mantienen sin cambios)
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

-- Los privilegios (revoke/grant) ya aplicados en la ETAPA 2B no se ven
-- afectados por un CREATE OR REPLACE FUNCTION con la misma firma — se
-- conservan tal cual, no es necesario repetirlos.
