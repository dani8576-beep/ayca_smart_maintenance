-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2D.08
-- (rollup automático de estado / ejecucion_estado / revision_estado)
--
-- Requiere que ya estén ejecutadas todas las migraciones de 2A a 2D.08
-- (incluida la edición de 2D-01 con el vocabulario nuevo).
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK.
--
-- Como todavía no existe ninguna función que haga avanzar el
-- ejecucion_estado/revision_estado de una MANTENCIÓN individual (eso es
-- de una etapa futura, fuera del alcance de 2D-08), este test simula ese
-- avance con UPDATE directo sobre "mantenciones" — válido para probar el
-- CÁLCULO del rollup en sí. Las partes que SÍ están integradas en 2D-08
-- (fn_agregar_equipo_evento y fn_quitar_equipo_evento disparando el
-- rollup automáticamente) se prueban sin llamar a
-- fn_recalcular_estados_evento() a mano — se verifica que ya haya
-- corrido sola.
--
-- Escenarios cubiertos:
--   A) Setup: evento, 1 plantilla con personal/recursos/actividades/
--      protocolos, 3 equipos de prueba.
--   B) Evento vacío → borrador / sin_equipos / no_aplica.
--   C) Un equipo agregado (ejecucion_estado no_iniciada, automático al
--      agregar) → planificado / pendiente.
--   D) Segundo equipo en 'en_curso' (simulado) → mezcla pendiente/en
--      ejecución → en_ejecucion / en_ejecucion.
--   E) Segundo equipo pasa a 'completada' (primero sigue no_iniciada) →
--      mezcla finalizado/pendiente → en_ejecucion / parcial.
--   F) Primer equipo también 'completada' → todos finalizados →
--      finalizado / completado.
--   G) Tercer equipo agregado y luego quitado (fn_quitar_equipo_evento)
--      → mantención cancelada ignorada → el evento vuelve a
--      finalizado/completado pese a la mantención cancelada.
--   H) Evento cancelado no sobrescrito: se fuerza estado='cancelado' y
--      se cambia una mantención hija — el rollup no debe tocar nada.
--   I) Revisión parcial y aprobación total: evento nuevo, revision_estado
--      pasa de en_revision → parcial (tras aprobar personal/recursos,
--      con la mantención todavía sin revisar) → aprobado (al aprobar
--      también la mantención).
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Setup ──
do $$
declare
  v_actor_id       uuid;
  v_cliente_id     uuid;
  v_faena_id       uuid;
  v_area_id        uuid;
  v_tipo_mant_id   uuid;
  v_tipo_protocolo text;
  v_version_test   int;
  v_plantilla_id   uuid;
  v_equipo_1_id    uuid;
  v_equipo_2_id    uuid;
  v_equipo_3_id    uuid;
  v_evento_id      uuid;
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
  values (v_area_id, 'TEST-EQ1-2D08', 'TEST-TAG1-2D08', 'Equipo de prueba 1 (2D.08)', 'Motor eléctrico', true)
  returning id into v_equipo_1_id;
  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_id, 'TEST-EQ2-2D08', 'TEST-TAG2-2D08', 'Equipo de prueba 2 (2D.08)', 'Motor eléctrico', true)
  returning id into v_equipo_2_id;
  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_id, 'TEST-EQ3-2D08', 'TEST-TAG3-2D08', 'Equipo de prueba 3 (2D.08)', 'Motor eléctrico', true)
  returning id into v_equipo_3_id;

  update public.plantillas_mantencion set activa = false
    where tipo_mantencion_id = v_tipo_mant_id and activa = true;

  select coalesce(max(version), 0) + 1000 into v_version_test
    from public.plantillas_mantencion where tipo_mantencion_id = v_tipo_mant_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test, 'TEST_PLANTILLA_2D08', true)
  returning id into v_plantilla_id;

  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_id, 'Electricista', 1, 'Media tensión', true);
  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_id, 'herramienta', 'Megger 5kV', 1, false);
  insert into public.plantilla_actividades (plantilla_id, codigo_actividad, descripcion, orden, obligatoria)
  values (v_plantilla_id, 'TEST-2D08-1.1', 'Actividad de prueba', 1, true);
  insert into public.plantilla_protocolos (plantilla_id, tipo_protocolo, obligatorio)
  values (v_plantilla_id, v_tipo_protocolo, true);

  select id into v_evento_id
  from fn_crear_evento_mantencion(
    p_cliente_id => v_cliente_id, p_faena_id => v_faena_id, p_tipo_evento => 'PROGRAMADA',
    p_nombre => 'TEST evento 2D.08', p_supervisor_id => v_actor_id
  );

  raise notice 'Setup completo -> actor=%, evento=%, equipos=%,%,%, plantilla=%',
    v_actor_id, v_evento_id, v_equipo_1_id, v_equipo_2_id, v_equipo_3_id, v_plantilla_id;

  perform set_config('ayca_test.actor_id',      v_actor_id::text, true);
  perform set_config('ayca_test.cliente_id',    v_cliente_id::text, true);
  perform set_config('ayca_test.faena_id',      v_faena_id::text, true);
  perform set_config('ayca_test.area_id',       v_area_id::text, true);
  perform set_config('ayca_test.tipo_mant_id',  v_tipo_mant_id::text, true);
  perform set_config('ayca_test.plantilla_id',  v_plantilla_id::text, true);
  perform set_config('ayca_test.equipo_1_id',   v_equipo_1_id::text, true);
  perform set_config('ayca_test.equipo_2_id',   v_equipo_2_id::text, true);
  perform set_config('ayca_test.equipo_3_id',   v_equipo_3_id::text, true);
  perform set_config('ayca_test.evento_id',     v_evento_id::text, true);
