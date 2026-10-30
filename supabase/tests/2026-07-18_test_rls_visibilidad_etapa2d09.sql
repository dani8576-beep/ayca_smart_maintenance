-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2D.09
-- (RLS y visibilidad por rol — 9 tablas de 2D)
--
-- Requiere que ya estén ejecutadas todas las migraciones de 2A a 2D.09.
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK.
--
-- ── POR QUÉ ESTE TEST HACE "SET LOCAL ROLE authenticated" ──
-- Todos los tests anteriores (2D-02 a 2D-08) corren con el rol de
-- conexión por defecto (dueño de las tablas / superusuario), que
-- POSTGRES IGNORA COMPLETAMENTE para efectos de RLS — cambiar
-- auth.uid() vía request.jwt.claims no alcanza para probar políticas si
-- quien consulta es el dueño de la tabla. Por eso, y solo en este
-- archivo, se hace "SET LOCAL ROLE authenticated" (rol real de Supabase,
-- el mismo que usa PostgREST) — desde ahí en adelante, TODAS las
-- consultas quedan sujetas a RLS de verdad, y solo cambia qué usuario se
-- simula (vía request.jwt.claims) entre una prueba y otra.
--
-- IMPORTANTE: "SET ROLE"/"RESET ROLE" son comandos de sesión — no se
-- pueden ejecutar dentro de un bloque "do $$ ... $$" (PL/pgSQL no los
-- reconoce como sentencia embebible). Por eso aparecen SIEMPRE como
-- sentencias sueltas a nivel de script, nunca dentro de un "do $$".
--
-- ── USUARIOS REALES NECESARIOS ──
-- Se necesita al menos 1 administrador real (usuario_roles) — aborta si
-- no existe. Se busca además un segundo usuario real cualquiera de
-- auth.users (v_actor_2_id) para poder probar "supervisor ajeno" y los
-- 3 estados de técnico de forma limpia (una identidad que NO es
-- supervisor del evento de prueba). Si no existe un segundo usuario, esos
-- escenarios se OMITEN con un aviso explícito (RAISE NOTICE) en vez de
-- fallar — degradar el resultado en silencio sería peor que avisarlo.
--
-- Escenarios cubiertos: administrador, supervisor propietario, supervisor
-- ajeno, técnico no asignado / asignado / liberado, planificador, bodega,
-- gerencia, usuario sin rol.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Resolver usuarios reales (rol de conexión por defecto — antes
--       de cambiar a "authenticated" hace falta poder leer usuario_roles
--       sin las restricciones de su propia RLS) ──
do $$
declare
  v_admin_id   uuid;
  v_actor_id   uuid;
  v_actor_2_id uuid;
begin
  select ur.usuario_id into v_admin_id from public.usuario_roles ur where ur.rol = 'administrador' limit 1;
  if v_admin_id is null then
    raise exception 'TEST ABORTADO: se necesita al menos un usuario con rol administrador.';
  end if;

  select ur.usuario_id into v_actor_id from public.usuario_roles ur where ur.rol = 'supervisor' limit 1;
  if v_actor_id is null then
    v_actor_id := v_admin_id;
    raise notice 'AVISO: no hay un usuario con rol supervisor separado del administrador — se usa el administrador también como "supervisor propietario" de prueba.';
  end if;

  select u.id into v_actor_2_id from auth.users u where u.id <> v_actor_id and u.id <> v_admin_id limit 1;
  if v_actor_2_id is null then
    raise notice 'AVISO: no se encontró un segundo usuario real distinto — se OMITEN los escenarios "supervisor ajeno" y "técnico" (F, G, H) y los de rol único (I, J, K).';
  end if;

  perform set_config('ayca_test.admin_id',      v_admin_id::text, true);
  perform set_config('ayca_test.actor_id',      v_actor_id::text, true);
  perform set_config('ayca_test.actor_2_id',    coalesce(v_actor_2_id::text, ''), true);
  perform set_config('ayca_test.tiene_actor_2', (v_actor_2_id is not null)::text, true);
end $$;

-- ── Cambiar al rol real "authenticated" — desde aquí, RLS se aplica de
--    verdad. Se impersona como el administrador para el setup (algunas
--    tablas de catálogo exigen es_admin() en su propia policy de INSERT). ──
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.admin_id'))::text, true);

-- ── B. Setup de datos de prueba (impersonando al administrador) ──
do $$
declare
  v_cliente_id     uuid;
  v_faena_id       uuid;
  v_area_id        uuid;
  v_tipo_mant_id   uuid;
  v_plantilla_id   uuid;
  v_version_test   int;
  v_equipo_id      uuid;
  v_evento_id      uuid;
  v_mant_id        uuid;
  v_requerido_id   uuid;
  v_recurso_id     uuid;
