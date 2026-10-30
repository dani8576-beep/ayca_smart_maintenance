-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.08
-- Rollup automático de estados del evento
--
-- PROPÓSITO:
-- Derivar automáticamente "estado", "ejecucion_estado" y "revision_estado"
-- de eventos_mantencion a partir de sus mantenciones hijas VIGENTES
-- (estado <> 'cancelada'), en vez de dejarlos como campos de escritura
-- libre. "planificacion_estado" NO se toca — sigue siendo de uso manual
-- del planificador.
--
-- ── CAMBIO DE VOCABULARIO (decisión explícita, ver conversación) ──
-- El CHECK de estado/ejecucion_estado/revision_estado en eventos_mantencion
-- (2D-01) usaba un vocabulario que no alcanzaba a cubrir las reglas de
-- rollup pedidas aquí, y que además chocaba con dos CHECK cruzados que
-- asumían un modelo distinto (estado cambiando solo a mano, en conjunto
-- con los demás campos). Se editó 2D-01 directamente (todavía no
-- ejecutado en ningún ambiente) para:
--   - estado:           borrador / planificado / en_ejecucion / finalizado / cancelado
--   - ejecucion_estado:  sin_equipos / pendiente / en_ejecucion / parcial / completado
--   - revision_estado:   pendiente / en_revision / parcial / aprobado / no_aplica
--   - Eliminar los 2 CHECK cruzados que ya no aplican con rollup automático.
-- Como consecuencia, esta migración también actualiza (CREATE OR REPLACE)
-- fn_validar_supervisor_evento(), fn_agregar_equipo_evento() y
-- fn_quitar_equipo_evento() (2D-07), que comparaban el estado del evento
-- contra 'cerrada'/'cancelada' — ahora comparan contra
-- 'finalizado'/'cancelado'. Ningún otro comportamiento de esas funciones
-- cambia.
--
-- ── DISEÑO: 3 funciones puras de cálculo + 1 función que aplica ──
-- fn_calcular_ejecucion_estado_evento(evento_id) → text
-- fn_calcular_estado_evento(evento_id)           → text  (reutiliza la anterior)
-- fn_calcular_revision_estado_evento(evento_id)  → text
-- Ninguna de las tres escribe nada — solo calculan, a partir del estado
-- ACTUAL de las mantenciones hijas y de personal_estado/recursos_estado.
-- Son la lógica "reutilizable" pedida: cualquier función futura puede
-- llamarlas para saber qué debería valer un campo, sin duplicar reglas.
--
-- fn_recalcular_estados_evento(evento_id) → void   (privada)
-- Es la única que ESCRIBE los 3 campos, y la única que aplica la regla
-- "no sobrescribir un evento cancelado": si eventos_mantencion.estado ya
-- es 'cancelado', no hace nada. 'cancelado' es un estado terminal que
-- solo se alcanza por una función explícita de cancelación de evento
-- (todavía no existe esa función — cuando se cree, será la única vía).
--
-- ── DÓNDE SE INTEGRA (sin duplicar la integración en 10+ funciones) ──
-- fn_actualizar_estado_revision() (2D-07) YA es el único punto de
-- escritura de personal_estado/recursos_estado, y YA es llamada al
-- final de las 10 funciones de ajuste/aprobación de personal y recursos
-- (2D-07) más fn_agregar_equipo_evento()/fn_quitar_equipo_evento(). Se
-- extiende aquí (CREATE OR REPLACE, misma firma) para que, además de
-- fijar personal_estado o recursos_estado, recalcule también
-- revision_estado con fn_calcular_revision_estado_evento() — así las
-- "operaciones de aprobación que afecten revisión" (y también agregar/
-- quitar/modificar personal o recursos, que son las mismas que ya
-- llaman a esta función) quedan cubiertas SIN tocar esas 10 funciones
-- una por una.
-- estado/ejecucion_estado NO dependen de personal_estado/recursos_estado
-- (solo de las mantenciones hijas), así que no tiene sentido recalcularlos
-- ahí — se integran explícitamente, como pide el enunciado, al FINAL de
-- fn_agregar_equipo_evento() y fn_quitar_equipo_evento() (las únicas dos
-- funciones que agregan o quitan mantenciones hijas), con una llamada a
-- fn_recalcular_estados_evento().
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql (YA EDITADO
--     con el vocabulario nuevo — re-ejecutar si ya se había corrido antes)
--   - 2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql
--   - 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql
--
-- NO modifica RLS (2D-09). NO crea una función de cancelación explícita
-- de evento (fuera de alcance de esta etapa) — el rollup simplemente
-- respeta 'cancelado' como terminal si algo más lo pone en ese estado.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regprocedure('public.fn_actualizar_estado_revision(uuid,text)') is null then
    raise exception 'Falta fn_actualizar_estado_revision() — ejecutar primero 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql';
  end if;

  if to_regprocedure('public.fn_validar_supervisor_evento(uuid)') is null then
    raise exception 'Falta fn_validar_supervisor_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql';
  end if;

  if to_regprocedure('public.fn_agregar_equipo_evento(uuid,uuid,uuid,uuid,uuid,text,timestamptz,timestamptz,text)') is null then
    raise exception 'Falta fn_agregar_equipo_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql';
  end if;

  if to_regprocedure('public.fn_quitar_equipo_evento(uuid,text)') is null then
    raise exception 'Falta fn_quitar_equipo_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.eventos_mantencion'::regclass
      and conname = 'eventos_mantencion_estado_check'
  ) then
    raise exception 'El CHECK de eventos_mantencion.estado todavía tiene el vocabulario antiguo — volver a ejecutar 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql (ya editado) antes de este archivo.';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN A — Funciones puras de cálculo (no escriben nada)
