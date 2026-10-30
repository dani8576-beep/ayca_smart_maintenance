-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2D.07
-- (ajuste manual y aprobación — cierra el ciclo de planificación)
--
-- Requiere que ya estén ejecutadas todas las migraciones de 2A a 2D.07.
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK.
--
-- Escenarios cubiertos:
--   A) Setup: evento con 2 equipos (fn_agregar_equipo_evento, 2D-06),
--      igual que el test de 2D.06 — personal consolidado=3, recursos=3.
--   B) Aprobación manual — BULK personal: fn_aprobar_evento_personal().
--   C) Aprobación manual — POR LÍNEA recursos: fn_aprobar_recurso_evento().
--   D) Recurso extraordinario: fn_agregar_recurso_manual_evento() — el
--      estado de recursos deja de estar 'aprobado' (nueva línea sin
--      aprobar todavía).
--   E) Personal extraordinario: fn_agregar_personal_manual_evento().
--   F) Aprobar las líneas nuevas — ambos estados vuelven a 'aprobado'.
--   G) Modificación manual: fn_modificar_recurso_manual_evento() sobre
--      la línea manual — vuelve a quedar desalineada (parcial).
--   H) Aprobación BULK recursos: fn_aprobar_evento_recursos() — vuelve
--      a 'aprobado'.
--   I) Quitar un equipo: fn_quitar_equipo_evento() — recalcula
--      cantidad_sugerida de las líneas de PLANTILLA (personal y
--      recursos) SIN tocar cantidad_aprobada — verificación central de
--      "recálculo posterior sin perder aprobaciones existentes".
--   J) Negativo: volver a quitar el mismo equipo (ya cancelado).
--   K) Negativo: modificar una línea de origen 'plantilla' a mano.
--   L) Negativo: quitar una línea sin motivo_modificacion.
--   M) Negativo: agregar personal/recurso manual con cantidad <= 0.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Setup: evento con 2 equipos (mismo criterio que el test de 2D.06) ──
do $$
declare
  v_actor_id        uuid;
  v_cliente_id      uuid;
  v_faena_id        uuid;
  v_area_id         uuid;
  v_tipo_mant_id    uuid;
  v_tipo_protocolo  text;
  v_version_test    int;
  v_plantilla_1_id  uuid;
  v_plantilla_2_id  uuid;
  v_equipo_1_id     uuid;
  v_equipo_2_id     uuid;
  v_evento_id       uuid;
  v_mant_1_id       uuid;
  v_mant_2_id       uuid;
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
  select id into v_faena_id   from public.faenas where cliente_id = v_cliente_id and codigo = 'ANDINA';
  select id into v_area_id    from public.areas where faena_id = v_faena_id and codigo = 'MOLIENDA';
  if v_cliente_id is null or v_faena_id is null or v_area_id is null then
    raise exception 'TEST ABORTADO: no se encontró CODELCO → Andina → Molienda.';
  end if;

  select id into v_tipo_mant_id from public.tipos_mantencion where codigo = 'MANTENCION_MENSUAL';
  select codigo into v_tipo_protocolo from public.tipos_protocolo where codigo = 'control_dimensional';
  if v_tipo_mant_id is null or v_tipo_protocolo is null then
    raise exception 'TEST ABORTADO: falta MANTENCION_MENSUAL o control_dimensional.';
  end if;

  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_id, 'TEST-EQ1-2D07', 'TEST-TAG1-2D07', 'Equipo de prueba 1 (2D.07)', 'Motor eléctrico', true)
  returning id into v_equipo_1_id;

  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_id, 'TEST-EQ2-2D07', 'TEST-TAG2-2D07', 'Equipo de prueba 2 (2D.07)', 'Motor eléctrico', true)
  returning id into v_equipo_2_id;

  update public.plantillas_mantencion set activa = false
    where tipo_mantencion_id = v_tipo_mant_id and activa = true;

  select coalesce(max(version), 0) + 1000 into v_version_test
    from public.plantillas_mantencion where tipo_mantencion_id = v_tipo_mant_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test, 'TEST_PLANTILLA_1_2D07', true)
  returning id into v_plantilla_1_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test + 1, 'TEST_PLANTILLA_2_2D07', false)
  returning id into v_plantilla_2_id;

  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_1_id, 'Electricista', 2, 'Media tensión', true);
  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_2_id, 'Electricista', 1, 'Media tensión', true);

  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_1_id, 'herramienta', 'Megger 5kV', 1, false);
  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_2_id, 'herramienta', 'Megger 5kV', 2, false);

  insert into public.plantilla_actividades (plantilla_id, codigo_actividad, descripcion, orden, obligatoria)
  values (v_plantilla_1_id, 'TEST-2D07-1.1', 'Actividad plantilla 1', 1, true);
  insert into public.plantilla_actividades (plantilla_id, codigo_actividad, descripcion, orden, obligatoria)
  values (v_plantilla_2_id, 'TEST-2D07-2.1', 'Actividad plantilla 2', 1, true);

  insert into public.plantilla_protocolos (plantilla_id, tipo_protocolo, obligatorio)
  values (v_plantilla_1_id, v_tipo_protocolo, true);
  insert into public.plantilla_protocolos (plantilla_id, tipo_protocolo, obligatorio)
  values (v_plantilla_2_id, v_tipo_protocolo, true);

  select id into v_evento_id
  from fn_crear_evento_mantencion(
    p_cliente_id => v_cliente_id, p_faena_id => v_faena_id, p_tipo_evento => 'PROGRAMADA',
    p_nombre => 'TEST evento 2D.07', p_supervisor_id => v_actor_id
  );

  select mantencion_id into v_mant_1_id
  from fn_agregar_equipo_evento(v_evento_id, v_area_id, v_equipo_1_id, v_tipo_mant_id, v_plantilla_1_id);

  select mantencion_id into v_mant_2_id
  from fn_agregar_equipo_evento(v_evento_id, v_area_id, v_equipo_2_id, v_tipo_mant_id, v_plantilla_2_id);

  raise notice 'Setup completo -> actor=%, evento=%, mant_1=%, mant_2=%', v_actor_id, v_evento_id, v_mant_1_id, v_mant_2_id;

  perform set_config('ayca_test.actor_id',  v_actor_id::text, true);
  perform set_config('ayca_test.evento_id', v_evento_id::text, true);
  perform set_config('ayca_test.mant_1_id', v_mant_1_id::text, true);
  perform set_config('ayca_test.mant_2_id', v_mant_2_id::text, true);
