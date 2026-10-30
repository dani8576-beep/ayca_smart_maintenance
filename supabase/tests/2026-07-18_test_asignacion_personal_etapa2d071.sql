-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2D.07.1
-- (fn_asignar_persona_evento / fn_quitar_persona_evento /
--  fn_modificar_asignacion_evento)
--
-- Requiere que ya estén ejecutadas todas las migraciones de 2A a
-- 2D.07.1.
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK. Usa un único usuario real (el
-- mismo actor que actúa como supervisor) también como persona asignada
-- — se alterna su perfiles_ayca.activo entre false/true dentro de la
-- transacción para poder probar ambos casos sin depender de que exista
-- un segundo usuario real en la base.
--
-- Escenarios cubiertos:
--   A) Setup: evento, línea de personal requerido, perfil del actor
--      forzado a INACTIVO para el escenario B.
--   B) Negativo: asignar con perfil inactivo.
--   C) Positivo: perfil activado, asignación válida con
--      evento_personal_requerido_id.
--   D) Negativo: usuario inexistente.
--   E) Negativo: evento_personal_requerido_id de OTRO evento.
--   F) Negativo: evento_personal_requerido_id de una línea eliminada.
--   H) Negativo: duplicar al mismo usuario como asignación vigente.
--   I) Negativo: fn_modificar_asignacion_evento intentando poner
--      estado_asignacion = 'liberado'.
--   J) Positivo: fn_modificar_asignacion_evento (confirmado + fechas +
--      observaciones).
--   K) Negativo: cambiar usuario_id mediante UPDATE directo.
--   L) Negativo: DELETE físico.
--   O) Negativo: fn_quitar_persona_evento sin motivo.
--   M) Positivo: fn_quitar_persona_evento con motivo.
--   N) Negativo: volver a quitar la misma asignación (ya liberada).
--   P) Positivo: nueva asignación EXTRAORDINARIA (requerido_id null)
--      reutilizando el mismo usuario, ahora liberado de la anterior.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Setup ──
do $$
declare
  v_actor_id       uuid;
  v_cliente_id     uuid;
  v_faena_id       uuid;
  v_evento_id      uuid;
  v_evento_2_id    uuid;
  v_requerido_id   uuid;
  v_requerido_elim_id uuid;
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

  -- Asegura una fila de perfiles_ayca para el actor, y la deja INACTIVA
  -- a propósito para el escenario B (si ya existía, ej. el admin de
  -- bootstrap, se sobrescribe activo=false solo dentro de esta
  -- transacción de prueba).
  insert into public.perfiles_ayca (id, nombre, activo)
  values (v_actor_id, 'Actor de prueba 2D.07.1', false)
  on conflict (id) do update set activo = false;

  select id into v_evento_id
  from fn_crear_evento_mantencion(
    p_cliente_id => v_cliente_id, p_faena_id => v_faena_id, p_tipo_evento => 'PROGRAMADA',
    p_nombre => 'TEST evento 2D.07.1', p_supervisor_id => v_actor_id
  );

  select id into v_evento_2_id
  from fn_crear_evento_mantencion(
    p_cliente_id => v_cliente_id, p_faena_id => v_faena_id, p_tipo_evento => 'PROGRAMADA',
    p_nombre => 'TEST evento 2D.07.1 — B (otro evento)', p_supervisor_id => v_actor_id
  );

  insert into public.evento_personal_requerido (evento_mantencion_id, perfil, especialidad, cantidad_sugerida, origen, creado_por)
  values (v_evento_id, 'Electricista', 'Media tensión', 2, 'manual', v_actor_id)
  returning id into v_requerido_id;

  insert into public.evento_personal_requerido (evento_mantencion_id, perfil, cantidad_sugerida, origen, estado_fila, motivo_modificacion, creado_por)
  values (v_evento_id, 'Rigger', 1, 'manual', 'eliminado', 'Ya no se requiere (prueba 2D.07.1)', v_actor_id)
  returning id into v_requerido_elim_id;

  raise notice 'Setup completo -> actor=%, evento=%, evento_2=%, requerido=%, requerido_eliminado=%',
    v_actor_id, v_evento_id, v_evento_2_id, v_requerido_id, v_requerido_elim_id;

  perform set_config('ayca_test.actor_id',        v_actor_id::text, true);
  perform set_config('ayca_test.evento_id',       v_evento_id::text, true);
  perform set_config('ayca_test.evento_2_id',     v_evento_2_id::text, true);
  perform set_config('ayca_test.requerido_id',    v_requerido_id::text, true);
  perform set_config('ayca_test.requerido_elim_id', v_requerido_elim_id::text, true);
end $$;

