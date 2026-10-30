-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2D.06
-- (fn_crear_evento_mantencion / fn_agregar_equipo_evento)
--
-- Requiere que ya estén ejecutadas todas las migraciones de 2A a 2D.06
-- (perfiles_roles, 2A, 2A.5(+tag), 2B, 2C(+fix), 2C.4, 2C.5,
-- 2D-01 a 2D-06).
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK. Usa CODELCO → Andina → Molienda
-- (datos reales de 2C.5), dos equipos y dos plantillas de prueba
-- temporales — ambas con el MISMO perfil de personal ("Electricista" /
-- "Media tensión") y el MISMO recurso genérico ("Megger 5kV") a
-- propósito, para poder comprobar que la consolidación efectivamente
-- suma en una sola línea en vez de duplicarla.
--
-- Escenarios cubiertos:
--   A) Setup: evento + 2 equipos + 2 plantillas de prueba.
--   B) fn_agregar_equipo_evento() con el equipo 1: mantención creada,
--      snapshot reducido (solo actividades/protocolos, personal/recursos
--      del equipo en 0), 1 línea de personal y 1 de recursos
--      consolidadas, origen activo, estados del evento en revisión.
--   C) fn_agregar_equipo_evento() con el equipo 2 (misma plantilla-perfil/
--      recurso): NO se duplica la línea — se consolida en la misma,
--      sumando cantidad_sugerida de ambos equipos.
--   D) Negativo: volver a agregar el equipo 1 al mismo evento — mensaje
--      de error claro, no el genérico de una restricción de BD.
--   E) Negativo: agregar un equipo de OTRA faena al evento — falla por
--      jerarquía.
--   F) Negativo: fn_crear_evento_mantencion() con nombre vacío.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Setup ──
do $$
declare
  v_actor_id           uuid;
  v_cliente_id         uuid;
  v_faena_andina_id    uuid;
  v_faena_tte_id       uuid;
  v_area_andina_id     uuid;
  v_area_tte_id        uuid;
  v_tipo_mant_id       uuid;
  v_tipo_protocolo     text;
  v_version_test       int;
  v_plantilla_1_id     uuid;
  v_plantilla_2_id     uuid;
  v_equipo_1_id        uuid;
  v_equipo_2_id        uuid;
  v_equipo_otra_faena_id uuid;
