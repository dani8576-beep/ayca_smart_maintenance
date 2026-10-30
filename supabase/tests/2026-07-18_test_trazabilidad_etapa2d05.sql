-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2D.05
-- (evento_personal_origen / evento_recursos_origen)
--
-- Requiere que ya estén ejecutadas: perfiles_roles.sql,
-- mantenciones_etapa2a.sql, mantenciones_etapa2a5.sql (+ tag_equipos),
-- mantenciones_etapa2b.sql, mantenciones_etapa2c4/2c5,
-- mantenciones_etapa2d_01_eventos_numeracion.sql,
-- mantenciones_etapa2d_02_relacion_evento.sql,
-- mantenciones_etapa2d_03_personal.sql,
-- mantenciones_etapa2d_04_recursos.sql,
-- mantenciones_etapa2d_05_trazabilidad.sql.
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK. Como fn_crear_evento_mantencion() y
-- fn_agregar_equipo_evento() todavía no existen (2D-06), este test
-- inserta directo en eventos_mantencion/mantenciones/evento_personal_
-- requerido/evento_recursos, igual que los tests de 2D-02/03/04.
--
-- Escenarios cubiertos (personal):
--   B) Positivo: fila de origen válida (mantención → línea requerida,
--      con su propia fila de plantilla_personal).
--   C) Negativo: cantidad_aportada <= 0.
--   E) Negativo: línea requerida de OTRO evento que el de la mantención.
--   F) Negativo: fila de plantilla_personal que no pertenece a la
--      plantilla real de la mantención.
--   G) Negativo: duplicado activo de la misma combinación.
--   H) Positivo: retirar y volver a crear una fila nueva (reincorporación).
--   I) Negativo: reactivar una fila retirada (retirado → activo).
--   J) Negativo: modificar cantidad_aportada de una fila ya creada.
--   K) Negativo: DELETE físico.
--   L) Negativo: estado/campos de retiro inconsistentes (CHECK).
--
-- Escenarios cubiertos (recursos, versión abreviada — misma lógica):
--   M) Positivo, N) evento cruzado, O) plantilla cruzada,
--   P) duplicado activo, Q) reactivar retirado, R) DELETE físico.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Setup ──
do $$
declare
  v_actor_id        uuid;
  v_cliente_id      uuid;
  v_faena_id        uuid;
  v_area_id         uuid;
  v_tipo_mant_id    uuid;
  v_version_test    int;
  v_plantilla_id    uuid;
  v_plantilla_otra_id uuid;
  v_pp_id           uuid;
  v_pp_otra_id      uuid;
  v_prec_id         uuid;
  v_prec_otra_id    uuid;
  v_equipo_id       uuid;
  v_evento_a_id     uuid;
  v_evento_b_id     uuid;
  v_mant_id         uuid;
  v_requerido_a_id  uuid;
  v_requerido_b_id  uuid;
  v_recurso_a_id    uuid;
  v_recurso_b_id    uuid;
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
  if v_tipo_mant_id is null then
    raise exception 'TEST ABORTADO: no se encontró el tipo de mantención MANTENCION_MENSUAL.';
  end if;

  -- Equipo de prueba temporal.
  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_id, 'TEST-EQ-2D05', 'TEST-TAG-2D05', 'Equipo de prueba 2D.05', 'Motor eléctrico', true)
  returning id into v_equipo_id;

  -- Dos plantillas de prueba temporales (misma técnica que tests previos).
  update public.plantillas_mantencion set activa = false
    where tipo_mantencion_id = v_tipo_mant_id and activa = true;

  select coalesce(max(version), 0) + 1000 into v_version_test
    from public.plantillas_mantencion where tipo_mantencion_id = v_tipo_mant_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test, 'TEST_PRINCIPAL_2D05', true)
  returning id into v_plantilla_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test + 1, 'TEST_OTRA_2D05', false)
  returning id into v_plantilla_otra_id;

  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_id, 'Electricista', 2, 'Media tensión', true)
  returning id into v_pp_id;

  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_otra_id, 'Electricista', 1, 'Media tensión', true)
  returning id into v_pp_otra_id;

  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_id, 'herramienta', 'Megger 5kV (plantilla)', 1, false)
  returning id into v_prec_id;

  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_otra_id, 'herramienta', 'Megger 5kV (otra plantilla)', 1, false)
  returning id into v_prec_otra_id;

  -- Dos eventos de prueba (A: el real; B: solo para probar el cruce entre eventos).
  insert into public.eventos_mantencion (numero, cliente_id, faena_id, tipo_evento, nombre, supervisor_id, creado_por)
  values (fn_generar_numero_evento_mantencion(), v_cliente_id, v_faena_id, 'PROGRAMADA', 'TEST evento A 2D.05', v_actor_id, v_actor_id)
  returning id into v_evento_a_id;

  insert into public.eventos_mantencion (numero, cliente_id, faena_id, tipo_evento, nombre, supervisor_id, creado_por)
  values (fn_generar_numero_evento_mantencion(), v_cliente_id, v_faena_id, 'PROGRAMADA', 'TEST evento B 2D.05', v_actor_id, v_actor_id)
  returning id into v_evento_b_id;

  -- Mantención del equipo de prueba, dentro del evento A, usando la
  -- plantilla PRINCIPAL (inserción directa — fn_crear_mantencion() aún
  -- no acepta evento_mantencion_id, eso llega en 2D-06).
  insert into public.mantenciones (
    numero, cliente_id, faena_id, area_id, equipo_id,
    tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
    evento_mantencion_id, supervisor_id, creado_por
  ) values (
    fn_generar_numero_mantencion(), v_cliente_id, v_faena_id, v_area_id, v_equipo_id,
    v_tipo_mant_id, v_plantilla_id, 'TEST_PRINCIPAL_2D05', v_version_test,
    v_evento_a_id, v_actor_id, v_actor_id
  )
  returning id into v_mant_id;

  -- Líneas consolidadas en cada evento.
  insert into public.evento_personal_requerido (evento_mantencion_id, perfil, especialidad, cantidad_sugerida, origen, creado_por)
  values (v_evento_a_id, 'Electricista', 'Media tensión', 0, 'plantilla', v_actor_id)
  returning id into v_requerido_a_id;

  insert into public.evento_personal_requerido (evento_mantencion_id, perfil, especialidad, cantidad_sugerida, origen, creado_por)
  values (v_evento_b_id, 'Electricista', 'Media tensión', 0, 'plantilla', v_actor_id)
  returning id into v_requerido_b_id;

  insert into public.evento_recursos (evento_mantencion_id, categoria_recurso, nombre_generico, cantidad_sugerida, origen, creado_por)
  values (v_evento_a_id, 'herramienta', 'Megger 5kV', 0, 'plantilla', v_actor_id)
  returning id into v_recurso_a_id;

  insert into public.evento_recursos (evento_mantencion_id, categoria_recurso, nombre_generico, cantidad_sugerida, origen, creado_por)
  values (v_evento_b_id, 'herramienta', 'Megger 5kV', 0, 'plantilla', v_actor_id)
  returning id into v_recurso_b_id;

  raise notice 'Setup completo -> actor=%, evento_a=%, evento_b=%, mantencion=%, plantilla_principal=%, plantilla_otra=%',
    v_actor_id, v_evento_a_id, v_evento_b_id, v_mant_id, v_plantilla_id, v_plantilla_otra_id;

  perform set_config('ayca_test.actor_id',       v_actor_id::text, true);
  perform set_config('ayca_test.mant_id',        v_mant_id::text, true);
  perform set_config('ayca_test.requerido_a_id', v_requerido_a_id::text, true);
  perform set_config('ayca_test.requerido_b_id', v_requerido_b_id::text, true);
  perform set_config('ayca_test.recurso_a_id',   v_recurso_a_id::text, true);
  perform set_config('ayca_test.recurso_b_id',   v_recurso_b_id::text, true);
  perform set_config('ayca_test.pp_id',          v_pp_id::text, true);
  perform set_config('ayca_test.pp_otra_id',     v_pp_otra_id::text, true);
  perform set_config('ayca_test.prec_id',        v_prec_id::text, true);
  perform set_config('ayca_test.prec_otra_id',   v_prec_otra_id::text, true);
