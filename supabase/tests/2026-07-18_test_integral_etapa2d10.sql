-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test INTEGRAL de la ETAPA 2D.10
-- (motor multiequipo completo, de punta a punta)
--
-- Requiere que ya estén ejecutadas todas las migraciones de 2A a 2D.09.
-- NO introduce lógica de negocio nueva — solo ejercita, con datos y
-- cantidades reales, las funciones ya construidas en 2D-01 a 2D-09.
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK.
--
-- ── ESCENARIO ──
-- 1 evento (CODELCO → Andina), 3 equipos:
--   - equipo 1 → MANTENCION_MENSUAL   / plantilla A
--   - equipo 2 → MANTENCION_SEMESTRAL / plantilla B  (se retira más tarde)
--   - equipo 3 → MANTENCION_MENSUAL   / plantilla A  (misma plantilla que el 1)
-- plantilla A: personal Electricista/Media tensión (cant=2), recurso
--   Megger 5kV (cant=1), 2 actividades, protocolo control_dimensional.
-- plantilla B: personal Electricista/Media tensión (cant=1 — MISMO
--   perfil que A, para forzar consolidación), recursos Megger 5kV
--   (cant=2 — mismo recurso, consolida) + Pie de metro (cant=1 —
--   recurso distinto, solo de B), 1 actividad distinta, protocolo
--   dielectrico (distinto).
-- Personal/recurso manual: Rigger (cant=2), Grúa horquilla (cant=1).
--
-- ── MATEMÁTICA ESPERADA (se verifica en cada fase) ──
--   Tras agregar los 3 equipos:
--     Electricista: sugerida = 2+1+2 = 5
--     Megger 5kV:   sugerida = 1+2+1 = 4
--     Pie de metro: sugerida = 1 (solo equipo 2)
--   Tras agregar Rigger(2) y Grúa(1) manuales, y aprobar TODO:
--     Electricista aprobada=5, Rigger aprobada=2,
--     Megger aprobada=4, Pie de metro aprobada=1, Grúa aprobada=1.
--   Tras RETIRAR el equipo 2 (aportaba Electricista=1, Megger=2, Pie de
--   metro=1 — su única fuente):
--     Electricista sugerida 5→4 (aprobada SIGUE en 5 → desalineada)
--     Megger        sugerida 4→2 (aprobada SIGUE en 4 → desalineada)
--     Pie de metro  sugerida 1→0 (aprobada SIGUE en 1 → desalineada)
--     Rigger y Grúa (manuales) no cambian — siguen conformes.
--   personal_estado/recursos_estado → 'parcial' (1 de 2 y 1 de 3
--   conformes, respectivamente).
--   Tras finalizar equipos 1 y 3 (los únicos vigentes): estado=finalizado,
--   ejecucion_estado=completado, revision_estado pasa a 'en_revision'
--   (no "se mantiene en parcial": fn_recalcular_estados_evento recalcula
--   revision_estado desde cero en cada llamada, y con personal_estado/
--   recursos_estado todavía en 'parcial' — sin cambios desde G — ninguna
--   unidad queda conforme, lo que corresponde a 'en_revision', no a
--   'parcial'; 'parcial' exige que AL MENOS una unidad esté conforme).
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Setup: datos maestros, usuarios reales, equipos, plantillas ──
do $$
declare
  v_admin_id        uuid;
  v_actor_id        uuid;
  v_actor_2_id      uuid;
  v_cliente_id      uuid;
  v_faena_andina_id uuid;
  v_faena_tte_id    uuid;
  v_area_andina_id  uuid;
  v_area_tte_id     uuid;
  v_tipo_mensual_id uuid;
  v_tipo_semestral_id uuid;
  v_protocolo_dimensional text;
  v_protocolo_dielectrico text;
  v_version_a       int;
  v_version_b       int;
  v_plantilla_a_id  uuid;
  v_plantilla_b_id  uuid;
  v_equipo_1_id     uuid;
  v_equipo_2_id     uuid;
  v_equipo_3_id     uuid;
  v_equipo_4_id     uuid; -- Teniente, solo para el negativo de cruce de faena