end $$;

-- ── B. Evento vacío ──
do $$
declare
  v_estado text; v_ejec text; v_rev text;
begin
  perform fn_recalcular_estados_evento(current_setting('ayca_test.evento_id')::uuid);

  select estado, ejecucion_estado, revision_estado into v_estado, v_ejec, v_rev
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_estado <> 'borrador' or v_ejec <> 'sin_equipos' or v_rev <> 'no_aplica' then
    raise exception 'TEST FALLIDO (B): se esperaba borrador/sin_equipos/no_aplica, es %/%/%.', v_estado, v_ejec, v_rev;
  end if;
  raise notice '✔ B) OK: evento vacío -> borrador/sin_equipos/no_aplica.';
end $$;

-- ── C. Un equipo pendiente (automático al agregar) ──
do $$
declare
  v_mant_1_id uuid;
  v_estado text; v_ejec text;
begin
  select mantencion_id into v_mant_1_id
  from fn_agregar_equipo_evento(
    current_setting('ayca_test.evento_id')::uuid, current_setting('ayca_test.area_id')::uuid,
    current_setting('ayca_test.equipo_1_id')::uuid, current_setting('ayca_test.tipo_mant_id')::uuid,
    current_setting('ayca_test.plantilla_id')::uuid
  );
  perform set_config('ayca_test.mant_1_id', v_mant_1_id::text, true);

  select estado, ejecucion_estado into v_estado, v_ejec
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_estado <> 'planificado' or v_ejec <> 'pendiente' then
    raise exception 'TEST FALLIDO (C): se esperaba planificado/pendiente (automático al agregar), es %/%.', v_estado, v_ejec;
  end if;
  raise notice '✔ C) OK: un equipo pendiente -> planificado/pendiente (sin llamar el rollup a mano).';
end $$;

-- ── D. Segundo equipo en 'en_curso' (simulado) — mezcla pendiente/en ejecución ──
do $$
declare
  v_mant_2_id uuid;
  v_estado text; v_ejec text;
begin
  select mantencion_id into v_mant_2_id
  from fn_agregar_equipo_evento(
    current_setting('ayca_test.evento_id')::uuid, current_setting('ayca_test.area_id')::uuid,
    current_setting('ayca_test.equipo_2_id')::uuid, current_setting('ayca_test.tipo_mant_id')::uuid,
    current_setting('ayca_test.plantilla_id')::uuid
  );
  perform set_config('ayca_test.mant_2_id', v_mant_2_id::text, true);

  update public.mantenciones set ejecucion_estado = 'en_curso' where id = v_mant_2_id;
  perform fn_recalcular_estados_evento(current_setting('ayca_test.evento_id')::uuid);

  select estado, ejecucion_estado into v_estado, v_ejec
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_estado <> 'en_ejecucion' or v_ejec <> 'en_ejecucion' then
    raise exception 'TEST FALLIDO (D): se esperaba en_ejecucion/en_ejecucion, es %/%.', v_estado, v_ejec;
  end if;
  raise notice '✔ D) OK: mezcla pendiente/en ejecución -> en_ejecucion/en_ejecucion.';