begin
  select ur.usuario_id into v_actor_id
    from public.usuario_roles ur
    where ur.rol in ('administrador','supervisor')
    limit 1;
  if v_actor_id is null then
    raise exception 'TEST ABORTADO: no existe ningún usuario con rol supervisor o administrador en usuario_roles.';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_actor_id::text)::text, true);

  select id into v_cliente_id from public.clientes where codigo = 'CODELCO';
  select id into v_faena_andina_id from public.faenas where cliente_id = v_cliente_id and codigo = 'ANDINA';
  select id into v_faena_tte_id    from public.faenas where cliente_id = v_cliente_id and codigo = 'TENIENTE';
  if v_cliente_id is null or v_faena_andina_id is null or v_faena_tte_id is null then
    raise exception 'TEST ABORTADO: no se encontró CODELCO → Andina/Teniente.';
  end if;

  select id into v_area_andina_id from public.areas where faena_id = v_faena_andina_id and codigo = 'MOLIENDA';
  select id into v_area_tte_id    from public.areas where faena_id = v_faena_tte_id    and codigo = 'MOLIENDA';
  if v_area_andina_id is null or v_area_tte_id is null then
    raise exception 'TEST ABORTADO: no se encontró el área Molienda bajo Andina/Teniente.';
  end if;

  select id into v_tipo_mant_id from public.tipos_mantencion where codigo = 'MANTENCION_MENSUAL';
  select codigo into v_tipo_protocolo from public.tipos_protocolo where codigo = 'control_dimensional';
  if v_tipo_mant_id is null or v_tipo_protocolo is null then
    raise exception 'TEST ABORTADO: falta MANTENCION_MENSUAL o control_dimensional.';
  end if;

  -- Equipos de prueba: dos en Andina (para el evento), uno en Teniente
  -- (para el escenario negativo de jerarquía).
  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_andina_id, 'TEST-EQ1-2D06', 'TEST-TAG1-2D06', 'Equipo de prueba 1 (2D.06)', 'Motor eléctrico', true)
  returning id into v_equipo_1_id;

  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_andina_id, 'TEST-EQ2-2D06', 'TEST-TAG2-2D06', 'Equipo de prueba 2 (2D.06)', 'Motor eléctrico', true)
  returning id into v_equipo_2_id;

  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_tte_id, 'TEST-EQ3-2D06', 'TEST-TAG3-2D06', 'Equipo de prueba 3, Teniente (2D.06)', 'Motor eléctrico', true)
  returning id into v_equipo_otra_faena_id;

  -- Dos plantillas de prueba, ambas con el MISMO perfil de personal y el
  -- MISMO recurso genérico (a propósito, para probar la consolidación).
  update public.plantillas_mantencion set activa = false
    where tipo_mantencion_id = v_tipo_mant_id and activa = true;

  select coalesce(max(version), 0) + 1000 into v_version_test
    from public.plantillas_mantencion where tipo_mantencion_id = v_tipo_mant_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test, 'TEST_PLANTILLA_1_2D06', true)
  returning id into v_plantilla_1_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test + 1, 'TEST_PLANTILLA_2_2D06', false)
  returning id into v_plantilla_2_id;

  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_1_id, 'Electricista', 2, 'Media tensión', true);

  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_2_id, 'Electricista', 1, 'Media tensión', true);

  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_1_id, 'herramienta', 'Megger 5kV', 1, false);

  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_2_id, 'herramienta', '  megger 5kv  ', 2, false);  -- mismo recurso, distinto casing/espacios

  insert into public.plantilla_actividades (plantilla_id, codigo_actividad, descripcion, orden, obligatoria)
  values
    (v_plantilla_1_id, 'TEST-2D06-1.1', 'Actividad plantilla 1 — A', 1, true),
    (v_plantilla_1_id, 'TEST-2D06-1.2', 'Actividad plantilla 1 — B', 2, true);

  insert into public.plantilla_actividades (plantilla_id, codigo_actividad, descripcion, orden, obligatoria)
  values (v_plantilla_2_id, 'TEST-2D06-2.1', 'Actividad plantilla 2 — A', 1, true);

  insert into public.plantilla_protocolos (plantilla_id, tipo_protocolo, obligatorio)
  values (v_plantilla_1_id, v_tipo_protocolo, true);

  insert into public.plantilla_protocolos (plantilla_id, tipo_protocolo, obligatorio)
  values (v_plantilla_2_id, v_tipo_protocolo, true);

  raise notice 'Setup completo -> actor=%, cliente=CODELCO(%), andina=%, equipo_1=%, equipo_2=%, equipo_otra_faena=%, plantilla_1=%, plantilla_2=%',
    v_actor_id, v_cliente_id, v_faena_andina_id, v_equipo_1_id, v_equipo_2_id, v_equipo_otra_faena_id, v_plantilla_1_id, v_plantilla_2_id;

  perform set_config('ayca_test.actor_id',        v_actor_id::text, true);
  perform set_config('ayca_test.cliente_id',      v_cliente_id::text, true);
  perform set_config('ayca_test.faena_andina_id', v_faena_andina_id::text, true);
  perform set_config('ayca_test.area_andina_id',  v_area_andina_id::text, true);
  perform set_config('ayca_test.tipo_mant_id',    v_tipo_mant_id::text, true);
  perform set_config('ayca_test.plantilla_1_id',  v_plantilla_1_id::text, true);
  perform set_config('ayca_test.plantilla_2_id',  v_plantilla_2_id::text, true);
  perform set_config('ayca_test.equipo_1_id',     v_equipo_1_id::text, true);
  perform set_config('ayca_test.equipo_2_id',     v_equipo_2_id::text, true);
  perform set_config('ayca_test.equipo_otra_faena_id', v_equipo_otra_faena_id::text, true);
end $$;

-- ── A2. Crear el evento con fn_crear_evento_mantencion() ──
do $$
declare
  v_evento_id     uuid;
  v_evento_numero text;
begin
  select id, numero into v_evento_id, v_evento_numero
  from fn_crear_evento_mantencion(
    p_cliente_id => current_setting('ayca_test.cliente_id')::uuid,
    p_faena_id   => current_setting('ayca_test.faena_andina_id')::uuid,
    p_tipo_evento => 'PROGRAMADA',
    p_nombre     => 'TEST evento multiequipo 2D.06',
    p_supervisor_id => current_setting('ayca_test.actor_id')::uuid
  );

  if v_evento_id is null then
    raise exception 'TEST FALLIDO (A2): fn_crear_evento_mantencion() no devolvió un id.';
  end if;

  raise notice '✔ A2) OK: evento creado id=%, numero=%.', v_evento_id, v_evento_numero;
  perform set_config('ayca_test.evento_id', v_evento_id::text, true);
end $$;

-- ── B. Agregar el equipo 1 con fn_agregar_equipo_evento() ──
do $$
declare
  v_mant_1_id       uuid;
  v_mant_1_numero   text;
  v_count_act       int;
  v_count_prot      int;
  v_count_personal  int;
  v_count_recursos  int;
  v_requerido_count int;
  v_requerido_cant  numeric;
  v_recurso_count   int;
  v_recurso_cant    numeric;
  v_personal_estado text;
  v_recursos_estado text;