begin
  select ur.usuario_id into v_admin_id from public.usuario_roles ur where ur.rol = 'administrador' limit 1;
  if v_admin_id is null then
    raise exception 'TEST ABORTADO: se necesita al menos un administrador.';
  end if;

  select ur.usuario_id into v_actor_id from public.usuario_roles ur where ur.rol = 'supervisor' limit 1;
  if v_actor_id is null then v_actor_id := v_admin_id; end if;

  select u.id into v_actor_2_id from auth.users u where u.id <> v_actor_id and u.id <> v_admin_id limit 1;
  if v_actor_2_id is null then
    raise notice 'AVISO: no hay un segundo usuario real — se omiten los pasos de asignación de técnico y las verificaciones RLS de persona (se avisa en cada paso omitido).';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text)::text, true);

  select id into v_cliente_id from public.clientes where codigo = 'CODELCO';
  select id into v_faena_andina_id from public.faenas where cliente_id = v_cliente_id and codigo = 'ANDINA';
  select id into v_faena_tte_id    from public.faenas where cliente_id = v_cliente_id and codigo = 'TENIENTE';
  select id into v_area_andina_id  from public.areas where faena_id = v_faena_andina_id and codigo = 'MOLIENDA';
  select id into v_area_tte_id     from public.areas where faena_id = v_faena_tte_id    and codigo = 'MOLIENDA';
  if v_cliente_id is null or v_faena_andina_id is null or v_faena_tte_id is null
     or v_area_andina_id is null or v_area_tte_id is null then
    raise exception 'TEST ABORTADO: no se encontró CODELCO → Andina/Teniente → Molienda.';
  end if;

  select id into v_tipo_mensual_id   from public.tipos_mantencion where codigo = 'MANTENCION_MENSUAL';
  select id into v_tipo_semestral_id from public.tipos_mantencion where codigo = 'MANTENCION_SEMESTRAL';
  select codigo into v_protocolo_dimensional from public.tipos_protocolo where codigo = 'control_dimensional';
  select codigo into v_protocolo_dielectrico  from public.tipos_protocolo where codigo = 'dielectrico';
  if v_tipo_mensual_id is null or v_tipo_semestral_id is null
     or v_protocolo_dimensional is null or v_protocolo_dielectrico is null then
    raise exception 'TEST ABORTADO: faltan tipos de mantención o de protocolo maestros.';
  end if;

  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_andina_id, 'TEST-EQ1-2D10', 'TEST-TAG1-2D10', 'Equipo de prueba 1 (2D.10)', 'Motor eléctrico', true)
  returning id into v_equipo_1_id;
  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_andina_id, 'TEST-EQ2-2D10', 'TEST-TAG2-2D10', 'Equipo de prueba 2 (2D.10)', 'Motor eléctrico', true)
  returning id into v_equipo_2_id;
  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_andina_id, 'TEST-EQ3-2D10', 'TEST-TAG3-2D10', 'Equipo de prueba 3 (2D.10)', 'Motor eléctrico', true)
  returning id into v_equipo_3_id;
  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_tte_id, 'TEST-EQ4-2D10', 'TEST-TAG4-2D10', 'Equipo de prueba 4, Teniente (2D.10)', 'Motor eléctrico', true)
  returning id into v_equipo_4_id;

  update public.plantillas_mantencion set activa = false
    where tipo_mantencion_id in (v_tipo_mensual_id, v_tipo_semestral_id) and activa = true;

  select coalesce(max(version), 0) + 1000 into v_version_a from public.plantillas_mantencion where tipo_mantencion_id = v_tipo_mensual_id;
  select coalesce(max(version), 0) + 1000 into v_version_b from public.plantillas_mantencion where tipo_mantencion_id = v_tipo_semestral_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mensual_id, v_version_a, 'TEST_PLANTILLA_A_2D10', true)
  returning id into v_plantilla_a_id;
  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_semestral_id, v_version_b, 'TEST_PLANTILLA_B_2D10', true)
  returning id into v_plantilla_b_id;

  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_a_id, 'Electricista', 2, 'Media tensión', true);
  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_b_id, 'Electricista', 1, 'Media tensión', true);

  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_a_id, 'herramienta', 'Megger 5kV', 1, false);
  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_b_id, 'herramienta', 'Megger 5kV', 2, false);
  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_b_id, 'instrumento', 'Pie de metro', 1, false);

  insert into public.plantilla_actividades (plantilla_id, codigo_actividad, descripcion, orden, obligatoria)
  values
    (v_plantilla_a_id, 'INT-A-1.1', 'Actividad A — 1', 1, true),
    (v_plantilla_a_id, 'INT-A-1.2', 'Actividad A — 2', 2, true);
  insert into public.plantilla_actividades (plantilla_id, codigo_actividad, descripcion, orden, obligatoria)
  values (v_plantilla_b_id, 'INT-B-2.1', 'Actividad B — 1', 1, true);

  insert into public.plantilla_protocolos (plantilla_id, tipo_protocolo, obligatorio)
  values (v_plantilla_a_id, v_protocolo_dimensional, true);
  insert into public.plantilla_protocolos (plantilla_id, tipo_protocolo, obligatorio)
  values (v_plantilla_b_id, v_protocolo_dielectrico, true);

  perform set_config('ayca_test.admin_id',        v_admin_id::text, true);
  perform set_config('ayca_test.actor_id',        v_actor_id::text, true);
  perform set_config('ayca_test.actor_2_id',      coalesce(v_actor_2_id::text, ''), true);
  perform set_config('ayca_test.tiene_actor_2',   (v_actor_2_id is not null)::text, true);
  perform set_config('ayca_test.cliente_id',      v_cliente_id::text, true);
  perform set_config('ayca_test.faena_andina_id', v_faena_andina_id::text, true);
  perform set_config('ayca_test.area_andina_id',  v_area_andina_id::text, true);
  perform set_config('ayca_test.area_tte_id',     v_area_tte_id::text, true);
  perform set_config('ayca_test.tipo_mensual_id', v_tipo_mensual_id::text, true);
  perform set_config('ayca_test.tipo_semestral_id', v_tipo_semestral_id::text, true);
  perform set_config('ayca_test.plantilla_a_id',  v_plantilla_a_id::text, true);
  perform set_config('ayca_test.plantilla_b_id',  v_plantilla_b_id::text, true);
  perform set_config('ayca_test.equipo_1_id',     v_equipo_1_id::text, true);
  perform set_config('ayca_test.equipo_2_id',     v_equipo_2_id::text, true);
  perform set_config('ayca_test.equipo_3_id',     v_equipo_3_id::text, true);
  perform set_config('ayca_test.equipo_4_id',     v_equipo_4_id::text, true);

  raise notice 'Setup completo -> admin=%, actor=%, tiene_actor_2=%, equipos=%,%,%,%',
    v_admin_id, v_actor_id, (v_actor_2_id is not null), v_equipo_1_id, v_equipo_2_id, v_equipo_3_id, v_equipo_4_id;