end $$;

-- ── E. Equipo 2 pasa a 'completada' (equipo 1 sigue no_iniciada) —
--       mezcla finalizado/pendiente ──
do $$
declare
  v_estado text; v_ejec text;
begin
  update public.mantenciones set ejecucion_estado = 'completada'
    where id = current_setting('ayca_test.mant_2_id')::uuid;
  perform fn_recalcular_estados_evento(current_setting('ayca_test.evento_id')::uuid);

  select estado, ejecucion_estado into v_estado, v_ejec
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_estado <> 'en_ejecucion' or v_ejec <> 'parcial' then
    raise exception 'TEST FALLIDO (E): se esperaba en_ejecucion/parcial (mezcla finalizado/pendiente), es %/%.', v_estado, v_ejec;
  end if;
  raise notice '✔ E) OK: mezcla finalizado/pendiente -> en_ejecucion/parcial.';
end $$;

-- ── F. Equipo 1 también 'completada' — todos finalizados ──
do $$
declare
  v_estado text; v_ejec text;
begin
  update public.mantenciones set ejecucion_estado = 'completada'
    where id = current_setting('ayca_test.mant_1_id')::uuid;
  perform fn_recalcular_estados_evento(current_setting('ayca_test.evento_id')::uuid);

  select estado, ejecucion_estado into v_estado, v_ejec
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_estado <> 'finalizado' or v_ejec <> 'completado' then
    raise exception 'TEST FALLIDO (F): se esperaba finalizado/completado, es %/%.', v_estado, v_ejec;
  end if;
  raise notice '✔ F) OK: todos finalizados -> finalizado/completado.';
end $$;

-- ── G. Tercer equipo agregado y luego quitado — mantención cancelada
--       ignorada; el evento vuelve a finalizado/completado ──
do $$
declare
  v_mant_3_id uuid;
  v_estado text; v_ejec text;
begin
  select mantencion_id into v_mant_3_id
  from fn_agregar_equipo_evento(
    current_setting('ayca_test.evento_id')::uuid, current_setting('ayca_test.area_id')::uuid,
    current_setting('ayca_test.equipo_3_id')::uuid, current_setting('ayca_test.tipo_mant_id')::uuid,
    current_setting('ayca_test.plantilla_id')::uuid
  );

  -- Al agregarlo (no_iniciada), el evento vuelve a una mezcla (2
  -- completadas + 1 no_iniciada) — se verifica de paso.
  select estado, ejecucion_estado into v_estado, v_ejec
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_estado <> 'en_ejecucion' or v_ejec <> 'parcial' then
    raise exception 'TEST FALLIDO (G-intermedio): se esperaba en_ejecucion/parcial tras agregar el tercer equipo, es %/%.', v_estado, v_ejec;
  end if;

  -- Quitarlo del evento (fn_quitar_equipo_evento, dispara el rollup solo).
  perform fn_quitar_equipo_evento(v_mant_3_id, 'Prueba 2D.08 — equipo 3 no participa finalmente');

  select estado, ejecucion_estado into v_estado, v_ejec
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_estado <> 'finalizado' or v_ejec <> 'completado' then
    raise exception 'TEST FALLIDO (G): se esperaba que la mantención cancelada quedara ignorada (finalizado/completado), es %/%.', v_estado, v_ejec;
  end if;

  raise notice '✔ G) OK: mantención cancelada ignorada -> el evento vuelve a finalizado/completado tras quitar el equipo 3.';
end $$;

-- ── H. Evento cancelado no sobrescrito ──
do $$
declare
  v_estado text; v_ejec text; v_rev text;