end $$;

-- ── B. Aprobación manual BULK — personal ──
do $$
declare
  v_requerido_id uuid;
  v_cant_sug numeric;
  v_cant_apr numeric;
  v_personal_estado text;
begin
  select id, cantidad_sugerida into v_requerido_id, v_cant_sug
    from evento_personal_requerido where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;

  if v_cant_sug <> 3 then
    raise exception 'TEST FALLIDO (B-pre): se esperaba cantidad_sugerida=3 antes de aprobar, es %.', v_cant_sug;
  end if;

  perform fn_aprobar_evento_personal(current_setting('ayca_test.evento_id')::uuid);

  select cantidad_aprobada into v_cant_apr from evento_personal_requerido where id = v_requerido_id;
  select personal_estado into v_personal_estado from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_cant_apr <> 3 then
    raise exception 'TEST FALLIDO (B): se esperaba cantidad_aprobada=3, es %.', v_cant_apr;
  end if;
  if v_personal_estado <> 'aprobado' then
    raise exception 'TEST FALLIDO (B): se esperaba personal_estado=aprobado, es %.', v_personal_estado;
  end if;

  perform set_config('ayca_test.requerido_electricista_id', v_requerido_id::text, true);
  raise notice '✔ B) OK: aprobación bulk de personal — cantidad_aprobada=3, personal_estado=aprobado.';