end $$;

-- ── B. Crear el evento y agregar los 3 equipos ──
do $$
declare
  v_evento_id uuid;
  v_mant_1_id uuid;
  v_mant_2_id uuid;
  v_mant_3_id uuid;
begin
  select id into v_evento_id
  from fn_crear_evento_mantencion(
    p_cliente_id => current_setting('ayca_test.cliente_id')::uuid,
    p_faena_id   => current_setting('ayca_test.faena_andina_id')::uuid,
    p_tipo_evento => 'PARADA_GENERAL', p_nombre => 'TEST evento integral 2D.10',
    p_supervisor_id => current_setting('ayca_test.actor_id')::uuid
  );

  select mantencion_id into v_mant_1_id from fn_agregar_equipo_evento(
    v_evento_id, current_setting('ayca_test.area_andina_id')::uuid, current_setting('ayca_test.equipo_1_id')::uuid,
    current_setting('ayca_test.tipo_mensual_id')::uuid, current_setting('ayca_test.plantilla_a_id')::uuid
  );
  select mantencion_id into v_mant_2_id from fn_agregar_equipo_evento(
    v_evento_id, current_setting('ayca_test.area_andina_id')::uuid, current_setting('ayca_test.equipo_2_id')::uuid,
    current_setting('ayca_test.tipo_semestral_id')::uuid, current_setting('ayca_test.plantilla_b_id')::uuid
  );
  select mantencion_id into v_mant_3_id from fn_agregar_equipo_evento(
    v_evento_id, current_setting('ayca_test.area_andina_id')::uuid, current_setting('ayca_test.equipo_3_id')::uuid,
    current_setting('ayca_test.tipo_mensual_id')::uuid, current_setting('ayca_test.plantilla_a_id')::uuid
  );

  perform set_config('ayca_test.evento_id', v_evento_id::text, true);
  perform set_config('ayca_test.mant_1_id', v_mant_1_id::text, true);
  perform set_config('ayca_test.mant_2_id', v_mant_2_id::text, true);
  perform set_config('ayca_test.mant_3_id', v_mant_3_id::text, true);

  raise notice '✔ B) OK: evento=% con 3 mantenciones creadas (%,%,%).', v_evento_id, v_mant_1_id, v_mant_2_id, v_mant_3_id;
end $$;

-- ── C. Verificación de snapshot y consolidación tras agregar los 3 equipos ──
do $$
declare
  v_n int; v_electricista_id uuid; v_electricista_sug numeric;
  v_megger_id uuid; v_megger_sug numeric; v_pie_id uuid; v_pie_sug numeric;
