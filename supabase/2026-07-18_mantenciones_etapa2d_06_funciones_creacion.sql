-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.06
-- Funciones de creación: evento y agregado de equipo
--
-- PROPÓSITO:
-- Entregar las dos funciones públicas que arman el flujo multiequipo:
--   - fn_crear_evento_mantencion(): crea SOLO la fila del evento
--     (eventos_mantencion). Responsabilidad única — no toca equipos,
--     personal ni recursos.
--   - fn_agregar_equipo_evento(): agrega UN equipo a un evento ya
--     existente. Es la función "pesada" de esta etapa: crea la
--     mantención de ese equipo, su snapshot reducido, consolida
--     personal/recursos del evento y actualiza los estados agregados.
--     Se puede llamar tantas veces como equipos tenga el evento.
--
-- Ambas funciones NO tocan fn_crear_mantencion() (2B/2C) — siguen
-- existiendo sin cambios para el flujo de mantención suelta.
--
-- ── FLUJO COMPLETO DE fn_agregar_equipo_evento() ──
--   1. validar        → rol, evento existe y no está cerrado/cancelado,
--                        quien llama es el supervisor del evento o admin,
--                        jerarquía equipo→área→faena→cliente contra el
--                        cliente/faena REALES del evento, el equipo NO
--                        está ya activo en este evento (verificado en
--                        código, no solo confiando en el índice único de
--                        2D-02 — ver nota más abajo), tipo de mantención
--                        activo, plantilla activa y del tipo correcto.
--   2. crear mantención     → inserta en "mantenciones" con
--                             evento_mantencion_id = el evento.
--   3. snapshot reducido    → copia SOLO plantilla_actividades y
--                             plantilla_protocolos hacia
--                             mantencion_actividades/mantencion_protocolos
--                             (idéntico, línea por línea, al bloque de
--                             snapshot que ya usa fn_crear_mantencion
--                             para esas dos tablas — sin reinventarlo).
--                             Personal y recursos NO se snapshotean por
--                             equipo: van a los pasos 4-6.
--   4. consolidar personal  → fn_consolidar_personal_evento() (privada)
--                             encuentra o crea, por cada fila de
--                             plantilla_personal del equipo, la línea
--                             evento_personal_requerido correspondiente
--                             (match por perfil+especialidad).
--   5. consolidar recursos  → fn_consolidar_recursos_evento() (privada),
--                             mismo criterio, usando la misma clave
--                             normalizada que el índice único de
--                             evento_recursos (2D-04): categoria +
--                             nombre_generico normalizado + código.
--   6. crear tablas de origen → el resultado de los pasos 4 y 5 (qué
--                             línea corresponde a cada fila de
--                             plantilla) se usa directamente para
--                             insertar en evento_personal_origen /
--                             evento_recursos_origen (2D-05) — fusionado
--                             en el mismo INSERT ... SELECT que consume
--                             la función de consolidación.
--   7. recalcular cantidades → fn_recalcular_personal_evento() /
--                             fn_recalcular_recursos_evento() (privadas)
--                             recomputan cantidad_sugerida de TODAS las
--                             líneas vigentes del evento, sumando las
--                             filas de origen ACTIVAS. Nunca tocan
--                             cantidad_aprobada — son las mismas
--                             funciones que reutilizará 2D-07 al quitar
--                             un equipo.
--   8. actualizar estados   → personal_estado/recursos_estado del evento
--                             pasan a 'en_revision' (cualquier cambio en
--                             las listas exige que el supervisor revise
--                             de nuevo antes de aprobar).
--
-- TRANSACCIONALIDAD: todo el flujo ocurre dentro de UNA sola función
-- PL/pgSQL. En PostgreSQL, una función completa se ejecuta como parte de
-- la transacción que la invoca — si CUALQUIER paso lanza una excepción
-- (incluida cualquiera de las validaciones del paso 1, o un CHECK/FK de
-- alguna de las tablas), ningún efecto de los pasos anteriores queda
-- aplicado: no hay mantención a medio crear, ni snapshot parcial, ni
-- consolidación incompleta. No se necesita (ni es posible) un BEGIN/COMMIT
-- explícito dentro de la función — la atomicidad es una propiedad del
-- lenguaje, no algo que este archivo deba programar aparte.
--
-- DUPLICADOS: el índice único uq_mantenciones_evento_equipo (2D-02) sigue
-- siendo el resguardo final ante condiciones de carrera (dos llamadas
-- simultáneas). Pero esta función NO se apoya solo en él: valida
-- explícitamente la ausencia de una mantención activa del mismo equipo en
-- el mismo evento ANTES de intentar el insert, y lanza un mensaje de
-- error claro y específico en vez de dejar que el usuario vea el error
-- genérico de una restricción de base de datos violada.
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-17_mantenciones_etapa2a.sql     (plantilla_actividades, plantilla_protocolos,
--                                                plantilla_personal, plantilla_recursos)
--   - 2026-07-17_mantenciones_etapa2b.sql      (mantenciones, fn_validar_jerarquia_equipo(),
--                                                fn_generar_numero_mantencion())
--   - 2026-07-17_mantenciones_etapa2c.sql      (mantencion_actividades, mantencion_protocolos)
--   - 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql
--   - 2026-07-18_mantenciones_etapa2d_02_relacion_evento.sql
--   - 2026-07-18_mantenciones_etapa2d_03_personal.sql
--   - 2026-07-18_mantenciones_etapa2d_04_recursos.sql
--   - 2026-07-18_mantenciones_etapa2d_05_trazabilidad.sql
--
-- NO crea todavía: funciones de alta/baja/modificación/aprobación manual
-- de evento_personal_requerido/evento_recursos/evento_personal_asignado,
-- ni la función de "quitar equipo" con su propio recálculo (todo eso es
-- 2D-07). NO modifica RLS (2D-09).
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regprocedure('public.tiene_rol(text)') is null then
    raise exception 'Falta tiene_rol() — ejecutar primero 2026-07-17_perfiles_roles.sql';
  end if;

  if to_regprocedure('public.fn_validar_jerarquia_equipo(uuid,uuid,uuid,uuid)') is null then
    raise exception 'Falta fn_validar_jerarquia_equipo() — ejecutar primero 2026-07-17_mantenciones_etapa2b.sql';
  end if;

  if to_regprocedure('public.fn_generar_numero_mantencion()') is null then
    raise exception 'Falta fn_generar_numero_mantencion() — ejecutar primero 2026-07-17_mantenciones_etapa2b.sql';
  end if;

  if to_regprocedure('public.fn_generar_numero_evento_mantencion()') is null then
    raise exception 'Falta fn_generar_numero_evento_mantencion() — ejecutar primero 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql';
  end if;

  if to_regclass('public.mantencion_actividades') is null or to_regclass('public.mantencion_protocolos') is null then
    raise exception 'Faltan mantencion_actividades/mantencion_protocolos — ejecutar primero 2026-07-17_mantenciones_etapa2c.sql';
  end if;

  if to_regclass('public.evento_personal_requerido') is null then
    raise exception 'Falta evento_personal_requerido — ejecutar primero 2026-07-18_mantenciones_etapa2d_03_personal.sql';
  end if;

  if to_regclass('public.evento_recursos') is null then
    raise exception 'Falta evento_recursos — ejecutar primero 2026-07-18_mantenciones_etapa2d_04_recursos.sql';
  end if;

  if to_regclass('public.evento_personal_origen') is null or to_regclass('public.evento_recursos_origen') is null then
    raise exception 'Faltan evento_personal_origen/evento_recursos_origen — ejecutar primero 2026-07-18_mantenciones_etapa2d_05_trazabilidad.sql';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'mantenciones' and column_name = 'evento_mantencion_id'
  ) then
    raise exception 'Falta la columna mantenciones.evento_mantencion_id — ejecutar primero 2026-07-18_mantenciones_etapa2d_02_relacion_evento.sql';
  end if;