end $$;

-- ── C. Aprobación manual POR LÍNEA — recursos ──
do $$
declare
  v_recurso_id uuid;
  v_cant_apr numeric;
  v_recursos_estado text;
begin
  select id into v_recurso_id
    from evento_recursos where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;

  perform fn_aprobar_recurso_evento(v_recurso_id);

  select cantidad_aprobada into v_cant_apr from evento_recursos where id = v_recurso_id;
  select recursos_estado into v_recursos_estado from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_cant_apr <> 3 then
    raise exception 'TEST FALLIDO (C): se esperaba cantidad_aprobada=3, es %.', v_cant_apr;
  end if;
  if v_recursos_estado <> 'aprobado' then
    raise exception 'TEST FALLIDO (C): se esperaba recursos_estado=aprobado, es %.', v_recursos_estado;
  end if;

  perform set_config('ayca_test.recurso_megger_id', v_recurso_id::text, true);
  raise notice '✔ C) OK: aprobación por línea de recursos — cantidad_aprobada=3, recursos_estado=aprobado.';
end $$;

-- ── D. Recurso extraordinario (manual) — el estado deja de estar aprobado ──
do $$
declare
  v_recurso_grua_id uuid;
  v_recursos_estado text;
begin
  v_recurso_grua_id := fn_agregar_recurso_manual_evento(
    current_setting('ayca_test.evento_id')::uuid, 'equipo_apoyo', 'Grúa horquilla', 1
  );

  select recursos_estado into v_recursos_estado from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_recursos_estado <> 'parcial' then
    raise exception 'TEST FALLIDO (D): se esperaba recursos_estado=parcial tras agregar un recurso extraordinario sin aprobar, es %.', v_recursos_estado;
  end if;

  perform set_config('ayca_test.recurso_grua_id', v_recurso_grua_id::text, true);
  raise notice '✔ D) OK: recurso extraordinario agregado (Grúa horquilla) — recursos_estado=parcial.';
end $$;

-- ── E. Personal extraordinario (manual) ──
do $$
declare
  v_requerido_rigger_id uuid;
  v_personal_estado text;
begin
  v_requerido_rigger_id := fn_agregar_personal_manual_evento(
    current_setting('ayca_test.evento_id')::uuid, 'Rigger', 1
  );

  select personal_estado into v_personal_estado from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_personal_estado <> 'parcial' then
    raise exception 'TEST FALLIDO (E): se esperaba personal_estado=parcial tras agregar personal extraordinario sin aprobar, es %.', v_personal_estado;
  end if;

  perform set_config('ayca_test.requerido_rigger_id', v_requerido_rigger_id::text, true);
  raise notice '✔ E) OK: personal extraordinario agregado (Rigger) — personal_estado=parcial.';
end $$;

-- ── F. Aprobar las líneas nuevas — ambos estados vuelven a 'aprobado' ──
do $$
declare
  v_personal_estado text;
  v_recursos_estado text;
begin
  perform fn_aprobar_personal_evento(current_setting('ayca_test.requerido_rigger_id')::uuid);
  perform fn_aprobar_recurso_evento(current_setting('ayca_test.recurso_grua_id')::uuid);

  select personal_estado, recursos_estado into v_personal_estado, v_recursos_estado
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_personal_estado <> 'aprobado' or v_recursos_estado <> 'aprobado' then
    raise exception 'TEST FALLIDO (F): se esperaba personal_estado/recursos_estado=aprobado, son %/%.', v_personal_estado, v_recursos_estado;
  end if;

  raise notice '✔ F) OK: ambas líneas extraordinarias aprobadas — estados vuelven a aprobado.';
end $$;

-- ── G. Modificación manual — desalinea la línea manual de recursos ──
do $$
declare
  v_recursos_estado text;
  v_cant_sug numeric;
  v_cant_apr numeric;