begin
  select count(*) into v_n from mantenciones where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;
  if v_n <> 3 then raise exception 'TEST FALLIDO (C): se esperaban 3 mantenciones hijas, hay %.', v_n; end if;

  select count(*) into v_n from mantencion_actividades where mantencion_id = current_setting('ayca_test.mant_1_id')::uuid;
  if v_n <> 2 then raise exception 'TEST FALLIDO (C): equipo 1 debía tener 2 actividades (plantilla A), tiene %.', v_n; end if;
  select count(*) into v_n from mantencion_actividades where mantencion_id = current_setting('ayca_test.mant_2_id')::uuid;
  if v_n <> 1 then raise exception 'TEST FALLIDO (C): equipo 2 debía tener 1 actividad (plantilla B), tiene %.', v_n; end if;
  select count(*) into v_n from mantencion_protocolos where mantencion_id = current_setting('ayca_test.mant_2_id')::uuid;
  if v_n <> 1 then raise exception 'TEST FALLIDO (C): equipo 2 debía tener 1 protocolo (dielectrico), tiene %.', v_n; end if;

  select count(*) into v_n from mantencion_personal
    where mantencion_id in (current_setting('ayca_test.mant_1_id')::uuid, current_setting('ayca_test.mant_2_id')::uuid, current_setting('ayca_test.mant_3_id')::uuid);
  if v_n <> 0 then raise exception 'TEST FALLIDO (C): mantencion_personal debe estar VACÍA en flujo evento, tiene % fila(s).', v_n; end if;
  select count(*) into v_n from mantencion_recursos
    where mantencion_id in (current_setting('ayca_test.mant_1_id')::uuid, current_setting('ayca_test.mant_2_id')::uuid, current_setting('ayca_test.mant_3_id')::uuid);
  if v_n <> 0 then raise exception 'TEST FALLIDO (C): mantencion_recursos debe estar VACÍA en flujo evento, tiene % fila(s).', v_n; end if;

  select id, cantidad_sugerida into v_electricista_id, v_electricista_sug
    from evento_personal_requerido where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;
  if v_electricista_sug <> 5 then raise exception 'TEST FALLIDO (C): Electricista debía consolidar sugerida=5 (2+1+2), es %.', v_electricista_sug; end if;

  select count(*) into v_n from evento_recursos where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;
  if v_n <> 2 then raise exception 'TEST FALLIDO (C): se esperaban 2 líneas de recursos (Megger, Pie de metro), hay %.', v_n; end if;

  select id, cantidad_sugerida into v_megger_id, v_megger_sug
    from evento_recursos where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid and nombre_generico = 'Megger 5kV';
  if v_megger_sug <> 4 then raise exception 'TEST FALLIDO (C): Megger 5kV debía consolidar sugerida=4 (1+2+1), es %.', v_megger_sug; end if;

  select id, cantidad_sugerida into v_pie_id, v_pie_sug
    from evento_recursos where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid and nombre_generico = 'Pie de metro';
  if v_pie_sug <> 1 then raise exception 'TEST FALLIDO (C): Pie de metro debía consolidar sugerida=1 (solo equipo 2), es %.', v_pie_sug; end if;

  select count(*) into v_n from evento_personal_origen where evento_personal_requerido_id = v_electricista_id and estado = 'activo';
  if v_n <> 3 then raise exception 'TEST FALLIDO (C): se esperaban 3 filas de origen activas para Electricista (una por equipo), hay %.', v_n; end if;

  select count(*) into v_n from evento_recursos_origen where evento_recursos_id = v_megger_id and estado = 'activo';
  if v_n <> 3 then raise exception 'TEST FALLIDO (C): se esperaban 3 filas de origen activas para Megger 5kV, hay %.', v_n; end if;

  perform set_config('ayca_test.requerido_electricista_id', v_electricista_id::text, true);
  perform set_config('ayca_test.recurso_megger_id', v_megger_id::text, true);
  perform set_config('ayca_test.recurso_pie_id', v_pie_id::text, true);

  raise notice '✔ C) OK: 3 mantenciones, snapshot correcto, mantencion_personal/recursos vacías, consolidación Electricista=5/Megger=4/Pie de metro=1, 3+3 filas de origen activas.';
end $$;

-- ── D. Personal y recursos manuales (Rigger, Grúa horquilla) ──
do $$
declare
  v_rigger_id uuid;
  v_grua_id uuid;
  v_n int;