begin
  select id into v_cliente_id from public.clientes where codigo = 'CODELCO';
  select id into v_faena_id   from public.faenas where cliente_id = v_cliente_id and codigo = 'ANDINA';
  select id into v_area_id    from public.areas where faena_id = v_faena_id and codigo = 'MOLIENDA';
  if v_cliente_id is null or v_faena_id is null or v_area_id is null then
    raise exception 'TEST ABORTADO: no se encontró CODELCO → Andina → Molienda.';
  end if;

  select id into v_tipo_mant_id from public.tipos_mantencion where codigo = 'MANTENCION_MENSUAL';
  if v_tipo_mant_id is null then
    raise exception 'TEST ABORTADO: no se encontró MANTENCION_MENSUAL.';
  end if;

  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_id, 'TEST-EQ-2D09', 'TEST-TAG-2D09', 'Equipo de prueba (2D.09)', 'Motor eléctrico', true)
  returning id into v_equipo_id;

  update public.plantillas_mantencion set activa = false
    where tipo_mantencion_id = v_tipo_mant_id and activa = true;
  select coalesce(max(version), 0) + 1000 into v_version_test
    from public.plantillas_mantencion where tipo_mantencion_id = v_tipo_mant_id;
  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test, 'TEST_PLANTILLA_2D09', true)
  returning id into v_plantilla_id;

  insert into public.plantilla_personal (plantilla_id, perfil, cantidad, especialidad, obligatorio)
  values (v_plantilla_id, 'Electricista', 1, 'Media tensión', true);
  insert into public.plantilla_recursos (plantilla_id, categoria_recurso, nombre_generico, cantidad_sugerida, obligatorio)
  values (v_plantilla_id, 'herramienta', 'Megger 5kV', 1, false);

  -- El evento se crea con el ACTOR (supervisor propietario de prueba),
  -- no con el administrador — fn_crear_evento_mantencion permite esto
  -- porque quien llama (el admin impersonado en este bloque) es es_admin().
  select id into v_evento_id
  from fn_crear_evento_mantencion(
    p_cliente_id => v_cliente_id, p_faena_id => v_faena_id, p_tipo_evento => 'PROGRAMADA',
    p_nombre => 'TEST evento 2D.09', p_supervisor_id => current_setting('ayca_test.actor_id')::uuid
  );

  select mantencion_id into v_mant_id
  from fn_agregar_equipo_evento(v_evento_id, v_area_id, v_equipo_id, v_tipo_mant_id, v_plantilla_id);

  select id into v_requerido_id from evento_personal_requerido where evento_mantencion_id = v_evento_id;
  select id into v_recurso_id   from evento_recursos           where evento_mantencion_id = v_evento_id;

  perform set_config('ayca_test.evento_id',    v_evento_id::text, true);
  perform set_config('ayca_test.mant_id',      v_mant_id::text, true);
  perform set_config('ayca_test.requerido_id', v_requerido_id::text, true);
  perform set_config('ayca_test.recurso_id',   v_recurso_id::text, true);

  raise notice 'Setup completo (impersonando admin) -> evento=%, mantencion=%', v_evento_id, v_mant_id;
end $$;

-- ── C. Administrador: acceso total (seguimos impersonando al admin) ──
do $$
declare v_n int;
begin
  select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_n <> 1 then raise exception 'TEST FALLIDO (C): administrador no ve el evento (esperado 1, obtenido %).', v_n; end if;

  select count(*) into v_n from mantenciones where id = current_setting('ayca_test.mant_id')::uuid;
  if v_n <> 1 then raise exception 'TEST FALLIDO (C): administrador no ve la mantención.'; end if;

  select count(*) into v_n from evento_personal_requerido where id = current_setting('ayca_test.requerido_id')::uuid;
  if v_n <> 1 then raise exception 'TEST FALLIDO (C): administrador no ve evento_personal_requerido.'; end if;

  raise notice '✔ C) OK: administrador ve evento, mantención y personal requerido.';
end $$;

