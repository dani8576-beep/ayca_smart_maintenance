-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2C (Snapshot)
-- v2: usa los datos maestros REALES cargados por las ETAPAS 2C.4/2C.5
-- (cliente CODELCO → faena Andina → área Molienda, tipo de mantención
-- "MANTENCION_MENSUAL", protocolo "control_dimensional") en vez de
-- asumir una base vacía o datos arbitrarios.
--
-- Requiere que ya estén ejecutadas: perfiles_roles.sql,
-- mantenciones_etapa2a.sql, mantenciones_etapa2a5.sql (+ tag_equipos),
-- mantenciones_etapa2b.sql, mantenciones_etapa2c.sql,
-- mantenciones_etapa2c4_codigo_tipos_mantencion.sql,
-- mantenciones_etapa2c5_datos_maestros.sql.
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK. Usa el cliente/faena/área/tipo
-- de mantención/tipo de protocolo REALES recién cargados.
--
-- Única excepción: como todavía no existe ningún EQUIPO real (a
-- propósito — "no se agregan equipos ficticios" fue una decisión
-- para la carga PERMANENTE de la ETAPA 2C.5, no aplica a este test),
-- se crea un equipo de prueba temporal dentro de la misma
-- transacción, exclusivamente para poder ejercitar fn_crear_mantencion()
-- de punta a punta. Nunca queda persistido: se descarta con el
-- ROLLBACK final igual que la plantilla de prueba.
--
-- Alcance: valida la lógica de copiado (Snapshot), NO valida RLS de
-- punta a punta — se impersona a un usuario con rol supervisor o
-- administrador vía "request.jwt.claims" para que auth.uid()/
-- tiene_rol()/es_admin() resuelvan correctamente dentro de
-- fn_crear_mantencion(), pero el script no cambia de rol de Postgres.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── Paso A: ubicar datos maestros reales, crear equipo y plantilla de
--            prueba (temporales), y crear la mantención ──
do $$
declare
  v_actor_id           uuid;
  v_cliente_id         uuid;
  v_faena_id           uuid;
  v_area_id            uuid;
  v_equipo_id          uuid;
  v_tipo_mant_id       uuid;
  v_tipo_protocolo     text;
  v_herramienta_codigo text;
  v_insumo_codigo      text;
  v_version_test       int;
  v_plantilla_id       uuid;
  v_mant_id            uuid;
  v_mant_numero        text;