begin
  v_rigger_id := fn_agregar_personal_manual_evento(current_setting('ayca_test.evento_id')::uuid, 'Rigger', 2);
  v_grua_id := fn_agregar_recurso_manual_evento(current_setting('ayca_test.evento_id')::uuid, 'equipo_apoyo', 'Grúa horquilla', 1);

  select count(*) into v_n from evento_personal_requerido where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;
  if v_n <> 2 then raise exception 'TEST FALLIDO (D): se esperaban 2 líneas de personal (Electricista + Rigger), hay %.', v_n; end if;
  select count(*) into v_n from evento_recursos where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;
  if v_n <> 3 then raise exception 'TEST FALLIDO (D): se esperaban 3 líneas de recursos (Megger + Pie de metro + Grúa), hay %.', v_n; end if;

  perform set_config('ayca_test.requerido_rigger_id', v_rigger_id::text, true);
  perform set_config('ayca_test.recurso_grua_id', v_grua_id::text, true);

  raise notice '✔ D) OK: Rigger (personal manual) y Grúa horquilla (recurso manual) agregados.';
end $$;

-- ── E. Aprobación PARCIAL: solo Electricista ──
do $$
declare v_personal_estado text; v_recursos_estado text;
begin
  perform fn_aprobar_personal_evento(current_setting('ayca_test.requerido_electricista_id')::uuid);

  select personal_estado, recursos_estado into v_personal_estado, v_recursos_estado
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_personal_estado <> 'parcial' then
    raise exception 'TEST FALLIDO (E): se esperaba personal_estado=parcial (Electricista aprobado, Rigger no), es %.', v_personal_estado;
  end if;
  if v_recursos_estado <> 'en_revision' then
    raise exception 'TEST FALLIDO (E): se esperaba recursos_estado=en_revision (nada aprobado todavía), es %.', v_recursos_estado;
  end if;

  raise notice '✔ E) OK: aprobación parcial — personal_estado=parcial, recursos_estado=en_revision.';
end $$;

-- ── F. Aprobación COMPLETA (bulk personal + recursos) ──
do $$
declare
  v_personal_estado text; v_recursos_estado text;
  v_apr_electricista numeric; v_apr_rigger numeric;
  v_apr_megger numeric; v_apr_pie numeric; v_apr_grua numeric;
begin
  perform fn_aprobar_evento_personal(current_setting('ayca_test.evento_id')::uuid);
  perform fn_aprobar_evento_recursos(current_setting('ayca_test.evento_id')::uuid);

  select personal_estado, recursos_estado into v_personal_estado, v_recursos_estado
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_personal_estado <> 'aprobado' or v_recursos_estado <> 'aprobado' then
    raise exception 'TEST FALLIDO (F): se esperaba personal_estado/recursos_estado=aprobado, son %/%.', v_personal_estado, v_recursos_estado;
  end if;

  select cantidad_aprobada into v_apr_electricista from evento_personal_requerido where id = current_setting('ayca_test.requerido_electricista_id')::uuid;
  select cantidad_aprobada into v_apr_rigger        from evento_personal_requerido where id = current_setting('ayca_test.requerido_rigger_id')::uuid;
  select cantidad_aprobada into v_apr_megger        from evento_recursos where id = current_setting('ayca_test.recurso_megger_id')::uuid;
  select cantidad_aprobada into v_apr_pie           from evento_recursos where id = current_setting('ayca_test.recurso_pie_id')::uuid;
  select cantidad_aprobada into v_apr_grua          from evento_recursos where id = current_setting('ayca_test.recurso_grua_id')::uuid;

  if v_apr_electricista <> 5 or v_apr_rigger <> 2 or v_apr_megger <> 4 or v_apr_pie <> 1 or v_apr_grua <> 1 then
    raise exception 'TEST FALLIDO (F): cantidades aprobadas inesperadas — Electricista=% Rigger=% Megger=% Pie=% Grúa=% (esperado 5,2,4,1,1).',
      v_apr_electricista, v_apr_rigger, v_apr_megger, v_apr_pie, v_apr_grua;
  end if;

  raise notice '✔ F) OK: aprobación completa — todo aprobado con las cantidades esperadas (Electricista=5, Rigger=2, Megger=4, Pie de metro=1, Grúa=1).';
end $$;

-- ── G. Retiro del equipo 2 — recalculo SIN perder aprobaciones ──
do $$
declare
  v_mant_2_estado text;
  v_sug numeric; v_apr numeric;
  v_personal_estado text; v_recursos_estado text; v_estado text; v_ejec text;
  v_n int;