-- ── D. Supervisor propietario: ve todo lo del evento que supervisa ──
select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_id'))::text, true);
do $$
declare v_n int;
begin
  select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_n <> 1 then raise exception 'TEST FALLIDO (D): el supervisor propietario no ve su propio evento.'; end if;

  select count(*) into v_n from mantenciones where id = current_setting('ayca_test.mant_id')::uuid;
  if v_n <> 1 then raise exception 'TEST FALLIDO (D): el supervisor propietario no ve la mantención de su evento.'; end if;

  select count(*) into v_n from evento_recursos where id = current_setting('ayca_test.recurso_id')::uuid;
  if v_n <> 1 then raise exception 'TEST FALLIDO (D): el supervisor propietario no ve los recursos de su evento.'; end if;

  raise notice '✔ D) OK: supervisor propietario ve evento, mantención y recursos.';
end $$;

-- ── E. Usuario sin rol (identidad sintética, sin fila en usuario_roles) ──
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid()::text)::text, true);
do $$
declare v_n int;
begin
  select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
  if v_n <> 0 then raise exception 'TEST FALLIDO (E): un usuario sin rol vio el evento (obtenido % filas).', v_n; end if;

  select count(*) into v_n from evento_personal_requerido where id = current_setting('ayca_test.requerido_id')::uuid;
  if v_n <> 0 then raise exception 'TEST FALLIDO (E): un usuario sin rol vio evento_personal_requerido.'; end if;

  raise notice '✔ E) OK: usuario sin rol no ve nada del evento.';
end $$;

do $$
begin
  if current_setting('ayca_test.tiene_actor_2') <> 'true' then
    raise notice 'AVISO: se omiten F/G/H/I/J/K — no hay un segundo usuario real disponible en esta base.';
  end if;
end $$;

-- ── F. Supervisor ajeno: actor_2 con rol 'supervisor' (vía
--       usuario_roles), pero NO es el supervisor de este evento ──
reset role;
insert into public.usuario_roles (usuario_id, rol)
  select nullif(current_setting('ayca_test.actor_2_id'), '')::uuid, 'supervisor'
  where current_setting('ayca_test.tiene_actor_2') = 'true'
on conflict (usuario_id, rol) do nothing;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_2_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_n int;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 0 then
      raise exception 'TEST FALLIDO (F): un supervisor AJENO (con rol pero sin ser dueño del evento) vio el evento.';
    end if;

    select count(*) into v_n from mantenciones where id = current_setting('ayca_test.mant_id')::uuid;
    if v_n <> 0 then
      raise exception 'TEST FALLIDO (F): un supervisor ajeno vio la mantención de un evento que no supervisa.';
    end if;

    raise notice '✔ F) OK: supervisor ajeno (tiene el rol, no es dueño de este evento) no ve nada de él.';
  end if;
end $$;

reset role;
delete from public.usuario_roles
  where usuario_id = nullif(current_setting('ayca_test.actor_2_id'), '')::uuid and rol = 'supervisor'
  and current_setting('ayca_test.tiene_actor_2') = 'true';
set local role authenticated;

-- ── G. Técnico NO asignado (todavía) — debe seguir sin ver nada ──
select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_2_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_n int;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 0 then
      raise exception 'TEST FALLIDO (G): un usuario todavía no asignado vio el evento.';
    end if;

    raise notice '✔ G) OK: técnico no asignado todavía no ve nada del evento.';
  end if;
end $$;

-- ── H. Técnico ASIGNADO (vigente) — ahora sí ve el evento; luego se
--       LIBERA la asignación y debe volver a perder el acceso ──
reset role;
insert into public.perfiles_ayca (id, nombre, activo)
  select nullif(current_setting('ayca_test.actor_2_id'), '')::uuid, 'Técnico de prueba 2D.09', true
  where current_setting('ayca_test.tiene_actor_2') = 'true'
on conflict (id) do update set activo = true;
set local role authenticated;

select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_asignacion_id uuid;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    v_asignacion_id := fn_asignar_persona_evento(
      current_setting('ayca_test.evento_id')::uuid,
      current_setting('ayca_test.actor_2_id')::uuid,
      'Técnico de apoyo'
    );
    perform set_config('ayca_test.asignacion_id', v_asignacion_id::text, true);
  end if;
end $$;