end $$;

-- ── 1. fn_crear_evento_mantencion() — responsabilidad única: crear el
--       evento. No agrega equipos, no toca personal ni recursos. ──
create or replace function fn_crear_evento_mantencion(
  p_cliente_id         uuid,
  p_faena_id           uuid,
  p_tipo_evento        text,
  p_nombre             text,
  p_supervisor_id      uuid default auth.uid(),
  p_planificador_id    uuid default null,
  p_codigo             text default null,
  p_criticidad         text default null,
  p_fecha_plan_inicio  timestamptz default null,
  p_fecha_plan_termino timestamptz default null,
  p_descripcion        text default null,
  p_observaciones      text default null
)
returns table (id uuid, numero text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente_activo      boolean;
  v_faena_activo        boolean;
  v_faena_cliente_id    uuid;
  v_tipo_evento_activo  boolean;
  v_numero              text;
  v_id                  uuid;
begin
  if not (tiene_rol('supervisor') or es_admin()) then
    raise exception 'Solo supervisores o administradores pueden crear eventos de mantención.';
  end if;

  if p_supervisor_id <> auth.uid() and not es_admin() then
    raise exception 'No puede crear un evento asignando a otro supervisor.';
  end if;

  select c.activo into v_cliente_activo from clientes c where c.id = p_cliente_id;
  if v_cliente_activo is null then
    raise exception 'Cliente no encontrado.';
  elsif not v_cliente_activo then
    raise exception 'El cliente está inactivo.';
  end if;

  select f.activo, f.cliente_id into v_faena_activo, v_faena_cliente_id from faenas f where f.id = p_faena_id;
  if v_faena_cliente_id is null then
    raise exception 'Faena no encontrada.';
  elsif not v_faena_activo then
    raise exception 'La faena está inactiva.';
  elsif v_faena_cliente_id <> p_cliente_id then
    raise exception 'La faena no pertenece al cliente seleccionado.';
  end if;

  select tem.activo into v_tipo_evento_activo from tipos_evento_mantencion tem where tem.codigo = p_tipo_evento;
  if v_tipo_evento_activo is null then
    raise exception 'Tipo de evento no encontrado.';
  elsif not v_tipo_evento_activo then
    raise exception 'El tipo de evento está inactivo.';
  end if;

  if trim(coalesce(p_nombre, '')) = '' then
    raise exception 'El evento debe tener un nombre.';
  end if;

  v_numero := fn_generar_numero_evento_mantencion();

  insert into eventos_mantencion as em (
    numero, codigo, cliente_id, faena_id, tipo_evento, nombre, descripcion,
    criticidad, fecha_plan_inicio, fecha_plan_termino,
    supervisor_id, planificador_id, observaciones, creado_por
  ) values (
    v_numero, p_codigo, p_cliente_id, p_faena_id, p_tipo_evento, p_nombre, p_descripcion,
    p_criticidad, p_fecha_plan_inicio, p_fecha_plan_termino,
    p_supervisor_id, p_planificador_id, p_observaciones, auth.uid()
  )
  returning em.id into v_id;

  return query select v_id, v_numero;
end;
$$;

revoke all on function fn_crear_evento_mantencion(
  uuid, uuid, text, text, uuid, uuid, text, text, timestamptz, timestamptz, text, text
) from public;
grant execute on function fn_crear_evento_mantencion(
  uuid, uuid, text, text, uuid, uuid, text, text, timestamptz, timestamptz, text, text
) to authenticated;

-- ── 2. fn_consolidar_personal_evento() — PRIVADA. Encuentra o crea, por
--       cada fila de plantilla_personal de la plantilla dada, la línea
--       evento_personal_requerido correspondiente en el evento dado.
--       Match por (perfil, especialidad) sobre líneas vigentes
--       (estado_fila <> 'eliminado'). Si no existe, la crea con
--       cantidad_sugerida = 0 (el valor real lo fija el recálculo del
--       paso 7, sumando TODAS las filas de origen activas — no solo la
--       de este equipo). Devuelve el mapeo necesario para crear la fila
--       de origen (paso 6). ──
create or replace function fn_consolidar_personal_evento(
  p_evento_id    uuid,
  p_plantilla_id uuid
)
returns table (plantilla_personal_id uuid, evento_personal_requerido_id uuid, cantidad numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pp           record;
  v_requerido_id uuid;
begin
  for v_pp in
    select pp.id, pp.perfil, pp.especialidad, pp.cantidad
    from plantilla_personal pp
    where pp.plantilla_id = p_plantilla_id
  loop
    select epr.id into v_requerido_id
      from evento_personal_requerido epr
      where epr.evento_mantencion_id = p_evento_id
        and epr.perfil = v_pp.perfil
        and epr.especialidad is not distinct from v_pp.especialidad
        and epr.estado_fila <> 'eliminado'
      limit 1;

    if v_requerido_id is null then
      insert into evento_personal_requerido (
        evento_mantencion_id, perfil, especialidad, cantidad_sugerida, origen, estado_fila, creado_por
      ) values (
        p_evento_id, v_pp.perfil, v_pp.especialidad, 0, 'plantilla', 'sugerido', auth.uid()
      )
      returning evento_personal_requerido.id into v_requerido_id;
    end if;

    plantilla_personal_id := v_pp.id;
    evento_personal_requerido_id := v_requerido_id;
    cantidad := v_pp.cantidad;
    return next;
  end loop;
end;
$$;

revoke all on function fn_consolidar_personal_evento(uuid, uuid) from public, authenticated;

-- ── 3. fn_consolidar_recursos_evento() — PRIVADA. Mismo criterio que la
--       anterior, para plantilla_recursos/evento_recursos. La clave de
--       coincidencia replica EXACTAMENTE la del índice único
--       uq_evento_recursos_vigente (2D-04): categoria_recurso +
--       nombre_generico normalizado (mayúsculas/trim) + coalesce de
--       ambos códigos — así una línea encontrada aquí es, por
--       construcción, la misma que protege ese índice. ──
create or replace function fn_consolidar_recursos_evento(
  p_evento_id    uuid,
  p_plantilla_id uuid
)
returns table (plantilla_recurso_id uuid, evento_recursos_id uuid, cantidad numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pr         record;
  v_recurso_id uuid;
begin
  for v_pr in
    select prec.id, prec.categoria_recurso, prec.nombre_generico,
           prec.herramienta_codigo, prec.insumo_codigo, prec.cantidad_sugerida
    from plantilla_recursos prec
    where prec.plantilla_id = p_plantilla_id
  loop
    select er.id into v_recurso_id
      from evento_recursos er
      where er.evento_mantencion_id = p_evento_id
        and er.categoria_recurso = v_pr.categoria_recurso
        and upper(trim(er.nombre_generico)) = upper(trim(v_pr.nombre_generico))
        and coalesce(er.herramienta_codigo, er.insumo_codigo, '') = coalesce(v_pr.herramienta_codigo, v_pr.insumo_codigo, '')
        and er.estado_fila <> 'eliminado'
      limit 1;

    if v_recurso_id is null then
      insert into evento_recursos (
        evento_mantencion_id, categoria_recurso, nombre_generico, herramienta_codigo, insumo_codigo,
        cantidad_sugerida, origen, estado_fila, creado_por
      ) values (
        p_evento_id, v_pr.categoria_recurso, v_pr.nombre_generico, v_pr.herramienta_codigo, v_pr.insumo_codigo,
        0, 'plantilla', 'sugerido', auth.uid()
      )
      returning evento_recursos.id into v_recurso_id;
    end if;

    plantilla_recurso_id := v_pr.id;
    evento_recursos_id := v_recurso_id;
    cantidad := v_pr.cantidad_sugerida;
    return next;
  end loop;
end;
$$;

revoke all on function fn_consolidar_recursos_evento(uuid, uuid) from public, authenticated;

-- ── 4. fn_recalcular_personal_evento() — PRIVADA y REUTILIZABLE: la
--       llamará tanto este archivo (paso 7, al agregar un equipo) como
--       2D-07 (al quitar uno). Recalcula cantidad_sugerida de TODAS las
--       líneas vigentes del evento como la suma de sus filas de origen
--       ACTIVAS — nunca escribe cantidad_aprobada. ──
create or replace function fn_recalcular_personal_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update evento_personal_requerido epr
  set cantidad_sugerida = coalesce((
        select sum(epo.cantidad_aportada)
        from evento_personal_origen epo
        where epo.evento_personal_requerido_id = epr.id
          and epo.estado = 'activo'
      ), 0)
  where epr.evento_mantencion_id = p_evento_id
    and epr.estado_fila <> 'eliminado';
end;
$$;

revoke all on function fn_recalcular_personal_evento(uuid) from public, authenticated;

-- ── 5. fn_recalcular_recursos_evento() — PRIVADA y REUTILIZABLE, mismo
--       criterio que la anterior para evento_recursos/evento_recursos_origen. ──
create or replace function fn_recalcular_recursos_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update evento_recursos er
  set cantidad_sugerida = coalesce((
        select sum(ero.cantidad_aportada)
        from evento_recursos_origen ero
        where ero.evento_recursos_id = er.id
          and ero.estado = 'activo'
      ), 0)
  where er.evento_mantencion_id = p_evento_id
    and er.estado_fila <> 'eliminado';
end;
$$;

revoke all on function fn_recalcular_recursos_evento(uuid) from public, authenticated;

-- ── 6. fn_agregar_equipo_evento() — orquesta los 8 pasos documentados
--       arriba, usando las 4 funciones privadas anteriores. ──
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
  -- ═══ Paso 1: validar ═══
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

  if v_evento_estado in ('cerrada','cancelada') then
    raise exception 'No se pueden agregar equipos a un evento en estado %.', v_evento_estado;
  end if;

  if auth.uid() <> v_evento_supervisor and not es_admin() then
    raise exception 'Solo el supervisor del evento o un administrador puede agregar equipos.';
  end if;

  -- Jerarquía completa equipo → área → faena → cliente, validada contra
  -- el cliente/faena REALES del evento (reutiliza fn_validar_jerarquia_equipo, 2B).
  perform fn_validar_jerarquia_equipo(v_evento_cliente_id, v_evento_faena_id, p_area_id, p_equipo_id);

  -- Duplicado: verificado EN CÓDIGO antes del insert — no se confía solo
  -- en uq_mantenciones_evento_equipo (2D-02), que sigue existiendo como
  -- resguardo ante condiciones de carrera, no como única defensa.
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

  -- ═══ Paso 2: crear mantención ═══
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

  -- ═══ Paso 3: snapshot reducido (solo actividades + protocolos) ═══
  -- Idéntico, línea por línea, al bloque equivalente de fn_crear_mantencion
  -- (2C) — mismo criterio, sin modificar esa función.
  insert into mantencion_actividades (
    mantencion_id, plantilla_actividad_id, codigo_actividad, descripcion, orden,
    depende_de, duracion_estimada_horas, obligatoria, origen, estado_fila, creado_por
  )
  select v_mant_id, pa.id, pa.codigo_actividad, pa.descripcion, pa.orden,
         pa.depende_de, pa.duracion_estimada_horas, pa.obligatoria, 'plantilla', 'sugerido', auth.uid()
  from plantilla_actividades pa
  where pa.plantilla_id = p_plantilla_id;

  insert into mantencion_protocolos (
    mantencion_id, plantilla_protocolo_id, tipo_protocolo, obligatorio, origen, estado_fila, creado_por
  )
  select v_mant_id, ppr.id, ppr.tipo_protocolo, ppr.obligatorio, 'plantilla', 'sugerido', auth.uid()
  from plantilla_protocolos ppr
  where ppr.plantilla_id = p_plantilla_id;

  -- ═══ Pasos 4 y 6 (personal): consolidar + crear fila de origen ═══
  -- fn_consolidar_personal_evento() (paso 4) resuelve o crea cada línea;
  -- el INSERT ... SELECT que consume su resultado crea la fila de origen
  -- (paso 6) para cada una, en el mismo recorrido.
  insert into evento_personal_origen (
    evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
  )
  select cp.evento_personal_requerido_id, v_mant_id, cp.plantilla_personal_id, cp.cantidad, auth.uid()
  from fn_consolidar_personal_evento(p_evento_id, p_plantilla_id) cp;

  -- ═══ Pasos 5 y 6 (recursos): mismo criterio que personal ═══
  insert into evento_recursos_origen (
    evento_recursos_id, mantencion_id, plantilla_recurso_id, cantidad_aportada, creado_por
  )
  select cr.evento_recursos_id, v_mant_id, cr.plantilla_recurso_id, cr.cantidad, auth.uid()
  from fn_consolidar_recursos_evento(p_evento_id, p_plantilla_id) cr;

  -- ═══ Paso 7: recalcular cantidades sugeridas ═══
  perform fn_recalcular_personal_evento(p_evento_id);
  perform fn_recalcular_recursos_evento(p_evento_id);

  -- ═══ Paso 8: actualizar estados del evento ═══
  -- Cualquier cambio en las listas consolidadas exige nueva revisión del
  -- supervisor. cantidad_aprobada nunca se toca aquí (solo la tocan las
  -- funciones de aprobación de 2D-07).
  update eventos_mantencion as em2
  set personal_estado = 'en_revision',
      recursos_estado = 'en_revision'
  where em2.id = p_evento_id;

  return query select v_mant_id, v_numero;
end;
$$;

revoke all on function fn_agregar_equipo_evento(
  uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text
) from public;
grant execute on function fn_agregar_equipo_evento(
  uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text
) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Funciones creadas y sus privilegios:
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace
--     and p.proname in (
--       'fn_crear_evento_mantencion', 'fn_agregar_equipo_evento',
--       'fn_consolidar_personal_evento', 'fn_consolidar_recursos_evento',
--       'fn_recalcular_personal_evento', 'fn_recalcular_recursos_evento'
--     )
--   order by p.proname;
-- -- Las 4 funciones privadas deben mostrar "false"; las 2 públicas, "true".
--
-- 2) Prueba de punta a punta (con datos reales, dentro de una transacción
--    que termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_funciones_creacion_etapa2d06.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop function if exists public.fn_agregar_equipo_evento(uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text);
-- drop function if exists public.fn_recalcular_recursos_evento(uuid);
-- drop function if exists public.fn_recalcular_personal_evento(uuid);
-- drop function if exists public.fn_consolidar_recursos_evento(uuid, uuid);
-- drop function if exists public.fn_consolidar_personal_evento(uuid, uuid);
-- drop function if exists public.fn_crear_evento_mantencion(uuid, uuid, text, text, uuid, uuid, text, text, timestamptz, timestamptz, text, text);
