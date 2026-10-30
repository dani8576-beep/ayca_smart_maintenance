-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.07
-- Funciones de ajuste manual y aprobación — cierre del flujo de
-- planificación multiequipo
--
-- PROPÓSITO:
-- Dejar operativo el ciclo completo de planificación de un evento:
-- quitar un equipo, y que el supervisor pueda agregar/quitar/modificar/
-- aprobar personal y recursos de forma manual, sin que el "motor"
-- automático (consolidación + recálculo) pise nunca una aprobación ya
-- dada.
--
-- ── SEPARACIÓN MOTOR vs. MANUAL (principio rector de este archivo) ──
--   MOTOR (automático, dispara con agregar/quitar un equipo):
--     - fn_consolidar_personal_evento() / fn_consolidar_recursos_evento() (2D-06)
--     - fn_recalcular_personal_evento() / fn_recalcular_recursos_evento() (2D-06,
--       CORREGIDAS aquí — ver más abajo)
--     - fn_quitar_equipo_evento() (nueva en este archivo)
--     El motor SOLO escribe cantidad_sugerida. NUNCA escribe
--     cantidad_aprobada — esa columna es exclusivamente del supervisor.
--   MANUAL (el supervisor decide, nunca se dispara solo):
--     - agregar/quitar/modificar líneas de origen 'manual'
--     - aprobar (fija cantidad_aprobada), sea el origen que sea
--
-- ── CORRECCIÓN A 2D-06 (antes de agregar funciones nuevas) ──
-- Al diseñar el alta manual se detectó un defecto real en las funciones
-- de recálculo de 2D-06: recalculaban cantidad_sugerida de TODAS las
-- líneas vigentes del evento, sin distinguir origen. Eso significa que
-- una línea 'manual' (que no tiene filas de origen por equipo, porque no
-- proviene de ninguna plantilla) quedaría en cantidad_sugerida = 0 la
-- próxima vez que se agregara o quitara cualquier equipo — borrando
-- silenciosamente el valor que el supervisor acaba de definir. Se
-- corrige aquí restringiendo el recálculo a origen = 'plantilla'
-- (CREATE OR REPLACE, misma firma, mismo contrato — igual criterio que
-- ya usó el archivo de corrección de 2C para fn_crear_mantencion()).
--
-- También se actualiza fn_agregar_equipo_evento() (2D-06) para que su
-- paso 8 use la nueva función reutilizable fn_actualizar_estado_revision()
-- en vez de fijar 'en_revision' de forma directa — así el paso 8 de
-- agregar un equipo y el de quitarlo (este archivo) comparten EXACTAMENTE
-- la misma lógica de estados, sin duplicarla.
--
-- ── FUNCIÓN REUTILIZABLE DE ESTADOS ──
-- fn_actualizar_estado_revision(p_evento_id, p_ambito) centraliza la
-- regla de personal_estado/recursos_estado, para no repetirla en cada
-- función de ajuste/aprobación:
--   - 0 líneas vigentes                          → 'pendiente'
--   - todas las líneas vigentes aprobadas Y con
--     cantidad_aprobada = cantidad_sugerida       → 'aprobado'
--   - ninguna línea vigente está en ese estado
--     "aprobada y conforme"                       → 'en_revision'
--   - una mezcla de ambas                         → 'parcial'
-- "Conforme" excluye a propósito una aprobación que quedó desalineada
-- tras un recálculo (aprobada ≠ sugerida) — necesita revisión igual que
-- una línea nunca aprobada, que es exactamente el caso que pide cubrir
-- "si una modificación manual cambia el equilibrio entre sugerido y
-- aprobado".
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-18_mantenciones_etapa2d_03_personal.sql
--   - 2026-07-18_mantenciones_etapa2d_04_recursos.sql
--   - 2026-07-18_mantenciones_etapa2d_05_trazabilidad.sql
--   - 2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql
--
-- NO modifica RLS (2D-09). NO crea funciones para evento_personal_asignado
-- (asignación de personas reales) — no estaba en el alcance pedido para
-- esta etapa; queda pendiente para cuando se aborde ese frente.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regprocedure('public.fn_recalcular_personal_evento(uuid)') is null
     or to_regprocedure('public.fn_recalcular_recursos_evento(uuid)') is null
     or to_regprocedure('public.fn_agregar_equipo_evento(uuid,uuid,uuid,uuid,uuid,text,timestamptz,timestamptz,text)') is null then
    raise exception 'Faltan funciones de 2D-06 — ejecutar primero 2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql';
  end if;

  if to_regclass('public.evento_personal_origen') is null or to_regclass('public.evento_recursos_origen') is null then
    raise exception 'Faltan evento_personal_origen/evento_recursos_origen — ejecutar primero 2026-07-18_mantenciones_etapa2d_05_trazabilidad.sql';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN A — Correcciones a funciones de 2D-06