begin
  perform fn_modificar_recurso_manual_evento(
    current_setting('ayca_test.recurso_grua_id')::uuid, 2, 'Se necesitan 2 grúas, no 1 (prueba 2D.07)'
  );

  select cantidad_sugerida, cantidad_aprobada into v_cant_sug, v_cant_apr
    from evento_recursos where id = current_setting('ayca_test.recurso_grua_id')::uuid;
  select recursos_estado into v_recursos_estado from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_cant_sug <> 2 then
    raise exception 'TEST FALLIDO (G): se esperaba cantidad_sugerida=2 tras modificar, es %.', v_cant_sug;
  end if;
  if v_cant_apr <> 1 then
    raise exception 'TEST FALLIDO (G): cantidad_aprobada NO debía cambiar (sigue en 1 de la aprobación anterior), es %.', v_cant_apr;
  end if;
  if v_recursos_estado <> 'parcial' then
    raise exception 'TEST FALLIDO (G): se esperaba recursos_estado=parcial (Megger conforme, Grúa desalineada), es %.', v_recursos_estado;
  end if;

  raise notice '✔ G) OK: modificación manual desalinea la línea (sugerida=2, aprobada sigue en 1) — recursos_estado=parcial.';
end $$;

-- ── H. Aprobación BULK recursos — vuelve a 'aprobado' ──
do $$
declare
  v_recursos_estado text;
begin
  perform fn_aprobar_evento_recursos(current_setting('ayca_test.evento_id')::uuid);

  select recursos_estado into v_recursos_estado from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_recursos_estado <> 'aprobado' then
    raise exception 'TEST FALLIDO (H): se esperaba recursos_estado=aprobado tras la aprobación bulk, es %.', v_recursos_estado;
  end if;

  raise notice '✔ H) OK: aprobación bulk de recursos — recursos_estado=aprobado.';
end $$;

-- ── I. Quitar un equipo — recalcula SIN perder las aprobaciones ──
do $$
declare
  v_electricista_sug numeric;
  v_electricista_apr numeric;
  v_megger_sug        numeric;
  v_megger_apr        numeric;
  v_personal_estado   text;
  v_recursos_estado   text;
  v_mant_2_estado     text;
  v_origen_personal_estado text;
  v_origen_recurso_estado  text;
