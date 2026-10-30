-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2D.03
-- (evento_personal_requerido / evento_personal_asignado)
--
-- Requiere que ya estén ejecutadas: perfiles_roles.sql,
-- mantenciones_etapa2a5.sql, mantenciones_etapa2d_01_eventos_numeracion.sql,
-- mantenciones_etapa2d_03_personal.sql.
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK. Usa cliente/faena REALES
-- (CODELCO → Andina, cargados por 2C.5) para dos eventos de prueba, y
-- un usuario real existente (cualquier supervisor/administrador) como
-- persona asignada.
--
-- Escenarios cubiertos:
--   A) Setup: 2 eventos de prueba (A y B).
--   B) Positivo: línea de personal requerido en A + asignación real
--      vinculada a esa línea.
--   C) Negativo: cantidad_sugerida negativa — CHECK.
--   D) Negativo: cantidad_aprobada negativa — CHECK.
--   E) Negativo: fecha_hasta anterior a fecha_desde — CHECK.
--   F) Negativo: asignación en evento A que referencia una línea
--      requerida del evento B — debe fallar (eventos distintos).
--   G) Negativo: asignación que referencia una línea ya eliminada.
--   H) Negativo: mismo usuario con dos asignaciones activas en el mismo
--      evento — índice único parcial.
--   I) Positivo: liberar la asignación anterior permite crear una nueva
--      asignación activa para el mismo usuario en el mismo evento.
--   J) Negativo: marcar una línea requerida como 'eliminado' sin
--      motivo_modificacion — CHECK.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Setup: actor real y dos eventos de prueba ──
do $$
declare
  v_actor_id      uuid;
  v_cliente_id    uuid;
  v_faena_id      uuid;
  v_evento_a_id   uuid;
  v_evento_b_id   uuid;
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
  if v_cliente_id is null or v_faena_id is null then
    raise exception 'TEST ABORTADO: no se encontró CODELCO → Andina.';
  end if;

  insert into public.eventos_mantencion (numero, cliente_id, faena_id, tipo_evento, nombre, supervisor_id, creado_por)
  values (fn_generar_numero_evento_mantencion(), v_cliente_id, v_faena_id, 'PROGRAMADA', 'TEST evento A 2D.03', v_actor_id, v_actor_id)
  returning id into v_evento_a_id;

  insert into public.eventos_mantencion (numero, cliente_id, faena_id, tipo_evento, nombre, supervisor_id, creado_por)
  values (fn_generar_numero_evento_mantencion(), v_cliente_id, v_faena_id, 'PROGRAMADA', 'TEST evento B 2D.03', v_actor_id, v_actor_id)
  returning id into v_evento_b_id;

  raise notice 'Setup completo -> actor=%, evento_a=%, evento_b=%', v_actor_id, v_evento_a_id, v_evento_b_id;

  perform set_config('ayca_test.actor_id',    v_actor_id::text, true);
  perform set_config('ayca_test.evento_a_id', v_evento_a_id::text, true);
  perform set_config('ayca_test.evento_b_id', v_evento_b_id::text, true);
end $$;

-- ── B. Positivo: línea de personal requerido + asignación real vinculada ──
do $$
declare
  v_requerido_id uuid;
  v_asignado_id  uuid;