-- ═══════════════════════════════════════════════════════════════

-- ── A.1 fn_recalcular_personal_evento() — agrega "and origen = 'plantilla'" ──
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
    and epr.estado_fila <> 'eliminado'
    and epr.origen = 'plantilla';
end;
$$;

-- ── A.2 fn_recalcular_recursos_evento() — mismo criterio ──
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
    and er.estado_fila <> 'eliminado'
    and er.origen = 'plantilla';
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN B — Función reutilizable de estados de revisión
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
end;
$$;

revoke all on function fn_actualizar_estado_revision(uuid, text) from public, authenticated;

-- ── B.1 fn_agregar_equipo_evento() (2D-06) — su paso 8 ahora usa la
--       función reutilizable de arriba en vez de fijar 'en_revision'
--       directamente. Mismo cuerpo que 2D-06 en todo lo demás. ──
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

  if v_evento_estado in ('cerrada','cancelada') then
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

  -- Paso 8, actualizado: usa la función reutilizable en vez de fijar
  -- 'en_revision' directamente (mismo resultado práctico para un evento
  -- recién creado, pero ahora comparte lógica con fn_quitar_equipo_evento).
  perform fn_actualizar_estado_revision(p_evento_id, 'personal');
  perform fn_actualizar_estado_revision(p_evento_id, 'recursos');

  return query select v_mant_id, v_numero;
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN C — Función privada compartida de permisos
-- ═══════════════════════════════════════════════════════════════

-- fn_validar_supervisor_evento() — evita repetir en cada función de
-- ajuste el mismo bloque de "el evento existe, quien llama es su
-- supervisor o admin, y el evento no está cerrado/cancelado".
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

  if v_estado in ('cerrada','cancelada') then
    raise exception 'No se puede modificar un evento en estado %.', v_estado;
  end if;
end;
$$;

revoke all on function fn_validar_supervisor_evento(uuid) from public, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN D — Motor: quitar un equipo del evento
-- ═══════════════════════════════════════════════════════════════

-- fn_quitar_equipo_evento() — cancela la mantención de un equipo dentro
-- de un evento, RETIRA (nunca borra) sus filas de origen activas, y
-- reutiliza EXACTAMENTE fn_recalcular_personal_evento()/
-- fn_recalcular_recursos_evento() (2D-06) para recomputar
-- cantidad_sugerida — la misma función que usa fn_agregar_equipo_evento.
-- cantidad_aprobada nunca se toca aquí.
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

  -- Mismas funciones de recálculo que usa fn_agregar_equipo_evento (2D-06) —
  -- reutilizadas sin duplicar su lógica.
  perform fn_recalcular_personal_evento(v_evento_id);
  perform fn_recalcular_recursos_evento(v_evento_id);

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');
end;
$$;