begin
  -- Actor: cualquier usuario con rol supervisor o administrador.
  select ur.usuario_id into v_actor_id
    from public.usuario_roles ur
    where ur.rol in ('administrador','supervisor')
    limit 1;
  if v_actor_id is null then
    raise exception 'TEST ABORTADO: no existe ningún usuario con rol supervisor o administrador en usuario_roles.';
  end if;

  -- Impersonar a ese usuario para que auth.uid()/tiene_rol()/es_admin() funcionen
  -- dentro de fn_crear_mantencion() (válido solo para esta transacción).
  perform set_config('request.jwt.claims', json_build_object('sub', v_actor_id::text)::text, true);

  -- Datos maestros REALES cargados por 2C.4/2C.5: CODELCO → Andina → Molienda.
  select id into v_cliente_id from public.clientes where codigo = 'CODELCO';
  if v_cliente_id is null then
    raise exception 'TEST ABORTADO: no se encontró el cliente CODELCO — ¿se ejecutó mantenciones_etapa2c5_datos_maestros.sql?';
  end if;

  select id into v_faena_id from public.faenas where cliente_id = v_cliente_id and codigo = 'ANDINA';
  if v_faena_id is null then
    raise exception 'TEST ABORTADO: no se encontró la faena Andina bajo CODELCO.';
  end if;

  select id into v_area_id from public.areas where faena_id = v_faena_id and codigo = 'MOLIENDA';
  if v_area_id is null then
    raise exception 'TEST ABORTADO: no se encontró el área Molienda bajo Andina.';
  end if;

  select id into v_tipo_mant_id from public.tipos_mantencion where codigo = 'MANTENCION_MENSUAL';
  if v_tipo_mant_id is null then
    raise exception 'TEST ABORTADO: no se encontró el tipo de mantención MANTENCION_MENSUAL — ¿se ejecutó mantenciones_etapa2c4/2c5?';
  end if;

  select codigo into v_tipo_protocolo from public.tipos_protocolo where codigo = 'control_dimensional';
  if v_tipo_protocolo is null then
    raise exception 'TEST ABORTADO: no se encontró el tipo de protocolo control_dimensional.';
  end if;

  select codigo into v_herramienta_codigo from public.herramientas limit 1;
  select codigo into v_insumo_codigo      from public.insumos_bodega limit 1;
  if v_herramienta_codigo is null and v_insumo_codigo is null then
    raise notice 'AVISO: no hay filas en herramientas ni en insumos_bodega — los recursos de prueba quedarán sin código asignado (recomendación genérica, válida según el diseño).';
  end if;

  -- Equipo de PRUEBA temporal (ver nota al inicio del archivo) — nunca persiste.
  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_id, 'TEST-EQUIPO-2C', 'TEST-TAG-2C', 'Equipo de prueba ETAPA 2C (temporal)', 'Motor eléctrico', true)
  returning id into v_equipo_id;

  raise notice 'Datos base -> actor=%, cliente=CODELCO(%), faena=Andina(%), area=Molienda(%), equipo_prueba=%, tipo_mantencion=MANTENCION_MENSUAL(%), tipo_protocolo=%, herramienta=%, insumo=%',
    v_actor_id, v_cliente_id, v_faena_id, v_area_id, v_equipo_id, v_tipo_mant_id, v_tipo_protocolo, v_herramienta_codigo, v_insumo_codigo;

  -- Plantilla temporal de prueba. Se desactiva temporalmente la plantilla activa
  -- vigente del mismo tipo (si existe) — se revierte solo con el ROLLBACK final.
  update public.plantillas_mantencion set activa = false
    where tipo_mantencion_id = v_tipo_mant_id and activa = true;

  select coalesce(max(version), 0) + 1000 into v_version_test
    from public.plantillas_mantencion where tipo_mantencion_id = v_tipo_mant_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test, 'TEST_SNAPSHOT_ETAPA2C', true)
  returning id into v_plantilla_id;

  raise notice 'Plantilla de prueba creada: id=%, version=%', v_plantilla_id, v_version_test;

  -- Contenido de la plantilla: 1 personal, 2 actividades, 1 protocolo, 2 recursos.
  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_id, 'tecnico', 1, 'electricista', true);

  insert into public.plantilla_actividades (plantilla_id, codigo_actividad, descripcion, orden, obligatoria)
  values
    (v_plantilla_id, 'TEST-1.1', 'Actividad de prueba 1', 1, true),
    (v_plantilla_id, 'TEST-1.2', 'Actividad de prueba 2', 2, false);

  insert into public.plantilla_protocolos (plantilla_id, tipo_protocolo, obligatorio)
  values (v_plantilla_id, v_tipo_protocolo, true);

  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, herramienta_codigo, cantidad_sugerida, obligatorio)
  values (v_plantilla_id, 'herramienta', 'Recurso de prueba 1 (herramienta)', v_herramienta_codigo, 1, false);

  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, insumo_codigo, cantidad_sugerida, obligatorio)
  values (v_plantilla_id, 'epp', 'Recurso de prueba 2 (insumo)', v_insumo_codigo, 2, false);

  raise notice 'Contenido de la plantilla de prueba insertado: 1 personal, 2 actividades, 1 protocolo, 2 recursos.';

  -- Crear la mantención mediante fn_crear_mantencion() (única vía permitida).
  select id, numero into v_mant_id, v_mant_numero
  from fn_crear_mantencion(
    p_cliente_id         => v_cliente_id,
    p_faena_id           => v_faena_id,
    p_area_id            => v_area_id,
    p_equipo_id          => v_equipo_id,
    p_tipo_mantencion_id => v_tipo_mant_id,
    p_plantilla_id       => v_plantilla_id,
    p_observaciones      => 'Mantención de prueba — ETAPA 2C con datos maestros reales (se revertirá con ROLLBACK)'
  );

  raise notice 'Mantención de prueba creada: id=%, numero=%', v_mant_id, v_mant_numero;

  perform set_config('ayca_test.mant_id', v_mant_id::text, true);