-- ── B. Negativo: asignar con perfil (perfiles_ayca) inactivo ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_asignar_persona_evento(
      current_setting('ayca_test.evento_id')::uuid,
      current_setting('ayca_test.actor_id')::uuid,
      'Electricista',
      p_evento_personal_requerido_id => current_setting('ayca_test.requerido_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ B) OK: asignación rechazada por perfil inactivo — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (B): se permitió asignar a un usuario con perfil inactivo.';
  end if;
end $$;

-- ── C. Positivo: perfil activado, asignación válida ──
do $$
declare
  v_asignacion_id uuid;
  v_estado text;
begin
  update public.perfiles_ayca set activo = true where id = current_setting('ayca_test.actor_id')::uuid;

  v_asignacion_id := fn_asignar_persona_evento(
    current_setting('ayca_test.evento_id')::uuid,
    current_setting('ayca_test.actor_id')::uuid,
    'Electricista',
    p_evento_personal_requerido_id => current_setting('ayca_test.requerido_id')::uuid
  );

  if v_asignacion_id is null then
    raise exception 'TEST FALLIDO (C): fn_asignar_persona_evento() no devolvió un id.';
  end if;

  select estado_asignacion into v_estado from evento_personal_asignado where id = v_asignacion_id;
  if v_estado <> 'propuesto' then
    raise exception 'TEST FALLIDO (C): se esperaba estado_asignacion=propuesto por defecto, es %.', v_estado;
  end if;

  perform set_config('ayca_test.asignacion_id', v_asignacion_id::text, true);
  raise notice '✔ C) OK: asignación creada (id=%), estado_asignacion=propuesto.', v_asignacion_id;
end $$;

-- ── D. Negativo: usuario inexistente ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_asignar_persona_evento(
      current_setting('ayca_test.evento_id')::uuid,
      gen_random_uuid(),
      'Electricista'
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ D) OK: usuario inexistente rechazado — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (D): se permitió asignar un usuario_id inexistente.';
  end if;
end $$;

-- ── E. Negativo: evento_personal_requerido_id de OTRO evento ──
do $$
declare
  v_requerido_otro_evento_id uuid;
  v_fallo boolean := false;
begin
  insert into public.evento_personal_requerido (evento_mantencion_id, perfil, cantidad_sugerida, origen, creado_por)
  values (current_setting('ayca_test.evento_2_id')::uuid, 'Soldador', 1, 'manual', current_setting('ayca_test.actor_id')::uuid)
  returning id into v_requerido_otro_evento_id;

  begin
    perform fn_asignar_persona_evento(
      current_setting('ayca_test.evento_id')::uuid,   -- evento 1 ...
      current_setting('ayca_test.actor_id')::uuid,
      'Soldador',
      p_evento_personal_requerido_id => v_requerido_otro_evento_id  -- ... pero la línea es del evento 2
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ E) OK: línea requerida de otro evento rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (E): se permitió asignar usando una línea requerida de otro evento.';
  end if;
end $$;

-- ── F. Negativo: evento_personal_requerido_id de una línea eliminada ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_asignar_persona_evento(
      current_setting('ayca_test.evento_id')::uuid,
      current_setting('ayca_test.actor_id')::uuid,
      'Rigger',
      p_evento_personal_requerido_id => current_setting('ayca_test.requerido_elim_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ F) OK: línea eliminada rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (F): se permitió asignar contra una línea de personal requerido eliminada.';
  end if;
end $$;

-- ── H. Negativo: duplicar al mismo usuario como asignación vigente ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_asignar_persona_evento(
      current_setting('ayca_test.evento_id')::uuid,
      current_setting('ayca_test.actor_id')::uuid,
      'Electricista'
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ H) OK: asignación duplicada del mismo usuario rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (H): se permitió una segunda asignación vigente del mismo usuario en el mismo evento.';
  end if;
end $$;

-- ── I. Negativo: fn_modificar_asignacion_evento intentando poner 'liberado' ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_modificar_asignacion_evento(
      current_setting('ayca_test.asignacion_id')::uuid,
      p_estado_asignacion => 'liberado'
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ I) OK: intento de liberar vía modificar rechazado — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (I): se permitió poner estado_asignacion=liberado a través de fn_modificar_asignacion_evento().';
  end if;
end $$;

-- ── J. Positivo: fn_modificar_asignacion_evento (confirmado + fechas + observaciones) ──
do $$
declare
  v_estado text;
  v_obs    text;
begin
  perform fn_modificar_asignacion_evento(
    current_setting('ayca_test.asignacion_id')::uuid,
    p_estado_asignacion => 'confirmado',
    p_fecha_desde => now(),
    p_fecha_hasta => now() + interval '10 days',
    p_observaciones => 'Confirmado para la parada (prueba 2D.07.1)'
  );

  select estado_asignacion, observaciones into v_estado, v_obs
    from evento_personal_asignado where id = current_setting('ayca_test.asignacion_id')::uuid;

  if v_estado <> 'confirmado' then
    raise exception 'TEST FALLIDO (J): se esperaba estado_asignacion=confirmado, es %.', v_estado;
  end if;
  if v_obs is null or v_obs not ilike '%Confirmado para la parada%' then
    raise exception 'TEST FALLIDO (J): las observaciones no se actualizaron como se esperaba.';
  end if;

  raise notice '✔ J) OK: asignación modificada — estado_asignacion=confirmado, fechas y observaciones actualizadas.';
end $$;

-- ── K. Negativo: cambiar usuario_id mediante UPDATE directo ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    update public.evento_personal_asignado
      set usuario_id = gen_random_uuid()
      where id = current_setting('ayca_test.asignacion_id')::uuid;
  exception when others then
    v_fallo := true;
    raise notice '✔ K) OK: cambio de usuario_id rechazado — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (K): se permitió cambiar usuario_id de una asignación existente.';
  end if;
end $$;

-- ── L. Negativo: DELETE físico ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    delete from public.evento_personal_asignado
      where id = current_setting('ayca_test.asignacion_id')::uuid;
  exception when others then
    v_fallo := true;
    raise notice '✔ L) OK: DELETE físico rechazado — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (L): se permitió eliminar físicamente una asignación.';
  end if;
end $$;

-- ── O. Negativo: fn_quitar_persona_evento sin motivo ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_quitar_persona_evento(current_setting('ayca_test.asignacion_id')::uuid, '   ');
  exception when others then
    v_fallo := true;
    raise notice '✔ O) OK: liberación sin motivo rechazada — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (O): se permitió liberar una asignación sin motivo.';
  end if;
end $$;

-- ── M. Positivo: fn_quitar_persona_evento con motivo ──
do $$
declare
  v_estado text;
  v_fecha_hasta timestamptz;
  v_obs text;
begin
  perform fn_quitar_persona_evento(current_setting('ayca_test.asignacion_id')::uuid, 'Persona reasignada a otra faena (prueba 2D.07.1)');

  select estado_asignacion, fecha_hasta, observaciones
    into v_estado, v_fecha_hasta, v_obs
    from evento_personal_asignado where id = current_setting('ayca_test.asignacion_id')::uuid;

  if v_estado <> 'liberado' then
    raise exception 'TEST FALLIDO (M): se esperaba estado_asignacion=liberado, es %.', v_estado;
  end if;
  if v_fecha_hasta is null then
    raise exception 'TEST FALLIDO (M): se esperaba que fecha_hasta quedara fijada al liberar.';
  end if;
  if v_obs not ilike '%Retirado: Persona reasignada%' then
    raise exception 'TEST FALLIDO (M): el motivo de retiro no quedó registrado en observaciones.';
  end if;

  raise notice '✔ M) OK: asignación liberada — estado_asignacion=liberado, fecha_hasta y motivo registrados.';
end $$;

-- ── N. Negativo: volver a quitar la misma asignación (ya liberada) ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    perform fn_quitar_persona_evento(current_setting('ayca_test.asignacion_id')::uuid, 'Segundo intento (prueba)');
  exception when others then
    v_fallo := true;
    raise notice '✔ N) OK: no se permitió liberar dos veces la misma asignación — %', sqlerrm;
  end;
  if not v_fallo then
    raise exception 'TEST FALLIDO (N): se permitió liberar dos veces la misma asignación.';
  end if;
end $$;

-- ── P. Positivo: nueva asignación EXTRAORDINARIA (requerido_id null),
--       reutilizando el mismo usuario ya liberado de la anterior ──
do $$
declare
  v_asignacion_2_id uuid;
begin
  v_asignacion_2_id := fn_asignar_persona_evento(
    current_setting('ayca_test.evento_id')::uuid,
    current_setting('ayca_test.actor_id')::uuid,
    'Supervisor de apoyo'
  );

  if v_asignacion_2_id is null then
    raise exception 'TEST FALLIDO (P): no se pudo crear una asignación extraordinaria tras liberar la anterior.';
  end if;

  raise notice '✔ P) OK: asignación extraordinaria (sin línea de personal requerido) creada tras liberar la anterior (id=%).', v_asignacion_2_id;
end $$;

do $$
begin
  raise notice '✔ TEST 2D.07.1 COMPLETO: positivos (C, J, M, P) y negativos (B, D, E, F, H, I, K, L, N, O) se comportaron como se esperaba.';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