end $$;

-- ══════════════ PERSONAL ══════════════

-- ── B. Positivo: fila de origen válida ──
do $$
declare
  v_origen_id uuid;
begin
  insert into public.evento_personal_origen (
    evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
  ) values (
    current_setting('ayca_test.requerido_a_id')::uuid,
    current_setting('ayca_test.mant_id')::uuid,
    current_setting('ayca_test.pp_id')::uuid,
    2, current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_origen_id;

  perform set_config('ayca_test.origen_personal_id', v_origen_id::text, true);
  raise notice '✔ B) OK: fila de evento_personal_origen creada (id=%).', v_origen_id;
end $$;

-- ── C. Negativo: cantidad_aportada <= 0 ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_origen (
      evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
    ) values (
      current_setting('ayca_test.requerido_a_id')::uuid,
      current_setting('ayca_test.mant_id')::uuid,
      current_setting('ayca_test.pp_id')::uuid,
      0, current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ C) OK: cantidad_aportada <= 0 rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (C): se permitió cantidad_aportada <= 0.';
  end if;
end $$;

-- ── E. Negativo: línea requerida de OTRO evento que el de la mantención ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_origen (
      evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
    ) values (
      current_setting('ayca_test.requerido_b_id')::uuid,  -- evento B ...
      current_setting('ayca_test.mant_id')::uuid,         -- ... pero la mantención es del evento A
      current_setting('ayca_test.pp_id')::uuid,
      1, current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ E) OK: línea requerida de otro evento rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (E): se permitió una fila de origen cruzando eventos distintos.';
  end if;
end $$;

-- ── F. Negativo: fila de plantilla_personal que no pertenece a la
--       plantilla real de la mantención ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_origen (
      evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
    ) values (
      current_setting('ayca_test.requerido_a_id')::uuid,
      current_setting('ayca_test.mant_id')::uuid,
      current_setting('ayca_test.pp_otra_id')::uuid,   -- pertenece a la OTRA plantilla
      1, current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ F) OK: fila de plantilla_personal ajena rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (F): se permitió una fila de plantilla_personal que no corresponde a la plantilla de la mantención.';
  end if;
end $$;

-- ── G. Negativo: duplicado activo de la misma combinación ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_origen (
      evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
    ) values (
      current_setting('ayca_test.requerido_a_id')::uuid,
      current_setting('ayca_test.mant_id')::uuid,
      current_setting('ayca_test.pp_id')::uuid,
      1, current_setting('ayca_test.actor_id')::uuid
    );
  exception when unique_violation then
    v_fallo := true;
    raise notice '✔ G) OK: duplicado activo rechazado por el índice único — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (G): se permitió un duplicado activo de la misma combinación.';
  end if;
end $$;

-- ── H. Positivo: retirar y volver a crear una fila nueva (reincorporación) ──
do $$
declare
  v_origen_2_id uuid;
begin
  update public.evento_personal_origen
    set estado = 'retirado', retirado_por = current_setting('ayca_test.actor_id')::uuid,
        retirado_en = now(), motivo_retiro = 'Equipo retirado del evento (prueba 2D.05)'
    where id = current_setting('ayca_test.origen_personal_id')::uuid;

  raise notice '✔ H1) OK: fila de origen original retirada.';

  insert into public.evento_personal_origen (
    evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
  ) values (
    current_setting('ayca_test.requerido_a_id')::uuid,
    current_setting('ayca_test.mant_id')::uuid,
    current_setting('ayca_test.pp_id')::uuid,
    2, current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_origen_2_id;

  if v_origen_2_id is null then
    raise exception 'TEST FALLIDO (H2): no se pudo crear una nueva fila de origen tras retirar la anterior.';
  end if;
  perform set_config('ayca_test.origen_personal_2_id', v_origen_2_id::text, true);
  raise notice '✔ H2) OK: nueva fila de origen creada tras el retiro (id=%).', v_origen_2_id;
end $$;

-- ── I. Negativo: reactivar una fila retirada (retirado → activo) ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    update public.evento_personal_origen
      set estado = 'activo', retirado_por = null, retirado_en = null, motivo_retiro = null
      where id = current_setting('ayca_test.origen_personal_id')::uuid;
  exception when others then
    v_fallo := true;
    raise notice '✔ I) OK: reactivación de fila retirada rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (I): se permitió reactivar una fila de origen retirada.';
  end if;
end $$;

-- ── J. Negativo: modificar cantidad_aportada de una fila ya creada ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    update public.evento_personal_origen
      set cantidad_aportada = 99
      where id = current_setting('ayca_test.origen_personal_2_id')::uuid;
  exception when others then
    v_fallo := true;
    raise notice '✔ J) OK: cambio de cantidad_aportada rechazado — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (J): se permitió modificar cantidad_aportada de una fila ya creada.';
  end if;
end $$;

-- ── K. Negativo: DELETE físico ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    delete from public.evento_personal_origen
      where id = current_setting('ayca_test.origen_personal_2_id')::uuid;
  exception when others then
    v_fallo := true;
    raise notice '✔ K) OK: DELETE físico rechazado — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (K): se permitió eliminar físicamente una fila de evento_personal_origen.';
  end if;
end $$;

-- ── L. Negativo: estado 'retirado' sin motivo_retiro (CHECK) ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_origen (
      evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada,
      estado, retirado_por, retirado_en, creado_por
    ) values (
      current_setting('ayca_test.requerido_a_id')::uuid,
      current_setting('ayca_test.mant_id')::uuid,
      current_setting('ayca_test.pp_id')::uuid,
      1, 'retirado', current_setting('ayca_test.actor_id')::uuid, now(),
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ L) OK: estado retirado sin motivo_retiro rechazado — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (L): se permitió estado retirado sin motivo_retiro.';
  end if;
end $$;

-- ══════════════ RECURSOS (versión abreviada, misma lógica) ══════════════

-- ── M. Positivo ──
do $$
declare
  v_origen_id uuid;
begin
  insert into public.evento_recursos_origen (
    evento_recursos_id, mantencion_id, plantilla_recurso_id, cantidad_aportada, creado_por
  ) values (
    current_setting('ayca_test.recurso_a_id')::uuid,
    current_setting('ayca_test.mant_id')::uuid,
    current_setting('ayca_test.prec_id')::uuid,
    1, current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_origen_id;

  perform set_config('ayca_test.origen_recurso_id', v_origen_id::text, true);
  raise notice '✔ M) OK: fila de evento_recursos_origen creada (id=%).', v_origen_id;
end $$;

-- ── N. Negativo: línea de recursos de OTRO evento ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_recursos_origen (
      evento_recursos_id, mantencion_id, plantilla_recurso_id, cantidad_aportada, creado_por
    ) values (
      current_setting('ayca_test.recurso_b_id')::uuid,
      current_setting('ayca_test.mant_id')::uuid,
      current_setting('ayca_test.prec_id')::uuid,
      1, current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ N) OK: línea de recursos de otro evento rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (N): se permitió una fila de origen de recursos cruzando eventos distintos.';
  end if;
end $$;

-- ── O. Negativo: fila de plantilla_recursos ajena a la plantilla de la mantención ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_recursos_origen (
      evento_recursos_id, mantencion_id, plantilla_recurso_id, cantidad_aportada, creado_por
    ) values (
      current_setting('ayca_test.recurso_a_id')::uuid,
      current_setting('ayca_test.mant_id')::uuid,
      current_setting('ayca_test.prec_otra_id')::uuid,
      1, current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ O) OK: fila de plantilla_recursos ajena rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (O): se permitió una fila de plantilla_recursos que no corresponde a la plantilla de la mantención.';
  end if;
end $$;

-- ── P. Negativo: duplicado activo ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_recursos_origen (
      evento_recursos_id, mantencion_id, plantilla_recurso_id, cantidad_aportada, creado_por
    ) values (
      current_setting('ayca_test.recurso_a_id')::uuid,
      current_setting('ayca_test.mant_id')::uuid,
      current_setting('ayca_test.prec_id')::uuid,
      1, current_setting('ayca_test.actor_id')::uuid
    );
  exception when unique_violation then
    v_fallo := true;
    raise notice '✔ P) OK: duplicado activo rechazado por el índice único — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (P): se permitió un duplicado activo de la misma combinación de recursos.';
  end if;
end $$;

-- ── Q. Negativo: reactivar retirado → activo ──
do $$
declare
  v_fallo boolean := false;
begin
  update public.evento_recursos_origen
    set estado = 'retirado', retirado_por = current_setting('ayca_test.actor_id')::uuid,
        retirado_en = now(), motivo_retiro = 'Prueba 2D.05'
    where id = current_setting('ayca_test.origen_recurso_id')::uuid;

  begin
    update public.evento_recursos_origen
      set estado = 'activo', retirado_por = null, retirado_en = null, motivo_retiro = null
      where id = current_setting('ayca_test.origen_recurso_id')::uuid;
  exception when others then
    v_fallo := true;
    raise notice '✔ Q) OK: reactivación de fila retirada rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (Q): se permitió reactivar una fila de origen de recursos retirada.';
  end if;
end $$;

-- ── R. Negativo: DELETE físico ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    delete from public.evento_recursos_origen
      where id = current_setting('ayca_test.origen_recurso_id')::uuid;
  exception when others then
    v_fallo := true;
    raise notice '✔ R) OK: DELETE físico rechazado — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (R): se permitió eliminar físicamente una fila de evento_recursos_origen.';
  end if;
end $$;

do $$
begin
  raise notice '✔ TEST 2D.05 COMPLETO: personal (B, H positivos; C, E, F, G, I, J, K, L negativos) y recursos (M positivo; N, O, P, Q, R negativos) se comportaron como se esperaba.';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