begin
  select mantencion_id, numero into v_mant_1_id, v_mant_1_numero
  from fn_agregar_equipo_evento(
    p_evento_id => current_setting('ayca_test.evento_id')::uuid,
    p_area_id   => current_setting('ayca_test.area_andina_id')::uuid,
    p_equipo_id => current_setting('ayca_test.equipo_1_id')::uuid,
    p_tipo_mantencion_id => current_setting('ayca_test.tipo_mant_id')::uuid,
    p_plantilla_id => current_setting('ayca_test.plantilla_1_id')::uuid
  );

  if v_mant_1_id is null then
    raise exception 'TEST FALLIDO (B): fn_agregar_equipo_evento() no devolvió un id de mantención.';
  end if;
  perform set_config('ayca_test.mant_1_id', v_mant_1_id::text, true);

  select count(*) into v_count_act      from mantencion_actividades where mantencion_id = v_mant_1_id;
  select count(*) into v_count_prot     from mantencion_protocolos  where mantencion_id = v_mant_1_id;
  select count(*) into v_count_personal from mantencion_personal    where mantencion_id = v_mant_1_id;
  select count(*) into v_count_recursos from mantencion_recursos    where mantencion_id = v_mant_1_id;

  if v_count_act <> 2 then
    raise exception 'TEST FALLIDO (B): se esperaban 2 mantencion_actividades, hay %.', v_count_act;
  end if;
  if v_count_prot <> 1 then
    raise exception 'TEST FALLIDO (B): se esperaba 1 mantencion_protocolos, hay %.', v_count_prot;
  end if;
  if v_count_personal <> 0 then
    raise exception 'TEST FALLIDO (B): mantencion_personal debe quedar VACÍA en el flujo multiequipo, tiene % fila(s).', v_count_personal;
  end if;
  if v_count_recursos <> 0 then
    raise exception 'TEST FALLIDO (B): mantencion_recursos debe quedar VACÍA en el flujo multiequipo, tiene % fila(s).', v_count_recursos;
  end if;

  select count(*), sum(cantidad_sugerida) into v_requerido_count, v_requerido_cant
    from evento_personal_requerido
    where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;

  if v_requerido_count <> 1 or v_requerido_cant <> 2 then
    raise exception 'TEST FALLIDO (B): se esperaba 1 línea de personal requerido con cantidad_sugerida=2, hay % línea(s) con total %.', v_requerido_count, v_requerido_cant;
  end if;

  select count(*), sum(cantidad_sugerida) into v_recurso_count, v_recurso_cant
    from evento_recursos
    where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;

  if v_recurso_count <> 1 or v_recurso_cant <> 1 then
    raise exception 'TEST FALLIDO (B): se esperaba 1 línea de recursos con cantidad_sugerida=1, hay % línea(s) con total %.', v_recurso_count, v_recurso_cant;
  end if;

  select em.personal_estado, em.recursos_estado into v_personal_estado, v_recursos_estado
    from eventos_mantencion em where em.id = current_setting('ayca_test.evento_id')::uuid;

  if v_personal_estado <> 'en_revision' or v_recursos_estado <> 'en_revision' then
    raise exception 'TEST FALLIDO (B): se esperaba personal_estado/recursos_estado = en_revision, son %/%.', v_personal_estado, v_recursos_estado;
  end if;

  raise notice '✔ B) OK: mantención 1 (%) creada — actividades=2, protocolos=1, personal/recursos por-equipo=0, 1 línea de personal (cant=2), 1 línea de recursos (cant=1), estados en_revision.', v_mant_1_numero;
end $$;

-- ── C. Agregar el equipo 2 (misma plantilla-perfil/recurso) — debe
--       CONSOLIDAR, no duplicar ──
do $$
declare
  v_mant_2_id       uuid;
  v_mant_2_numero   text;
  v_requerido_count int;
  v_requerido_cant  numeric;
  v_recurso_count   int;
  v_recurso_cant    numeric;
  v_origen_personal_activos int;
  v_origen_recurso_activos  int;