begin
  perform fn_quitar_equipo_evento(current_setting('ayca_test.mant_2_id')::uuid, 'Prueba integral 2D.10 — equipo 2 se retira');

  select estado into v_mant_2_estado from mantenciones where id = current_setting('ayca_test.mant_2_id')::uuid;
  if v_mant_2_estado <> 'cancelada' then raise exception 'TEST FALLIDO (G): la mantención 2 debía quedar cancelada, está %.', v_mant_2_estado; end if;

  select cantidad_sugerida, cantidad_aprobada into v_sug, v_apr from evento_personal_requerido where id = current_setting('ayca_test.requerido_electricista_id')::uuid;
  if v_sug <> 4 then raise exception 'TEST FALLIDO (G): Electricista sugerida debía bajar a 4, es %.', v_sug; end if;
  if v_apr <> 5 then raise exception 'TEST FALLIDO (G): ¡se perdió la aprobación! Electricista aprobada debía seguir en 5, es %.', v_apr; end if;

  select cantidad_sugerida, cantidad_aprobada into v_sug, v_apr from evento_recursos where id = current_setting('ayca_test.recurso_megger_id')::uuid;
  if v_sug <> 2 then raise exception 'TEST FALLIDO (G): Megger sugerida debía bajar a 2, es %.', v_sug; end if;
  if v_apr <> 4 then raise exception 'TEST FALLIDO (G): ¡se perdió la aprobación! Megger aprobada debía seguir en 4, es %.', v_apr; end if;

  select cantidad_sugerida, cantidad_aprobada into v_sug, v_apr from evento_recursos where id = current_setting('ayca_test.recurso_pie_id')::uuid;
  if v_sug <> 0 then raise exception 'TEST FALLIDO (G): Pie de metro sugerida debía bajar a 0 (su único aporte era el equipo 2), es %.', v_sug; end if;
  if v_apr <> 1 then raise exception 'TEST FALLIDO (G): ¡se perdió la aprobación! Pie de metro aprobada debía seguir en 1, es %.', v_apr; end if;

  select personal_estado, recursos_estado, estado, ejecucion_estado
    into v_personal_estado, v_recursos_estado, v_estado, v_ejec
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_personal_estado <> 'parcial' then raise exception 'TEST FALLIDO (G): se esperaba personal_estado=parcial, es %.', v_personal_estado; end if;
  if v_recursos_estado <> 'parcial' then raise exception 'TEST FALLIDO (G): se esperaba recursos_estado=parcial, es %.', v_recursos_estado; end if;
  if v_estado <> 'planificado' or v_ejec <> 'pendiente' then
    raise exception 'TEST FALLIDO (G): con equipo 2 cancelado y 1/3 no_iniciados, se esperaba planificado/pendiente, es %/%.', v_estado, v_ejec;
  end if;

  select count(*) into v_n from evento_personal_origen
    where mantencion_id = current_setting('ayca_test.mant_2_id')::uuid and estado = 'retirado';
  if v_n <> 1 then raise exception 'TEST FALLIDO (G): se esperaba 1 fila de evento_personal_origen retirada para el equipo 2, hay %.', v_n; end if;

  select count(*) into v_n from evento_recursos_origen
    where mantencion_id = current_setting('ayca_test.mant_2_id')::uuid and estado = 'retirado';
  if v_n <> 2 then raise exception 'TEST FALLIDO (G): se esperaban 2 filas de evento_recursos_origen retiradas para el equipo 2 (Megger + Pie de metro), hay %.', v_n; end if;

  select count(*) into v_n from evento_personal_origen where evento_personal_requerido_id = current_setting('ayca_test.requerido_electricista_id')::uuid and estado = 'activo';
  if v_n <> 2 then raise exception 'TEST FALLIDO (G): deben quedar 2 filas de origen ACTIVAS para Electricista (equipos 1 y 3), hay %.', v_n; end if;

  raise notice '✔ G) OK: equipo 2 retirado — sugeridas recalculadas (Electricista 5→4, Megger 4→2, Pie de metro 1→0), aprobadas SIN cambios (5,4,1), estados en parcial/planificado/pendiente, filas de origen correctamente retiradas.';
end $$;