-- ═══════════════════════════════════════════════════════════════

-- fn_calcular_ejecucion_estado_evento() — a partir del ejecucion_estado
-- de las mantenciones VIGENTES (estado <> 'cancelada') del evento:
--   sin_equipos → no hay mantenciones vigentes.
--   en_ejecucion → al menos una está 'en_curso' ahora mismo (prioridad
--                  máxima: si algo está corriendo, el evento está en
--                  ejecución, sin importar el resto).
--   completado  → TODAS están 'completada'.
--   pendiente   → TODAS están 'no_iniciada'.
--   parcial     → cualquier otra mezcla (ej. completada + no_iniciada,
--                  o alguna 'pausada') — algo avanzó pero nada corre
--                  ahora mismo y no todo terminó.
create or replace function fn_calcular_ejecucion_estado_evento(p_evento_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total        int;
  v_en_curso     int;
  v_completadas  int;
  v_no_iniciadas int;
begin
  select count(*),
         count(*) filter (where m.ejecucion_estado = 'en_curso'),
         count(*) filter (where m.ejecucion_estado = 'completada'),
         count(*) filter (where m.ejecucion_estado = 'no_iniciada')
    into v_total, v_en_curso, v_completadas, v_no_iniciadas
    from mantenciones m
    where m.evento_mantencion_id = p_evento_id
      and m.estado <> 'cancelada';

  if v_total = 0 then
    return 'sin_equipos';
  elsif v_en_curso > 0 then
    return 'en_ejecucion';
  elsif v_completadas = v_total then
    return 'completado';
  elsif v_no_iniciadas = v_total then
    return 'pendiente';
  else
    return 'parcial';
  end if;
end;
$$;

revoke all on function fn_calcular_ejecucion_estado_evento(uuid) from public, authenticated;

-- fn_calcular_estado_evento() — mapeo DIRECTO desde ejecucion_estado
-- (reutiliza fn_calcular_ejecucion_estado_evento en vez de repetir el
-- conteo): 'en_ejecucion' y 'parcial' del ejecucion_estado colapsan en
-- el único estado intermedio 'en_ejecucion' del evento — el enunciado
-- pide solo 4 valores automáticos (borrador/planificado/en_ejecucion/
-- finalizado), no 5, así que cualquier mezcla que no sea "todo pendiente"
-- ni "todo completado" cae en 'en_ejecucion'. 'cancelado' NUNCA se
-- calcula aquí — solo por acción explícita (ver fn_recalcular_estados_evento).
create or replace function fn_calcular_estado_evento(p_evento_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ejecucion text;
begin
  v_ejecucion := fn_calcular_ejecucion_estado_evento(p_evento_id);

  return case v_ejecucion
    when 'sin_equipos' then 'borrador'
    when 'pendiente'   then 'planificado'
    when 'completado'  then 'finalizado'
    else 'en_ejecucion' -- cubre 'en_ejecucion' y 'parcial'
  end;
end;
$$;

revoke all on function fn_calcular_estado_evento(uuid) from public, authenticated;

-- fn_calcular_revision_estado_evento() — combina TRES señales de
-- revisión en una sola: el revision_estado de cada mantención vigente
-- ('aprobada' cuenta como conforme; cualquier otro valor no), y
-- personal_estado/recursos_estado del propio evento ('aprobado' cuenta
-- como conforme). Cada mantención vigente aporta 1 unidad; personal y
-- recursos SIEMPRE aportan 1 unidad cada uno (así haya o no mantenciones).
--
-- Interpretación de "pendiente" vs. "en_revision" (el enunciado no
-- especifica el límite exacto entre ambos, así que se deja documentado
-- el criterio adoptado): "pendiente" es el caso más estricto de
-- "nada conforme" — CUALQUIER señal ya tocada (una mantención en
-- 'en_revision'/'observada', o personal/recursos ya en 'en_revision' o
-- 'parcial') sube a "en_revision" en vez de "pendiente", porque indica
-- que ya empezó actividad de revisión aunque nada esté aprobado todavía.
create or replace function fn_calcular_revision_estado_evento(p_evento_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_personal_estado text;
  v_recursos_estado text;
  v_mant_total       int;
  v_mant_aprobadas   int;
  v_mant_baseline    int; -- vigentes con revision_estado = 'pendiente'
  v_total_unidades   int;
  v_conformes        int;
  v_todo_en_baseline boolean;
begin
  select em.personal_estado, em.recursos_estado
    into v_personal_estado, v_recursos_estado
    from eventos_mantencion em
    where em.id = p_evento_id;

  select count(*),
         count(*) filter (where m.revision_estado = 'aprobada'),
         count(*) filter (where m.revision_estado = 'pendiente')
    into v_mant_total, v_mant_aprobadas, v_mant_baseline
    from mantenciones m
    where m.evento_mantencion_id = p_evento_id
      and m.estado <> 'cancelada';

  -- Evento realmente vacío: sin mantenciones vigentes y sin personal ni
  -- recursos consolidados todavía — no hay nada que revisar.
  if v_mant_total = 0 and v_personal_estado = 'pendiente' and v_recursos_estado = 'pendiente' then
    return 'no_aplica';
  end if;

  v_total_unidades := v_mant_total + 2; -- +1 personal, +1 recursos, siempre
  v_conformes := v_mant_aprobadas
    + (case when v_personal_estado = 'aprobado' then 1 else 0 end)
    + (case when v_recursos_estado = 'aprobado' then 1 else 0 end);

  if v_conformes = v_total_unidades then
    return 'aprobado';
  end if;

  v_todo_en_baseline := (v_mant_baseline = v_mant_total)
    and v_personal_estado = 'pendiente'
    and v_recursos_estado = 'pendiente';

  if v_conformes = 0 and v_todo_en_baseline then
    return 'pendiente';
  elsif v_conformes = 0 then
    return 'en_revision';
  else
    return 'parcial';
  end if;
end;
$$;

revoke all on function fn_calcular_revision_estado_evento(uuid) from public, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN B — Aplicación (única función que escribe estado/ejecucion_estado/revision_estado)
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_recalcular_estados_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado_actual text;
begin
  select em.estado into v_estado_actual from eventos_mantencion em where em.id = p_evento_id;

  if v_estado_actual is null then
    raise exception 'El evento de mantención indicado (%) no existe.', p_evento_id;
  end if;

  -- No sobrescribir un evento cancelado mediante rollup automático.
  if v_estado_actual = 'cancelado' then
    return;
  end if;

  update eventos_mantencion
  set estado           = fn_calcular_estado_evento(p_evento_id),
      ejecucion_estado = fn_calcular_ejecucion_estado_evento(p_evento_id),
      revision_estado  = fn_calcular_revision_estado_evento(p_evento_id)
  where id = p_evento_id;
end;
$$;

revoke all on function fn_recalcular_estados_evento(uuid) from public, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN C — Integración: extender fn_actualizar_estado_revision (2D-07)
-- para que también recalcule revision_estado
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_actualizar_estado_revision(
  p_evento_id uuid,
  p_ambito    text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total      int;
  v_conformes  int;
  v_nuevo_estado text;
begin
  if p_ambito = 'personal' then
    select count(*),
           count(*) filter (where cantidad_aprobada is not null and cantidad_aprobada = cantidad_sugerida)
      into v_total, v_conformes
      from evento_personal_requerido
      where evento_mantencion_id = p_evento_id and estado_fila <> 'eliminado';
  elsif p_ambito = 'recursos' then
    select count(*),
           count(*) filter (where cantidad_aprobada is not null and cantidad_aprobada = cantidad_sugerida)
      into v_total, v_conformes
      from evento_recursos
      where evento_mantencion_id = p_evento_id and estado_fila <> 'eliminado';
  else
    raise exception 'Ámbito no reconocido: % (debe ser ''personal'' o ''recursos'').', p_ambito;
  end if;

  if v_total = 0 then
    v_nuevo_estado := 'pendiente';
  elsif v_conformes = v_total then
    v_nuevo_estado := 'aprobado';
  elsif v_conformes = 0 then
    v_nuevo_estado := 'en_revision';
  else
    v_nuevo_estado := 'parcial';
  end if;

  if p_ambito = 'personal' then
    update eventos_mantencion set personal_estado = v_nuevo_estado where id = p_evento_id;
  else
    update eventos_mantencion set recursos_estado = v_nuevo_estado where id = p_evento_id;
  end if;

  -- 2D-08: revision_estado combina personal_estado + recursos_estado +
  -- revisión de mantenciones — se recalcula aquí, en el único punto de
  -- escritura de personal_estado/recursos_estado, para que las 10
  -- funciones de ajuste/aprobación de 2D-07 (y fn_agregar_equipo_evento/
  -- fn_quitar_equipo_evento, que también llaman a esta función) queden
  -- cubiertas sin duplicar la integración en cada una.
  update eventos_mantencion
  set revision_estado = fn_calcular_revision_estado_evento(p_evento_id)
  where id = p_evento_id;
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN D — Actualizar vocabulario 'cerrada'/'cancelada' → 'finalizado'/'cancelado'
-- en las funciones que comparan contra el estado del EVENTO, e integrar
-- el rollup completo al final de agregar/quitar equipo
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_validar_supervisor_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supervisor_id uuid;
  v_estado        text;
begin
  select supervisor_id, estado into v_supervisor_id, v_estado
    from eventos_mantencion where id = p_evento_id;

  if v_supervisor_id is null then
    raise exception 'El evento de mantención indicado (%) no existe.', p_evento_id;
  end if;

  if auth.uid() <> v_supervisor_id and not es_admin() then
    raise exception 'Solo el supervisor del evento o un administrador puede realizar esta acción.';
  end if;

  if v_estado in ('finalizado','cancelado') then
    raise exception 'No se puede modificar un evento en estado %.', v_estado;
  end if;
end;
$$;

-- fn_agregar_equipo_evento(): mismo cuerpo que 2D-07, con dos cambios
-- puntuales — (a) 'cerrada'/'cancelada' → 'finalizado'/'cancelado' al
-- validar el estado del evento, (b) llamada a fn_recalcular_estados_evento()
-- al final, para que estado/ejecucion_estado también reflejen la
-- mantención recién agregada.
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

  -- 2D-08: recalcula estado/ejecucion_estado/revision_estado a partir de
  -- TODAS las mantenciones hijas vigentes, incluida la recién creada.
  perform fn_recalcular_estados_evento(p_evento_id);

  return query select v_mant_id, v_numero;
end;
$$;

-- fn_quitar_equipo_evento(): mismo cuerpo que 2D-07, agregando la
-- llamada a fn_recalcular_estados_evento() al final (la comparación
-- v_estado in ('cancelada','cerrada') de aquí es sobre el estado de la
-- MANTENCIÓN, no del evento — ese vocabulario no cambió, sigue siendo
-- el de 2B/2C).
create or replace function fn_quitar_equipo_evento(
  p_mantencion_id uuid,
  p_motivo        text default null
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
  select evento_mantencion_id, estado into v_evento_id, v_estado
    from mantenciones where id = p_mantencion_id;

  if v_estado is null then
    raise exception 'La mantención indicada (%) no existe.', p_mantencion_id;
  end if;

  if v_evento_id is null then
    raise exception 'Esta mantención no pertenece a ningún evento — no corresponde usar esta función (es para el flujo multiequipo).';
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado in ('cancelada','cerrada') then
    raise exception 'Esta mantención ya está % — no se puede quitar del evento.', v_estado;
  end if;

  update mantenciones
  set estado = 'cancelada'
  where id = p_mantencion_id;

  update evento_personal_origen
  set estado = 'retirado',
      retirado_por = auth.uid(),
      retirado_en = now(),
      motivo_retiro = coalesce(p_motivo, 'Equipo retirado del evento')
  where mantencion_id = p_mantencion_id
    and estado = 'activo';

  update evento_recursos_origen
  set estado = 'retirado',
      retirado_por = auth.uid(),
      retirado_en = now(),
      motivo_retiro = coalesce(p_motivo, 'Equipo retirado del evento')
  where mantencion_id = p_mantencion_id
    and estado = 'activo';

  perform fn_recalcular_personal_evento(v_evento_id);
  perform fn_recalcular_recursos_evento(v_evento_id);

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');

  -- 2D-08: recalcula estado/ejecucion_estado/revision_estado — el equipo
  -- retirado ya no cuenta como vigente para ninguno de los 3.
  perform fn_recalcular_estados_evento(v_evento_id);
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) CHECK de eventos_mantencion con el vocabulario nuevo:
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conrelid = 'public.eventos_mantencion'::regclass
--     and conname in ('eventos_mantencion_estado_check','eventos_mantencion_ejecucion_estado_check','eventos_mantencion_revision_estado_check');
--
-- 2) Funciones de este archivo y sus privilegios:
-- select p.proname, has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace
--     and p.proname in (
--       'fn_calcular_estado_evento','fn_calcular_ejecucion_estado_evento',
--       'fn_calcular_revision_estado_evento','fn_recalcular_estados_evento'
--     )
--   order by p.proname;
-- -- Las 4 deben mostrar "false" (privadas).
--
-- 3) Prueba de punta a punta (con datos reales, dentro de una transacción
--    que termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_rollup_estados_etapa2d08.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- -- Revertir fn_agregar_equipo_evento()/fn_quitar_equipo_evento()/
-- -- fn_validar_supervisor_evento()/fn_actualizar_estado_revision() a su
-- -- versión de 2D-07 requiere volver a ejecutar el CREATE OR REPLACE de
-- -- 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql.
-- drop function if exists public.fn_recalcular_estados_evento(uuid);
-- drop function if exists public.fn_calcular_revision_estado_evento(uuid);
-- drop function if exists public.fn_calcular_estado_evento(uuid);
-- drop function if exists public.fn_calcular_ejecucion_estado_evento(uuid);
-- -- Revertir el vocabulario de eventos_mantencion requiere además
-- -- deshacer manualmente la edición de 2D-01 (restaurar el CHECK y los
-- -- 2 CHECK cruzados originales) y actualizar cualquier fila existente
-- -- que ya tenga los valores nuevos.