begin
  update public.eventos_mantencion set estado = 'cancelado'
    where id = current_setting('ayca_test.evento_id')::uuid;

  -- Cambiar una mantención hija después de cancelar el evento — el
  -- rollup NO debe reaccionar a esto en absoluto.
  update public.mantenciones set ejecucion_estado = 'no_iniciada'
    where id = current_setting('ayca_test.mant_1_id')::uuid;

  perform fn_recalcular_estados_evento(current_setting('ayca_test.evento_id')::uuid);

  select estado, ejecucion_estado, revision_estado into v_estado, v_ejec, v_rev
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_estado <> 'cancelado' then
    raise exception 'TEST FALLIDO (H): el rollup sobrescribió un evento cancelado (estado=%).', v_estado;
  end if;
  -- ejecucion_estado/revision_estado tampoco deben haberse tocado (el
  -- rollup retorna antes de llegar al UPDATE cuando estado=cancelado).
  if v_ejec <> 'completado' then
    raise exception 'TEST FALLIDO (H): ejecucion_estado cambió pese a que el evento está cancelado (es %, se esperaba que quedara en completado).', v_ejec;
  end if;

  raise notice '✔ H) OK: evento cancelado NO sobrescrito por el rollup automático (estado=cancelado, ejecucion_estado sin cambios).';
end $$;

-- ── I. Revisión parcial y aprobación total (evento nuevo) ──
do $$
declare
  v_evento_2_id uuid;
  v_mant_id     uuid;
  v_requerido_id uuid;
  v_recurso_id   uuid;
  v_rev text;
begin
  select id into v_evento_2_id
  from fn_crear_evento_mantencion(
    p_cliente_id => current_setting('ayca_test.cliente_id')::uuid,
    p_faena_id   => current_setting('ayca_test.faena_id')::uuid,
    p_tipo_evento => 'PROGRAMADA', p_nombre => 'TEST evento 2D.08 — revisión',
    p_supervisor_id => current_setting('ayca_test.actor_id')::uuid
  );

  select mantencion_id into v_mant_id
  from fn_agregar_equipo_evento(
    v_evento_2_id, current_setting('ayca_test.area_id')::uuid,
    current_setting('ayca_test.equipo_1_id')::uuid, current_setting('ayca_test.tipo_mant_id')::uuid,
    current_setting('ayca_test.plantilla_id')::uuid
  );

  select revision_estado into v_rev from eventos_mantencion where id = v_evento_2_id;
  if v_rev <> 'en_revision' then
    raise exception 'TEST FALLIDO (I-1): se esperaba revision_estado=en_revision recién agregado el equipo, es %.', v_rev;
  end if;

  -- Aprobar personal y recursos (bulk) — la mantención en sí sigue sin revisar.
  select id into v_requerido_id from evento_personal_requerido where evento_mantencion_id = v_evento_2_id;
  select id into v_recurso_id   from evento_recursos           where evento_mantencion_id = v_evento_2_id;

  perform fn_aprobar_evento_personal(v_evento_2_id);
  perform fn_aprobar_evento_recursos(v_evento_2_id);

  select revision_estado into v_rev from eventos_mantencion where id = v_evento_2_id;
  if v_rev <> 'parcial' then
    raise exception 'TEST FALLIDO (I-2): se esperaba revision_estado=parcial (personal/recursos aprobados, mantención sin revisar), es %.', v_rev;
  end if;
  raise notice '✔ I-2) OK: revision_estado=parcial tras aprobar personal y recursos, con la mantención todavía sin revisar.';

  -- Aprobar también la mantención (simulado — no existe aún una función
  -- dedicada para esto, fuera del alcance de 2D-08).
  update public.mantenciones set revision_estado = 'aprobada' where id = v_mant_id;
  perform fn_recalcular_estados_evento(v_evento_2_id);

  select revision_estado into v_rev from eventos_mantencion where id = v_evento_2_id;
  if v_rev <> 'aprobado' then
    raise exception 'TEST FALLIDO (I-3): se esperaba revision_estado=aprobado tras aprobar también la mantención, es %.', v_rev;
  end if;

  raise notice '✔ I-3) OK: revision_estado=aprobado cuando mantención + personal + recursos están todos conformes.';
end $$;

do $$
begin
  raise notice '✔ TEST 2D.08 COMPLETO: B, C, D, E, F, G, H, I se comportaron como se esperaba.';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