begin
  perform fn_quitar_equipo_evento(current_setting('ayca_test.mant_2_id')::uuid, 'Prueba 2D.07 — quitar equipo 2');

  select estado into v_mant_2_estado from mantenciones where id = current_setting('ayca_test.mant_2_id')::uuid;
  if v_mant_2_estado <> 'cancelada' then
    raise exception 'TEST FALLIDO (I): se esperaba que la mantención 2 quedara cancelada, está %.', v_mant_2_estado;
  end if;

  select estado into v_origen_personal_estado
    from evento_personal_origen where mantencion_id = current_setting('ayca_test.mant_2_id')::uuid;
  if v_origen_personal_estado <> 'retirado' then
    raise exception 'TEST FALLIDO (I): se esperaba evento_personal_origen retirado para el equipo 2, está %.', v_origen_personal_estado;
  end if;

  select estado into v_origen_recurso_estado
    from evento_recursos_origen where mantencion_id = current_setting('ayca_test.mant_2_id')::uuid;
  if v_origen_recurso_estado <> 'retirado' then
    raise exception 'TEST FALLIDO (I): se esperaba evento_recursos_origen retirado para el equipo 2, está %.', v_origen_recurso_estado;
  end if;

  -- Electricista: sugerida recalculada a 2 (solo aporte del equipo 1),
  -- pero aprobada DEBE seguir en 3 — la prueba central de este archivo.
  select cantidad_sugerida, cantidad_aprobada into v_electricista_sug, v_electricista_apr
    from evento_personal_requerido where id = current_setting('ayca_test.requerido_electricista_id')::uuid;

  if v_electricista_sug <> 2 then
    raise exception 'TEST FALLIDO (I): se esperaba cantidad_sugerida=2 para Electricista tras quitar el equipo 2, es %.', v_electricista_sug;
  end if;
  if v_electricista_apr <> 3 then
    raise exception 'TEST FALLIDO (I): ¡se perdió la aprobación! cantidad_aprobada debía seguir en 3, es %.', v_electricista_apr;
  end if;

  -- Megger: mismo criterio (sugerida baja de 3 a 1, aprobada sigue en 3).
  select cantidad_sugerida, cantidad_aprobada into v_megger_sug, v_megger_apr
    from evento_recursos where id = current_setting('ayca_test.recurso_megger_id')::uuid;

  if v_megger_sug <> 1 then
    raise exception 'TEST FALLIDO (I): se esperaba cantidad_sugerida=1 para Megger tras quitar el equipo 2, es %.', v_megger_sug;
  end if;
  if v_megger_apr <> 3 then
    raise exception 'TEST FALLIDO (I): ¡se perdió la aprobación! cantidad_aprobada de Megger debía seguir en 3, es %.', v_megger_apr;
  end if;

  -- Rigger (manual, no afectado por el recálculo) sigue conforme (1=1);
  -- Electricista quedó desalineado → personal_estado = 'parcial'.
  select personal_estado, recursos_estado into v_personal_estado, v_recursos_estado
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_personal_estado <> 'parcial' then
    raise exception 'TEST FALLIDO (I): se esperaba personal_estado=parcial (Rigger conforme, Electricista desalineado), es %.', v_personal_estado;
  end if;
  if v_recursos_estado <> 'parcial' then
    raise exception 'TEST FALLIDO (I): se esperaba recursos_estado=parcial (Grúa conforme, Megger desalineado), es %.', v_recursos_estado;
  end if;

  raise notice '✔ I) OK: al quitar el equipo 2, cantidad_sugerida se recalculó (Electricista 3→2, Megger 3→1) SIN tocar cantidad_aprobada (ambas siguen en 3) — estados en parcial.';
end $$;

-- ── J. Negativo: volver a quitar el mismo equipo (ya cancelado) ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_quitar_equipo_evento(current_setting('ayca_test.mant_2_id')::uuid, 'Segundo intento (prueba)');
  exception when others then
    v_fallo := true;
    raise notice '✔ J) OK: no se permitió volver a quitar un equipo ya cancelado — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (J): se permitió quitar dos veces el mismo equipo.';
  end if;
end $$;

-- ── K. Negativo: modificar una línea de origen 'plantilla' a mano ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_modificar_personal_manual_evento(
      current_setting('ayca_test.requerido_electricista_id')::uuid, 10, 'Intento inválido (prueba)'
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ K) OK: no se permitió modificar directamente una línea de plantilla — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (K): se permitió modificar manualmente una línea de origen plantilla.';
  end if;
end $$;

-- ── L. Negativo: quitar una línea sin motivo_modificacion ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_quitar_personal_evento(current_setting('ayca_test.requerido_rigger_id')::uuid, '   ');
  exception when others then
    v_fallo := true;
    raise notice '✔ L) OK: no se permitió eliminar una línea sin motivo — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (L): se permitió eliminar una línea sin motivo_modificacion.';
  end if;
end $$;

-- ── M. Negativo: agregar personal/recurso manual con cantidad <= 0 ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_agregar_personal_manual_evento(current_setting('ayca_test.evento_id')::uuid, 'Soldador', 0);
  exception when others then
    v_fallo := true;
    raise notice '✔ M) OK: no se permitió agregar personal manual con cantidad 0 — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (M): se permitió agregar personal manual con cantidad_sugerida = 0.';
  end if;
end $$;

do $$
begin
  raise notice '✔ TEST 2D.07 COMPLETO: aprobación (B, C, F, H), ajustes manuales (D, E, G), quitar equipo sin perder aprobaciones (I) y negativos (J, K, L, M) se comportaron como se esperaba.';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