begin
  select mantencion_id, numero into v_mant_2_id, v_mant_2_numero
  from fn_agregar_equipo_evento(
    p_evento_id => current_setting('ayca_test.evento_id')::uuid,
    p_area_id   => current_setting('ayca_test.area_andina_id')::uuid,
    p_equipo_id => current_setting('ayca_test.equipo_2_id')::uuid,
    p_tipo_mantencion_id => current_setting('ayca_test.tipo_mant_id')::uuid,
    p_plantilla_id => current_setting('ayca_test.plantilla_2_id')::uuid
  );

  if v_mant_2_id is null then
    raise exception 'TEST FALLIDO (C): fn_agregar_equipo_evento() no devolvió un id de mantención para el equipo 2.';
  end if;
  perform set_config('ayca_test.mant_2_id', v_mant_2_id::text, true);

  select count(*), sum(cantidad_sugerida) into v_requerido_count, v_requerido_cant
    from evento_personal_requerido
    where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;

  if v_requerido_count <> 1 then
    raise exception 'TEST FALLIDO (C): se esperaba que la línea de personal siguiera siendo 1 (consolidada), hay %.', v_requerido_count;
  end if;
  if v_requerido_cant <> 3 then
    raise exception 'TEST FALLIDO (C): se esperaba cantidad_sugerida=3 (2+1), es %.', v_requerido_cant;
  end if;

  select count(*), sum(cantidad_sugerida) into v_recurso_count, v_recurso_cant
    from evento_recursos
    where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;

  if v_recurso_count <> 1 then
    raise exception 'TEST FALLIDO (C): se esperaba que la línea de recursos siguiera siendo 1 (consolidada), hay %.', v_recurso_count;
  end if;
  if v_recurso_cant <> 3 then
    raise exception 'TEST FALLIDO (C): se esperaba cantidad_sugerida=3 (1+2), es %.', v_recurso_cant;
  end if;

  select count(*) into v_origen_personal_activos
    from evento_personal_origen
    where mantencion_id in (current_setting('ayca_test.mant_1_id')::uuid, current_setting('ayca_test.mant_2_id')::uuid)
      and estado = 'activo';
  if v_origen_personal_activos <> 2 then
    raise exception 'TEST FALLIDO (C): se esperaban 2 filas de evento_personal_origen activas (una por equipo), hay %.', v_origen_personal_activos;
  end if;

  select count(*) into v_origen_recurso_activos
    from evento_recursos_origen
    where mantencion_id in (current_setting('ayca_test.mant_1_id')::uuid, current_setting('ayca_test.mant_2_id')::uuid)
      and estado = 'activo';
  if v_origen_recurso_activos <> 2 then
    raise exception 'TEST FALLIDO (C): se esperaban 2 filas de evento_recursos_origen activas (una por equipo), hay %.', v_origen_recurso_activos;
  end if;

  raise notice '✔ C) OK: mantención 2 (%) agregada — consolidación correcta: personal cant=3, recursos cant=3, 2+2 filas de origen activas (personal/recursos).', v_mant_2_numero;
end $$;

-- ── D. Negativo: volver a agregar el equipo 1 al mismo evento ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform mantencion_id from fn_agregar_equipo_evento(
      p_evento_id => current_setting('ayca_test.evento_id')::uuid,
      p_area_id   => current_setting('ayca_test.area_andina_id')::uuid,
      p_equipo_id => current_setting('ayca_test.equipo_1_id')::uuid,
      p_tipo_mantencion_id => current_setting('ayca_test.tipo_mant_id')::uuid,
      p_plantilla_id => current_setting('ayca_test.plantilla_1_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ D) OK: duplicado rechazado con mensaje claro — %', sqlerrm;
    if sqlerrm not ilike '%ya tiene una mantención activa%' then
      raise exception 'TEST FALLIDO (D): el mensaje de error no es el esperado (mensaje claro de duplicado) — obtenido: %', sqlerrm;
    end if;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (D): se permitió agregar el mismo equipo dos veces al mismo evento.';
  end if;
end $$;

-- ── E. Negativo: agregar un equipo de OTRA faena al evento ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform mantencion_id from fn_agregar_equipo_evento(
      p_evento_id => current_setting('ayca_test.evento_id')::uuid,
      p_area_id   => (select area_id from public.equipos where id = current_setting('ayca_test.equipo_otra_faena_id')::uuid),
      p_equipo_id => current_setting('ayca_test.equipo_otra_faena_id')::uuid,
      p_tipo_mantencion_id => current_setting('ayca_test.tipo_mant_id')::uuid,
      p_plantilla_id => current_setting('ayca_test.plantilla_1_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ E) OK: equipo de otra faena rechazado — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (E): se permitió agregar un equipo de una faena distinta a la del evento.';
  end if;
end $$;

-- ── F. Negativo: fn_crear_evento_mantencion() con nombre vacío ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform id from fn_crear_evento_mantencion(
      p_cliente_id => current_setting('ayca_test.cliente_id')::uuid,
      p_faena_id   => current_setting('ayca_test.faena_andina_id')::uuid,
      p_tipo_evento => 'PROGRAMADA',
      p_nombre     => '   ',
      p_supervisor_id => current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ F) OK: evento con nombre vacío rechazado — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (F): se permitió crear un evento con nombre vacío.';
  end if;
end $$;

do $$
begin
  raise notice '✔ TEST 2D.06 COMPLETO: creación y consolidación (A2, B, C) y negativos (D, E, F) se comportaron como se esperaba.';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