select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_2_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_n int;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (H-asignado): el técnico asignado (vigente) no ve el evento.'; end if;

    select count(*) into v_n from mantenciones where id = current_setting('ayca_test.mant_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (H-asignado): el técnico asignado no ve la mantención del evento.'; end if;

    select count(*) into v_n from evento_personal_asignado where id = current_setting('ayca_test.asignacion_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (H-asignado): el técnico no ve su propia fila de asignación.'; end if;

    raise notice '✔ H-asignado) OK: técnico con asignación vigente ve el evento, la mantención y su asignación.';
  end if;
end $$;

-- Liberar la asignación (como el supervisor propietario) y volver a probar.
select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    perform fn_quitar_persona_evento(current_setting('ayca_test.asignacion_id')::uuid, 'Prueba 2D.09 — liberar para probar RLS');
  end if;
end $$;

select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_2_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_n int;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 0 then raise exception 'TEST FALLIDO (H-liberado): el técnico con asignación LIBERADA todavía ve el evento.'; end if;

    select count(*) into v_n from mantenciones where id = current_setting('ayca_test.mant_id')::uuid;
    if v_n <> 0 then raise exception 'TEST FALLIDO (H-liberado): el técnico liberado todavía ve la mantención.'; end if;

    raise notice '✔ H-liberado) OK: técnico con asignación liberada pierde el acceso al evento y a la mantención.';
  end if;
end $$;

-- ── I. Planificador: lectura amplia, sin escritura nueva ──
reset role;
insert into public.usuario_roles (usuario_id, rol)
  select nullif(current_setting('ayca_test.actor_2_id'), '')::uuid, 'planificador'
  where current_setting('ayca_test.tiene_actor_2') = 'true'
on conflict (usuario_id, rol) do nothing;
set local role authenticated;

select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_2_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_n int;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (I): planificador no ve el evento (lectura amplia esperada).'; end if;

    select count(*) into v_n from mantenciones where id = current_setting('ayca_test.mant_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (I): planificador no ve la mantención.'; end if;

    raise notice '✔ I) OK: planificador tiene lectura amplia de evento y mantención.';
  end if;
end $$;

reset role;
delete from public.usuario_roles
  where usuario_id = nullif(current_setting('ayca_test.actor_2_id'), '')::uuid and rol = 'planificador'
  and current_setting('ayca_test.tiene_actor_2') = 'true';
set local role authenticated;

-- ── J. Bodega: lectura de evento_recursos y del evento; SIN acceso a
--       evento_personal_requerido (matriz de permisos) ──
reset role;
insert into public.usuario_roles (usuario_id, rol)
  select nullif(current_setting('ayca_test.actor_2_id'), '')::uuid, 'bodega'
  where current_setting('ayca_test.tiene_actor_2') = 'true'
on conflict (usuario_id, rol) do nothing;
set local role authenticated;

select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_2_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_n int;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (J): bodega no ve el evento.'; end if;

    select count(*) into v_n from evento_recursos where id = current_setting('ayca_test.recurso_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (J): bodega no ve evento_recursos.'; end if;

    select count(*) into v_n from evento_personal_requerido where id = current_setting('ayca_test.requerido_id')::uuid;
    if v_n <> 0 then raise exception 'TEST FALLIDO (J): bodega vio evento_personal_requerido (no debería, según la matriz de permisos).'; end if;

    raise notice '✔ J) OK: bodega ve evento_recursos y el evento, pero no evento_personal_requerido.';
  end if;
end $$;

reset role;
delete from public.usuario_roles
  where usuario_id = nullif(current_setting('ayca_test.actor_2_id'), '')::uuid and rol = 'bodega'
  and current_setting('ayca_test.tiene_actor_2') = 'true';
set local role authenticated;

-- ── K. Gerencia: lectura global, sin escritura ──
reset role;
insert into public.usuario_roles (usuario_id, rol)
  select nullif(current_setting('ayca_test.actor_2_id'), '')::uuid, 'gerencia'
  where current_setting('ayca_test.tiene_actor_2') = 'true'
on conflict (usuario_id, rol) do nothing;
set local role authenticated;

select set_config('request.jwt.claims', json_build_object('sub', current_setting('ayca_test.actor_2_id'))::text, true)
where current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
declare v_n int;
begin
  if current_setting('ayca_test.tiene_actor_2') = 'true' then
    select count(*) into v_n from eventos_mantencion where id = current_setting('ayca_test.evento_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (K): gerencia no ve el evento.'; end if;

    select count(*) into v_n from mantenciones where id = current_setting('ayca_test.mant_id')::uuid;
    if v_n <> 1 then raise exception 'TEST FALLIDO (K): gerencia no ve la mantención.'; end if;

    raise notice '✔ K) OK: gerencia tiene lectura global de evento y mantención.';
  end if;
end $$;

reset role;
delete from public.usuario_roles
  where usuario_id = nullif(current_setting('ayca_test.actor_2_id'), '')::uuid and rol = 'gerencia'
  and current_setting('ayca_test.tiene_actor_2') = 'true';

do $$
begin
  raise notice '✔ TEST 2D.09 COMPLETO: C, D, E siempre corren; F, G, H, I, J, K dependen de un segundo usuario real (avisados si se omiten).';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