end $$;

-- ── Paso B: mostrar el resultado del snapshot ──
select 'MANTENCION' as tabla, m.*
  from public.mantenciones m
  where m.id = current_setting('ayca_test.mant_id')::uuid;

select 'MANTENCION_PERSONAL' as tabla, mp.*
  from public.mantencion_personal mp
  where mp.mantencion_id = current_setting('ayca_test.mant_id')::uuid;

select 'MANTENCION_ACTIVIDADES' as tabla, ma.*
  from public.mantencion_actividades ma
  where ma.mantencion_id = current_setting('ayca_test.mant_id')::uuid;

select 'MANTENCION_PROTOCOLOS' as tabla, mpr.*
  from public.mantencion_protocolos mpr
  where mpr.mantencion_id = current_setting('ayca_test.mant_id')::uuid;

select 'MANTENCION_RECURSOS' as tabla, mr.*
  from public.mantencion_recursos mr
  where mr.mantencion_id = current_setting('ayca_test.mant_id')::uuid;

-- ── Paso C: validar cantidades copiadas, con excepción clara si fallan ──
do $$
declare
  v_mant_id           uuid := current_setting('ayca_test.mant_id')::uuid;
  v_count_personal    int;
  v_count_actividades int;
  v_count_protocolos  int;
  v_count_recursos    int;
  v_errores           text[] := '{}';
begin
  select count(*) into v_count_personal    from public.mantencion_personal    where mantencion_id = v_mant_id;
  select count(*) into v_count_actividades from public.mantencion_actividades where mantencion_id = v_mant_id;
  select count(*) into v_count_protocolos  from public.mantencion_protocolos  where mantencion_id = v_mant_id;
  select count(*) into v_count_recursos    from public.mantencion_recursos    where mantencion_id = v_mant_id;

  raise notice 'Conteo snapshot -> personal=% (esperado 1), actividades=% (esperado 2), protocolos=% (esperado 1), recursos=% (esperado 2)',
    v_count_personal, v_count_actividades, v_count_protocolos, v_count_recursos;

  if v_count_personal <> 1 then
    v_errores := v_errores || format('mantencion_personal: esperado 1, obtenido %s', v_count_personal);
  end if;
  if v_count_actividades <> 2 then
    v_errores := v_errores || format('mantencion_actividades: esperado 2, obtenido %s', v_count_actividades);
  end if;
  if v_count_protocolos <> 1 then
    v_errores := v_errores || format('mantencion_protocolos: esperado 1, obtenido %s', v_count_protocolos);
  end if;
  if v_count_recursos <> 2 then
    v_errores := v_errores || format('mantencion_recursos: esperado 2, obtenido %s', v_count_recursos);
  end if;

  if array_length(v_errores, 1) > 0 then
    raise exception 'TEST FALLIDO — el snapshot no copió las cantidades esperadas: %', array_to_string(v_errores, ' | ');
  end if;

  raise notice '✔ TEST OK: el snapshot de la ETAPA 2C copió exactamente 1 personal, 2 actividades, 1 protocolo y 2 recursos, usando datos maestros reales (CODELCO → Andina → Molienda → MANTENCION_MENSUAL).';
end $$;

-- ── No dejar ningún dato de prueba en la base (incluye el equipo temporal) ──
rollback;