begin
  insert into public.evento_personal_requerido (
    evento_mantencion_id, perfil, especialidad, cantidad_sugerida, origen, creado_por
  ) values (
    current_setting('ayca_test.evento_a_id')::uuid, 'Electricista', 'Media tensión', 3, 'plantilla',
    current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_requerido_id;

  insert into public.evento_personal_asignado (
    evento_mantencion_id, evento_personal_requerido_id, usuario_id, perfil, especialidad,
    fecha_desde, fecha_hasta, creado_por
  ) values (
    current_setting('ayca_test.evento_a_id')::uuid, v_requerido_id,
    current_setting('ayca_test.actor_id')::uuid, 'Electricista', 'Media tensión',
    now(), now() + interval '5 days', current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_asignado_id;

  perform set_config('ayca_test.requerido_a_id', v_requerido_id::text, true);
  perform set_config('ayca_test.asignado_1_id',  v_asignado_id::text, true);
  raise notice '✔ B) OK: requerido=% y asignado=% creados y vinculados.', v_requerido_id, v_asignado_id;
end $$;

-- ── C. Negativo: cantidad_sugerida negativa ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_requerido (
      evento_mantencion_id, perfil, cantidad_sugerida, origen, creado_por
    ) values (
      current_setting('ayca_test.evento_a_id')::uuid, 'Rigger', -1, 'manual',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ C) OK: cantidad_sugerida negativa rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (C): se permitió cantidad_sugerida negativa.';
  end if;
end $$;

-- ── D. Negativo: cantidad_aprobada negativa ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_requerido (
      evento_mantencion_id, perfil, cantidad_sugerida, cantidad_aprobada, origen, creado_por
    ) values (
      current_setting('ayca_test.evento_a_id')::uuid, 'Rigger', 2, -1, 'manual',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ D) OK: cantidad_aprobada negativa rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (D): se permitió cantidad_aprobada negativa.';
  end if;
end $$;

-- ── E. Negativo: fecha_hasta anterior a fecha_desde ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_asignado (
      evento_mantencion_id, usuario_id, perfil, fecha_desde, fecha_hasta, creado_por
    ) values (
      current_setting('ayca_test.evento_a_id')::uuid, current_setting('ayca_test.actor_id')::uuid,
      'Rigger', now(), now() - interval '1 day', current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ E) OK: fecha_hasta anterior a fecha_desde rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (E): se permitió fecha_hasta anterior a fecha_desde.';
  end if;
end $$;

-- ── F. Negativo: asignación en el evento A que referencia una línea
--       requerida del evento B ──
do $$
declare
  v_requerido_b_id uuid;
  v_fallo          boolean := false;
begin
  insert into public.evento_personal_requerido (
    evento_mantencion_id, perfil, cantidad_sugerida, origen, creado_por
  ) values (
    current_setting('ayca_test.evento_b_id')::uuid, 'Soldador', 1, 'manual',
    current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_requerido_b_id;

  begin
    insert into public.evento_personal_asignado (
      evento_mantencion_id, evento_personal_requerido_id, usuario_id, perfil, creado_por
    ) values (
      current_setting('ayca_test.evento_a_id')::uuid,  -- evento A ...
      v_requerido_b_id,                                 -- ... pero la línea requerida es del evento B
      current_setting('ayca_test.actor_id')::uuid, 'Soldador',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ F) OK: asignación cruzada entre eventos rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (F): se permitió asignar personal de un evento usando una línea requerida de otro evento.';
  end if;
end $$;

-- ── G. Negativo: asignación que referencia una línea ya eliminada ──
do $$
declare
  v_requerido_elim_id uuid;
  v_fallo             boolean := false;
begin
  insert into public.evento_personal_requerido (
    evento_mantencion_id, perfil, cantidad_sugerida, origen, estado_fila, motivo_modificacion, creado_por
  ) values (
    current_setting('ayca_test.evento_a_id')::uuid, 'Andamiero', 1, 'manual', 'eliminado',
    'Ya no se requiere para esta parada (prueba)', current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_requerido_elim_id;

  begin
    insert into public.evento_personal_asignado (
      evento_mantencion_id, evento_personal_requerido_id, usuario_id, perfil, creado_por
    ) values (
      current_setting('ayca_test.evento_a_id')::uuid, v_requerido_elim_id,
      current_setting('ayca_test.actor_id')::uuid, 'Andamiero',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ G) OK: asignación contra línea eliminada rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (G): se permitió asignar personal a una línea de requerimiento eliminada.';
  end if;
end $$;

-- ── H. Negativo: mismo usuario con dos asignaciones activas en el mismo
--       evento (índice único parcial) ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_asignado (
      evento_mantencion_id, usuario_id, perfil, estado_asignacion, creado_por
    ) values (
      current_setting('ayca_test.evento_a_id')::uuid, current_setting('ayca_test.actor_id')::uuid,
      'Electricista', 'confirmado', current_setting('ayca_test.actor_id')::uuid
    );
  exception when unique_violation then
    v_fallo := true;
    raise notice '✔ H) OK: segunda asignación activa del mismo usuario en el mismo evento rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (H): se permitió una segunda asignación activa del mismo usuario en el mismo evento.';
  end if;
end $$;

-- ── I. Positivo: liberar la asignación original permite una nueva
--       asignación activa para el mismo usuario en el mismo evento ──
do $$
declare
  v_asignado_2_id uuid;
begin
  update public.evento_personal_asignado
    set estado_asignacion = 'liberado'
    where id = current_setting('ayca_test.asignado_1_id')::uuid;

  raise notice '✔ I1) OK: asignación original liberada.';

  insert into public.evento_personal_asignado (
    evento_mantencion_id, usuario_id, perfil, estado_asignacion, creado_por
  ) values (
    current_setting('ayca_test.evento_a_id')::uuid, current_setting('ayca_test.actor_id')::uuid,
    'Electricista', 'propuesto', current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_asignado_2_id;

  if v_asignado_2_id is null then
    raise exception 'TEST FALLIDO (I2): no se pudo crear una nueva asignación activa tras liberar la anterior.';
  end if;
  raise notice '✔ I2) OK: nueva asignación activa creada tras liberar la anterior (id=%).', v_asignado_2_id;
end $$;

-- ── J. Negativo: marcar una línea requerida como 'eliminado' sin
--       motivo_modificacion ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_personal_requerido (
      evento_mantencion_id, perfil, cantidad_sugerida, origen, estado_fila, creado_por
    ) values (
      current_setting('ayca_test.evento_a_id')::uuid, 'Soldador', 1, 'manual', 'eliminado',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ J) OK: línea eliminada sin motivo_modificacion rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (J): se permitió marcar una línea como eliminada sin motivo_modificacion.';
  end if;
end $$;

do $$
begin
  raise notice '✔ TEST 2D.03 COMPLETO: positivos (B, I) y negativos (C, D, E, F, G, H, J) se comportaron como se esperaba.';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