-- ── H. Finalización de las mantenciones restantes (equipos 1 y 3) ──
do $$
declare v_estado text; v_ejec text; v_rev text;
begin
  update public.mantenciones set ejecucion_estado = 'completada'
    where id in (current_setting('ayca_test.mant_1_id')::uuid, current_setting('ayca_test.mant_3_id')::uuid);

  perform fn_recalcular_estados_evento(current_setting('ayca_test.evento_id')::uuid);

  select estado, ejecucion_estado, revision_estado into v_estado, v_ejec, v_rev
    from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;

  if v_estado <> 'finalizado' or v_ejec <> 'completado' then
    raise exception 'TEST FALLIDO (H): se esperaba finalizado/completado, es %/%.', v_estado, v_ejec;
  end if;
  if v_rev <> 'en_revision' then
    raise exception 'TEST FALLIDO (H): revision_estado se recalcula en cada llamada a fn_recalcular_estados_evento — con personal_estado/recursos_estado todavía en ''parcial'' (sin cambios desde G), ninguna unidad queda conforme, así que corresponde ''en_revision'', no ''parcial''. Se esperaba en_revision, es %.', v_rev;
  end if;

  raise notice '✔ H) OK: equipos 1 y 3 finalizados — estado=finalizado, ejecucion_estado=completado, revision_estado=en_revision (recalculado desde cero; personal_estado/recursos_estado siguen en parcial desde G, así que ninguna unidad queda conforme).';
end $$;

-- ── I. Asignación de técnico (requiere un segundo usuario real) ──
do $$
declare
  v_asig_1_id uuid;
  v_asig_2_id uuid;
  v_n_vigentes int;
  v_n_liberadas int;
begin
  if current_setting('ayca_test.tiene_actor_2') <> 'true' then
    raise notice 'AVISO: se omite I (asignación de técnico) — no hay un segundo usuario real disponible.';
    return;
  end if;

  insert into public.perfiles_ayca (id, nombre, activo)
  values (current_setting('ayca_test.actor_2_id')::uuid, 'Técnico de prueba 2D.10', true)
  on conflict (id) do update set activo = true;

  v_asig_1_id := fn_asignar_persona_evento(
    current_setting('ayca_test.evento_id')::uuid, current_setting('ayca_test.actor_2_id')::uuid,
    'Electricista', p_evento_personal_requerido_id => current_setting('ayca_test.requerido_electricista_id')::uuid
  );

  perform fn_quitar_persona_evento(v_asig_1_id, 'Prueba 2D.10 — liberar para reasignar extraordinario');

  v_asig_2_id := fn_asignar_persona_evento(
    current_setting('ayca_test.evento_id')::uuid, current_setting('ayca_test.actor_2_id')::uuid,
    'Supervisor de apoyo'
  );

  select count(*) into v_n_vigentes  from evento_personal_asignado where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid and estado_asignacion <> 'liberado';
  select count(*) into v_n_liberadas from evento_personal_asignado where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid and estado_asignacion = 'liberado';

  if v_n_vigentes <> 1 or v_n_liberadas <> 1 then
    raise exception 'TEST FALLIDO (I): se esperaba 1 asignación vigente y 1 liberada, hay %/%.', v_n_vigentes, v_n_liberadas;
  end if;

  perform set_config('ayca_test.asig_vigente_id', v_asig_2_id::text, true);
  raise notice '✔ I) OK: 1 asignación vigente (extraordinaria) y 1 liberada (Electricista, reemplazada).';
end $$;

-- ═══════════════════════════════════════════════════════════════
-- NEGATIVOS
-- ═══════════════════════════════════════════════════════════════