revoke all on function fn_quitar_equipo_evento(uuid, text) from public;
grant execute on function fn_quitar_equipo_evento(uuid, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN E — Ajuste manual: personal
-- ═══════════════════════════════════════════════════════════════

-- fn_agregar_personal_manual_evento() — alta manual, origen='manual'.
create or replace function fn_agregar_personal_manual_evento(
  p_evento_id         uuid,
  p_perfil            text,
  p_cantidad_sugerida numeric,
  p_especialidad      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform fn_validar_supervisor_evento(p_evento_id);

  if trim(coalesce(p_perfil, '')) = '' then
    raise exception 'Debe indicar un perfil.';
  end if;

  if p_cantidad_sugerida <= 0 then
    raise exception 'La cantidad sugerida debe ser mayor a 0.';
  end if;

  insert into evento_personal_requerido (
    evento_mantencion_id, perfil, especialidad, cantidad_sugerida, origen, estado_fila, creado_por
  ) values (
    p_evento_id, p_perfil, p_especialidad, p_cantidad_sugerida, 'manual', 'agregado', auth.uid()
  )
  returning evento_personal_requerido.id into v_id;

  perform fn_actualizar_estado_revision(p_evento_id, 'personal');

  return v_id;
end;
$$;

revoke all on function fn_agregar_personal_manual_evento(uuid, text, numeric, text) from public;
grant execute on function fn_agregar_personal_manual_evento(uuid, text, numeric, text) to authenticated;

-- fn_quitar_personal_evento() — baja (soft delete) de CUALQUIER línea
-- vigente, sea su origen 'plantilla' o 'manual' — el supervisor puede
-- decidir que ya no se necesita, incluso si varios equipos la sugirieron.
create or replace function fn_quitar_personal_evento(
  p_evento_personal_requerido_id uuid,
  p_motivo_modificacion           text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id   uuid;
  v_estado_fila text;
begin
  select evento_mantencion_id, estado_fila into v_evento_id, v_estado_fila
    from evento_personal_requerido where id = p_evento_personal_requerido_id;

  if v_evento_id is null then
    raise exception 'La línea de personal requerido indicada (%) no existe.', p_evento_personal_requerido_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'Esta línea ya fue eliminada.';
  end if;

  if trim(coalesce(p_motivo_modificacion, '')) = '' then
    raise exception 'Debe indicar un motivo para eliminar esta línea.';
  end if;

  update evento_personal_requerido
  set estado_fila = 'eliminado',
      motivo_modificacion = p_motivo_modificacion
  where id = p_evento_personal_requerido_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
end;
$$;

revoke all on function fn_quitar_personal_evento(uuid, text) from public;
grant execute on function fn_quitar_personal_evento(uuid, text) to authenticated;

-- fn_modificar_personal_manual_evento() — SOLO sobre líneas origen =
-- 'manual'. Una línea 'plantilla' se recalcula sola al agregar/quitar
-- equipos — modificarla a mano rompería esa garantía en el siguiente
-- recálculo.
create or replace function fn_modificar_personal_manual_evento(
  p_evento_personal_requerido_id uuid,
  p_cantidad_sugerida             numeric,
  p_motivo_modificacion            text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id   uuid;
  v_origen      text;
  v_estado_fila text;
begin
  select evento_mantencion_id, origen, estado_fila into v_evento_id, v_origen, v_estado_fila
    from evento_personal_requerido where id = p_evento_personal_requerido_id;

  if v_evento_id is null then
    raise exception 'La línea de personal requerido indicada (%) no existe.', p_evento_personal_requerido_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'No se puede modificar una línea ya eliminada.';
  end if;

  if v_origen <> 'manual' then
    raise exception 'Solo se puede modificar directamente la cantidad sugerida de una línea manual. Las líneas derivadas de plantilla se recalculan automáticamente al agregar o quitar equipos.';
  end if;

  if p_cantidad_sugerida < 0 then
    raise exception 'La cantidad sugerida no puede ser negativa.';
  end if;

  if trim(coalesce(p_motivo_modificacion, '')) = '' then
    raise exception 'Debe indicar un motivo para modificar esta línea.';
  end if;

  update evento_personal_requerido
  set cantidad_sugerida = p_cantidad_sugerida,
      estado_fila = 'modificado',
      motivo_modificacion = p_motivo_modificacion
  where id = p_evento_personal_requerido_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
end;
$$;

revoke all on function fn_modificar_personal_manual_evento(uuid, numeric, text) from public;
grant execute on function fn_modificar_personal_manual_evento(uuid, numeric, text) to authenticated;

-- fn_aprobar_personal_evento() — aprobación de UNA línea (cualquier
-- origen). Si no se indica p_cantidad_aprobada, aprueba exactamente lo
-- sugerido.
create or replace function fn_aprobar_personal_evento(
  p_evento_personal_requerido_id uuid,
  p_cantidad_aprobada             numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id         uuid;
  v_estado_fila       text;
  v_cantidad_sugerida numeric;
  v_cantidad_final    numeric;
begin
  select evento_mantencion_id, estado_fila, cantidad_sugerida
    into v_evento_id, v_estado_fila, v_cantidad_sugerida
    from evento_personal_requerido where id = p_evento_personal_requerido_id;

  if v_evento_id is null then
    raise exception 'La línea de personal requerido indicada (%) no existe.', p_evento_personal_requerido_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'No se puede aprobar una línea eliminada.';
  end if;

  v_cantidad_final := coalesce(p_cantidad_aprobada, v_cantidad_sugerida);

  if v_cantidad_final < 0 then
    raise exception 'La cantidad aprobada no puede ser negativa.';
  end if;

  update evento_personal_requerido
  set cantidad_aprobada = v_cantidad_final,
      aprobado_por = auth.uid(),
      aprobado_en = now()
  where id = p_evento_personal_requerido_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
end;
$$;

revoke all on function fn_aprobar_personal_evento(uuid, numeric) from public;
grant execute on function fn_aprobar_personal_evento(uuid, numeric) to authenticated;

-- fn_aprobar_evento_personal() — aprueba de una vez todas las líneas
-- vigentes que todavía no estén conformes (aprobada = sugerida).
create or replace function fn_aprobar_evento_personal(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform fn_validar_supervisor_evento(p_evento_id);

  update evento_personal_requerido
  set cantidad_aprobada = cantidad_sugerida,
      aprobado_por = auth.uid(),
      aprobado_en = now()
  where evento_mantencion_id = p_evento_id
    and estado_fila <> 'eliminado'
    and cantidad_aprobada is distinct from cantidad_sugerida;

  perform fn_actualizar_estado_revision(p_evento_id, 'personal');
end;
$$;

revoke all on function fn_aprobar_evento_personal(uuid) from public;
grant execute on function fn_aprobar_evento_personal(uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN F — Ajuste manual: recursos (mismo criterio que personal)
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_agregar_recurso_manual_evento(
  p_evento_id          uuid,
  p_categoria_recurso  text,
  p_nombre_generico    text,
  p_cantidad_sugerida  numeric,
  p_herramienta_codigo text default null,
  p_insumo_codigo      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform fn_validar_supervisor_evento(p_evento_id);

  if trim(coalesce(p_nombre_generico, '')) = '' then
    raise exception 'Debe indicar un nombre_generico.';
  end if;

  if p_cantidad_sugerida <= 0 then
    raise exception 'La cantidad sugerida debe ser mayor a 0.';
  end if;

  insert into evento_recursos (
    evento_mantencion_id, categoria_recurso, nombre_generico, herramienta_codigo, insumo_codigo,
    cantidad_sugerida, origen, estado_fila, creado_por
  ) values (
    p_evento_id, p_categoria_recurso, p_nombre_generico, p_herramienta_codigo, p_insumo_codigo,
    p_cantidad_sugerida, 'manual', 'agregado', auth.uid()
  )
  returning evento_recursos.id into v_id;

  perform fn_actualizar_estado_revision(p_evento_id, 'recursos');

  return v_id;
end;
$$;

revoke all on function fn_agregar_recurso_manual_evento(uuid, text, text, numeric, text, text) from public;
grant execute on function fn_agregar_recurso_manual_evento(uuid, text, text, numeric, text, text) to authenticated;

create or replace function fn_quitar_recurso_evento(
  p_evento_recurso_id     uuid,
  p_motivo_modificacion   text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id   uuid;
  v_estado_fila text;
begin
  select evento_mantencion_id, estado_fila into v_evento_id, v_estado_fila
    from evento_recursos where id = p_evento_recurso_id;

  if v_evento_id is null then
    raise exception 'La línea de recursos indicada (%) no existe.', p_evento_recurso_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'Esta línea ya fue eliminada.';
  end if;

  if trim(coalesce(p_motivo_modificacion, '')) = '' then
    raise exception 'Debe indicar un motivo para eliminar esta línea.';
  end if;

  update evento_recursos
  set estado_fila = 'eliminado',
      motivo_modificacion = p_motivo_modificacion
  where id = p_evento_recurso_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');
end;
$$;

revoke all on function fn_quitar_recurso_evento(uuid, text) from public;
grant execute on function fn_quitar_recurso_evento(uuid, text) to authenticated;

create or replace function fn_modificar_recurso_manual_evento(
  p_evento_recurso_id    uuid,
  p_cantidad_sugerida    numeric,
  p_motivo_modificacion  text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id   uuid;
  v_origen      text;
  v_estado_fila text;
begin
  select evento_mantencion_id, origen, estado_fila into v_evento_id, v_origen, v_estado_fila
    from evento_recursos where id = p_evento_recurso_id;

  if v_evento_id is null then
    raise exception 'La línea de recursos indicada (%) no existe.', p_evento_recurso_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'No se puede modificar una línea ya eliminada.';
  end if;

  if v_origen <> 'manual' then
    raise exception 'Solo se puede modificar directamente la cantidad sugerida de una línea manual. Las líneas derivadas de plantilla se recalculan automáticamente al agregar o quitar equipos.';
  end if;

  if p_cantidad_sugerida < 0 then
    raise exception 'La cantidad sugerida no puede ser negativa.';
  end if;

  if trim(coalesce(p_motivo_modificacion, '')) = '' then
    raise exception 'Debe indicar un motivo para modificar esta línea.';
  end if;

  update evento_recursos
  set cantidad_sugerida = p_cantidad_sugerida,
      estado_fila = 'modificado',
      motivo_modificacion = p_motivo_modificacion
  where id = p_evento_recurso_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');
end;
$$;

revoke all on function fn_modificar_recurso_manual_evento(uuid, numeric, text) from public;
grant execute on function fn_modificar_recurso_manual_evento(uuid, numeric, text) to authenticated;

create or replace function fn_aprobar_recurso_evento(
  p_evento_recurso_id  uuid,
  p_cantidad_aprobada  numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id         uuid;
  v_estado_fila       text;
  v_cantidad_sugerida numeric;
  v_cantidad_final    numeric;
begin
  select evento_mantencion_id, estado_fila, cantidad_sugerida
    into v_evento_id, v_estado_fila, v_cantidad_sugerida
    from evento_recursos where id = p_evento_recurso_id;

  if v_evento_id is null then
    raise exception 'La línea de recursos indicada (%) no existe.', p_evento_recurso_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'No se puede aprobar una línea eliminada.';
  end if;

  v_cantidad_final := coalesce(p_cantidad_aprobada, v_cantidad_sugerida);

  if v_cantidad_final < 0 then
    raise exception 'La cantidad aprobada no puede ser negativa.';
  end if;

  update evento_recursos
  set cantidad_aprobada = v_cantidad_final,
      aprobado_por = auth.uid(),
      aprobado_en = now()
  where id = p_evento_recurso_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');
end;
$$;

revoke all on function fn_aprobar_recurso_evento(uuid, numeric) from public;
grant execute on function fn_aprobar_recurso_evento(uuid, numeric) to authenticated;

create or replace function fn_aprobar_evento_recursos(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform fn_validar_supervisor_evento(p_evento_id);

  update evento_recursos
  set cantidad_aprobada = cantidad_sugerida,
      aprobado_por = auth.uid(),
      aprobado_en = now()
  where evento_mantencion_id = p_evento_id
    and estado_fila <> 'eliminado'
    and cantidad_aprobada is distinct from cantidad_sugerida;

  perform fn_actualizar_estado_revision(p_evento_id, 'recursos');
end;
$$;

revoke all on function fn_aprobar_evento_recursos(uuid) from public;
grant execute on function fn_aprobar_evento_recursos(uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Todas las funciones de este archivo y sus privilegios:
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace
--     and p.proname in (
--       'fn_recalcular_personal_evento', 'fn_recalcular_recursos_evento',
--       'fn_agregar_equipo_evento', 'fn_actualizar_estado_revision',
--       'fn_validar_supervisor_evento', 'fn_quitar_equipo_evento',
--       'fn_agregar_personal_manual_evento', 'fn_quitar_personal_evento',
--       'fn_modificar_personal_manual_evento', 'fn_aprobar_personal_evento',
--       'fn_aprobar_evento_personal', 'fn_agregar_recurso_manual_evento',
--       'fn_quitar_recurso_evento', 'fn_modificar_recurso_manual_evento',
--       'fn_aprobar_recurso_evento', 'fn_aprobar_evento_recursos'
--     )
--   order by p.proname;
-- -- fn_actualizar_estado_revision y fn_validar_supervisor_evento deben
-- -- mostrar "false" (privadas); el resto, "true".
--
-- 2) Prueba de punta a punta (con datos reales, dentro de una transacción
--    que termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_ajuste_aprobacion_etapa2d07.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop function if exists public.fn_aprobar_evento_recursos(uuid);
-- drop function if exists public.fn_aprobar_recurso_evento(uuid, numeric);
-- drop function if exists public.fn_modificar_recurso_manual_evento(uuid, numeric, text);
-- drop function if exists public.fn_quitar_recurso_evento(uuid, text);
-- drop function if exists public.fn_agregar_recurso_manual_evento(uuid, text, text, numeric, text, text);
-- drop function if exists public.fn_aprobar_evento_personal(uuid);
-- drop function if exists public.fn_aprobar_personal_evento(uuid, numeric);
-- drop function if exists public.fn_modificar_personal_manual_evento(uuid, numeric, text);
-- drop function if exists public.fn_quitar_personal_evento(uuid, text);
-- drop function if exists public.fn_agregar_personal_manual_evento(uuid, text, numeric, text);
-- drop function if exists public.fn_quitar_equipo_evento(uuid, text);
-- drop function if exists public.fn_validar_supervisor_evento(uuid);
-- drop function if exists public.fn_actualizar_estado_revision(uuid, text);
--
-- -- Revertir fn_agregar_equipo_evento() y las funciones de recálculo a su
-- -- versión de 2D-06 requiere volver a ejecutar el CREATE OR REPLACE de
-- -- ese archivo (2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql).