-- ── J. Duplicado: re-agregar el equipo 1 (ya activo) al mismo evento ──
do $$
declare v_fallo boolean := false;
begin
  begin
    perform mantencion_id from fn_agregar_equipo_evento(
      current_setting('ayca_test.evento_id')::uuid, current_setting('ayca_test.area_andina_id')::uuid,
      current_setting('ayca_test.equipo_1_id')::uuid, current_setting('ayca_test.tipo_mensual_id')::uuid,
      current_setting('ayca_test.plantilla_a_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ J) OK: duplicado rechazado — %', sqlerrm;
  end;
  if not v_fallo then raise exception 'TEST FALLIDO (J): se permitió re-agregar un equipo ya activo en el evento.'; end if;
end $$;

-- ── K. Cruce de faena: equipo 4 (Teniente) contra un evento de Andina ──
do $$
declare v_fallo boolean := false;
begin
  begin
    perform mantencion_id from fn_agregar_equipo_evento(
      current_setting('ayca_test.evento_id')::uuid, current_setting('ayca_test.area_tte_id')::uuid,
      current_setting('ayca_test.equipo_4_id')::uuid, current_setting('ayca_test.tipo_mensual_id')::uuid,
      current_setting('ayca_test.plantilla_a_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ K) OK: cruce de faena rechazado — %', sqlerrm;
  end;
  if not v_fallo then raise exception 'TEST FALLIDO (K): se permitió agregar un equipo de otra faena.'; end if;
end $$;

-- ── L. Doble retiro: volver a quitar el equipo 2 (ya cancelado) ──
do $$
declare v_fallo boolean := false;
begin
  begin
    perform fn_quitar_equipo_evento(current_setting('ayca_test.mant_2_id')::uuid, 'Segundo intento (prueba)');
  exception when others then
    v_fallo := true;
    raise notice '✔ L) OK: doble retiro rechazado — %', sqlerrm;
  end;
  if not v_fallo then raise exception 'TEST FALLIDO (L): se permitió quitar dos veces el mismo equipo.'; end if;
end $$;

-- ── M. Edición de líneas de plantilla: modificar Electricista y Megger
--       (origen='plantilla') a mano — debe fallar en ambas ──
do $$
declare v_fallo boolean := false;
begin
  begin
    perform fn_modificar_personal_manual_evento(current_setting('ayca_test.requerido_electricista_id')::uuid, 99, 'Intento inválido');
  exception when others then
    v_fallo := true;
    raise notice '✔ M-1) OK: edición directa de línea de plantilla (personal) rechazada — %', sqlerrm;
  end;
  if not v_fallo then raise exception 'TEST FALLIDO (M-1): se permitió modificar a mano una línea de personal de origen plantilla.'; end if;

  v_fallo := false;
  begin
    perform fn_modificar_recurso_manual_evento(current_setting('ayca_test.recurso_megger_id')::uuid, 99, 'Intento inválido');
  exception when others then
    v_fallo := true;
    raise notice '✔ M-2) OK: edición directa de línea de plantilla (recursos) rechazada — %', sqlerrm;
  end;
  if not v_fallo then raise exception 'TEST FALLIDO (M-2): se permitió modificar a mano una línea de recursos de origen plantilla.'; end if;
end $$;

-- ── N. Asignaciones inválidas: usuario inexistente ──
do $$
declare v_fallo boolean := false;
begin
  begin
    perform fn_asignar_persona_evento(current_setting('ayca_test.evento_id')::uuid, gen_random_uuid(), 'Electricista');
  exception when others then
    v_fallo := true;
    raise notice '✔ N) OK: asignación con usuario inexistente rechazada — %', sqlerrm;
  end;
  if not v_fallo then raise exception 'TEST FALLIDO (N): se permitió asignar un usuario_id inexistente.'; end if;
end $$;

-- ── O. Accesos RLS no autorizados (requiere el segundo usuario real;
--       "SET LOCAL ROLE" no puede ir dentro de un "do $$") ──
do $$
begin
  if current_setting('ayca_test.tiene_actor_2') <> 'true' then
    raise notice 'AVISO: se omite O (RLS) — no hay un segundo usuario real disponible.';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_2_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_n int;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    -- actor_2 tiene una asignación VIGENTE (extraordinaria, del paso I) -> debe ver el evento.
    select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (O-1): el técnico con asignación vigente no ve el evento.'; end if;
    raise notice '✔ O-1) OK: técnico con asignación vigente ve el evento (RLS real, vía SET ROLE authenticated).';
  end if;
end $$;

-- Liberar también la asignación vigente restante, como el supervisor propietario.
select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';
do $$
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    perform fn_quitar_persona_evento(current_setting('ayca_test.asig_vigente_id')::uuid, 'Prueba 2D.10 — liberar para probar RLS negativo');
  end if;
end $$;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_2_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_n int;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 0 then raise exception 'TEST FALLIDO (O-2): el técnico, ya sin ninguna asignación vigente, todavía ve el evento.'; end if;

    select count(*) into v_n from evento_personal_requerido where evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 0 then raise exception 'TEST FALLIDO (O-2): el técnico sin asignación vigente todavía ve evento_personal_requerido.'; end if;

    raise notice '✔ O-2) OK: sin ninguna asignación vigente, el técnico no ve nada del evento.';
  end if;
end $$;

-- Usuario completamente sin rol ni asignación (identidad sintética).
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid()::text)::text, true);
do $$
declare v_n int;
begin
  select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_n <> 0 then raise exception 'TEST FALLIDO (O-3): un usuario sin rol vio el evento.'; end if;

  raise notice '✔ O-3) OK: usuario sin rol ni asignación no ve nada del evento.';
end $$;

reset role;

do $$
begin
  raise notice '✔ TEST INTEGRAL 2D.10 COMPLETO: setup/consolidación (B,C,D), aprobaciones (E,F), retiro sin perder aprobaciones (G), finalización (H), asignación (I), negativos (J,K,L,M,N) y RLS (O) se comportaron como se esperaba.';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
