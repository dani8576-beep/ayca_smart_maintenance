-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2D.02
-- (relación mantenciones ↔ eventos_mantencion)
--
-- Requiere que ya estén ejecutadas: perfiles_roles.sql,
-- mantenciones_etapa2a.sql, mantenciones_etapa2a5.sql (+ tag_equipos),
-- mantenciones_etapa2b.sql, mantenciones_etapa2c.sql (+ fix),
-- mantenciones_etapa2c4_codigo_tipos_mantencion.sql,
-- mantenciones_etapa2c5_datos_maestros.sql,
-- mantenciones_etapa2d_01_eventos_numeracion.sql,
-- mantenciones_etapa2d_02_relacion_evento.sql.
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK. Usa cliente/faenas/áreas/tipo de
-- mantención REALES (CODELCO → Andina y CODELCO → Teniente, ambos
-- cargados por 2C.5), más equipos y una plantilla de prueba temporales
-- (mismo criterio que el test de 2C).
--
-- Como fn_crear_mantencion() todavía NO acepta evento_mantencion_id (eso
-- llega recién en 2D-06) y fn_crear_evento_mantencion() tampoco existe
-- todavía, este test inserta directamente en "eventos_mantencion" y en
-- "mantenciones" para ejercitar exclusivamente lo que introduce 2D-02:
-- la columna, el índice único parcial, y los dos triggers nuevos. Esto
-- es intencional — valida el comportamiento a nivel de tabla,
-- independiente de qué función lo use más adelante.
--
-- Escenarios cubiertos:
--   A) Setup: datos maestros, 2 equipos de prueba, 1 plantilla de
--      prueba, 1 evento (CODELCO → Andina).
--   B) Positivo: mantención de un equipo de Andina asociada al evento.
--   C) Negativo: mantención de un equipo de Teniente asociada al mismo
--      evento (Andina) — debe fallar por jerarquía cliente/faena.
--   D) Negativo: el mismo equipo agregado dos veces al mismo evento —
--      debe fallar por el índice único parcial.
--   E) Negativo: intentar cambiar equipo_id de una mantención que YA
--      pertenece a un evento — debe fallar (bloqueo total, sin
--      excepción por estado).
--   F) Negativo: intentar desvincular/cambiar evento_mantencion_id de
--      una mantención ya creada — debe fallar por el mismo trigger.
--   G) Compatibilidad de mantención suelta con evento_mantencion_id
--      NULL: se crea sin evento (G1) y luego se corrige su equipo_id/
--      area_id mientras sigue en 'borrador' — permitido desde el ajuste
--      de 2D-02, a diferencia del bloqueo total original (G2).
--   H) Tras cancelar la mantención hija del equipo X, se vuelve a crear
--      una mantención para el mismo equipo dentro del mismo evento —
--      valida que el índice único parcial excluye correctamente las
--      filas en estado 'cancelada'.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Setup: datos maestros, equipos y plantilla de prueba, evento ──
do $$
declare
  v_actor_id         uuid;
  v_cliente_id       uuid;
  v_faena_andina_id  uuid;
  v_faena_tte_id     uuid;
  v_area_andina_id   uuid;
  v_area_tte_id      uuid; -- Teniente / Molienda
  v_area_tte_chan_id uuid; -- Teniente / Chancado (misma faena, otra área)
  v_tipo_mant_id     uuid;
  v_version_test     int;
  v_plantilla_id     uuid;
  v_plantilla_nombre text;
  v_equipo_x_id      uuid; -- Andina — coincide con el evento
  v_equipo_y_id      uuid; -- Teniente/Molienda — NO coincide con el evento
  v_equipo_z_id      uuid; -- Teniente/Chancado — misma faena que Y, otra área/equipo
  v_evento_id        uuid;
  v_evento_numero    text;
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
  if v_cliente_id is null then
    raise exception 'TEST ABORTADO: no se encontró el cliente CODELCO.';
  end if;

  select id into v_faena_andina_id from public.faenas where cliente_id = v_cliente_id and codigo = 'ANDINA';
  select id into v_faena_tte_id    from public.faenas where cliente_id = v_cliente_id and codigo = 'TENIENTE';
  if v_faena_andina_id is null or v_faena_tte_id is null then
    raise exception 'TEST ABORTADO: no se encontraron las faenas Andina y/o Teniente bajo CODELCO.';
  end if;

  select id into v_area_andina_id  from public.areas where faena_id = v_faena_andina_id and codigo = 'MOLIENDA';
  select id into v_area_tte_id     from public.areas where faena_id = v_faena_tte_id    and codigo = 'MOLIENDA';
  select id into v_area_tte_chan_id from public.areas where faena_id = v_faena_tte_id   and codigo = 'CHANCADO';
  if v_area_andina_id is null or v_area_tte_id is null or v_area_tte_chan_id is null then
    raise exception 'TEST ABORTADO: no se encontró el área Molienda bajo Andina/Teniente y/o Chancado bajo Teniente.';
  end if;

  select id into v_tipo_mant_id from public.tipos_mantencion where codigo = 'MANTENCION_MENSUAL';
  if v_tipo_mant_id is null then
    raise exception 'TEST ABORTADO: no se encontró el tipo de mantención MANTENCION_MENSUAL.';
  end if;

  -- Equipos de prueba temporales (nunca persisten, ver nota al inicio).
  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_andina_id, 'TEST-EQX-2D02', 'TEST-TAG-EQX-2D02', 'Equipo de prueba X (Andina) 2D.02', 'Motor eléctrico', true)
  returning id into v_equipo_x_id;

  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_tte_id, 'TEST-EQY-2D02', 'TEST-TAG-EQY-2D02', 'Equipo de prueba Y (Teniente/Molienda) 2D.02', 'Motor eléctrico', true)
  returning id into v_equipo_y_id;

  insert into public.equipos (area_id, codigo, tag, nombre, tipo_equipo, activo)
  values (v_area_tte_chan_id, 'TEST-EQZ-2D02', 'TEST-TAG-EQZ-2D02', 'Equipo de prueba Z (Teniente/Chancado) 2D.02', 'Motor eléctrico', true)
  returning id into v_equipo_z_id;

  -- Plantilla de prueba temporal (misma técnica que el test de 2C).
  update public.plantillas_mantencion set activa = false
    where tipo_mantencion_id = v_tipo_mant_id and activa = true;

  select coalesce(max(version), 0) + 1000 into v_version_test
    from public.plantillas_mantencion where tipo_mantencion_id = v_tipo_mant_id;

  insert into public.plantillas_mantencion (tipo_mantencion_id, version, nombre, activa)
  values (v_tipo_mant_id, v_version_test, 'TEST_EVENTO_ETAPA2D02', true)
  returning id, nombre into v_plantilla_id, v_plantilla_nombre;

  -- Evento de prueba: CODELCO → Andina (fn_crear_evento_mantencion() aún
  -- no existe — se inserta directo, es la tabla bajo prueba en 2D-01).
  v_evento_numero := fn_generar_numero_evento_mantencion();

  insert into public.eventos_mantencion (
    numero, cliente_id, faena_id, tipo_evento, nombre, supervisor_id, creado_por
  ) values (
    v_evento_numero, v_cliente_id, v_faena_andina_id, 'PROGRAMADA',
    'TEST evento 2D.02 — CODELCO/Andina', v_actor_id, v_actor_id
  )
  returning id into v_evento_id;

  raise notice 'Setup completo -> actor=%, cliente=CODELCO(%), andina=%, teniente=%, equipo_x(Andina)=%, equipo_y(Teniente)=%, plantilla=%, evento=%(%)',
    v_actor_id, v_cliente_id, v_faena_andina_id, v_faena_tte_id, v_equipo_x_id, v_equipo_y_id, v_plantilla_id, v_evento_id, v_evento_numero;

  perform set_config('ayca_test.cliente_id',        v_cliente_id::text, true);
  perform set_config('ayca_test.faena_andina_id',   v_faena_andina_id::text, true);
  perform set_config('ayca_test.faena_tte_id',      v_faena_tte_id::text, true);
  perform set_config('ayca_test.area_andina_id',    v_area_andina_id::text, true);
  perform set_config('ayca_test.area_tte_id',       v_area_tte_id::text, true);
  perform set_config('ayca_test.area_tte_chan_id',  v_area_tte_chan_id::text, true);
  perform set_config('ayca_test.tipo_mant_id',      v_tipo_mant_id::text, true);
  perform set_config('ayca_test.plantilla_id',      v_plantilla_id::text, true);
  perform set_config('ayca_test.plantilla_nombre',  v_plantilla_nombre, true);
  perform set_config('ayca_test.plantilla_version', v_version_test::text, true);
  perform set_config('ayca_test.equipo_x_id',       v_equipo_x_id::text, true);
  perform set_config('ayca_test.equipo_y_id',       v_equipo_y_id::text, true);
  perform set_config('ayca_test.equipo_z_id',       v_equipo_z_id::text, true);
  perform set_config('ayca_test.evento_id',         v_evento_id::text, true);
  perform set_config('ayca_test.actor_id',          v_actor_id::text, true);
end $$;

-- ── B. Positivo: mantención del equipo X (Andina) asociada al evento
--       (Andina) — debe funcionar sin errores ──
do $$
declare
  v_mant_x_id uuid;
begin
  insert into public.mantenciones (
    numero, cliente_id, faena_id, area_id, equipo_id,
    tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
    evento_mantencion_id, supervisor_id, creado_por
  ) values (
    fn_generar_numero_mantencion(),
    current_setting('ayca_test.cliente_id')::uuid,
    current_setting('ayca_test.faena_andina_id')::uuid,
    current_setting('ayca_test.area_andina_id')::uuid,
    current_setting('ayca_test.equipo_x_id')::uuid,
    current_setting('ayca_test.tipo_mant_id')::uuid,
    current_setting('ayca_test.plantilla_id')::uuid,
    current_setting('ayca_test.plantilla_nombre'),
    current_setting('ayca_test.plantilla_version')::int,
    current_setting('ayca_test.evento_id')::uuid,
    current_setting('ayca_test.actor_id')::uuid,
    current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_mant_x_id;

  perform set_config('ayca_test.mant_x_id', v_mant_x_id::text, true);
  raise notice '✔ B) OK: mantención del equipo X creada y asociada al evento (id=%).', v_mant_x_id;
end $$;

-- ── C. Negativo: mantención del equipo Y (Teniente) asociada al mismo
--       evento (Andina) — debe fallar por jerarquía cliente/faena ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.mantenciones (
      numero, cliente_id, faena_id, area_id, equipo_id,
      tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
      evento_mantencion_id, supervisor_id, creado_por
    ) values (
      fn_generar_numero_mantencion(),
      current_setting('ayca_test.cliente_id')::uuid,
      current_setting('ayca_test.faena_tte_id')::uuid,   -- Teniente: no coincide con el evento (Andina)
      current_setting('ayca_test.area_tte_id')::uuid,
      current_setting('ayca_test.equipo_y_id')::uuid,
      current_setting('ayca_test.tipo_mant_id')::uuid,
      current_setting('ayca_test.plantilla_id')::uuid,
      current_setting('ayca_test.plantilla_nombre'),
      current_setting('ayca_test.plantilla_version')::int,
      current_setting('ayca_test.evento_id')::uuid,
      current_setting('ayca_test.actor_id')::uuid,
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ C) OK: insert rechazado como se esperaba — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (C): se permitió asociar un equipo de Teniente a un evento de Andina.';
  end if;
end $$;

-- ── D. Negativo: mismo equipo (X) agregado dos veces al mismo evento —
--       debe fallar por el índice único parcial ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.mantenciones (
      numero, cliente_id, faena_id, area_id, equipo_id,
      tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
      evento_mantencion_id, supervisor_id, creado_por
    ) values (
      fn_generar_numero_mantencion(),
      current_setting('ayca_test.cliente_id')::uuid,
      current_setting('ayca_test.faena_andina_id')::uuid,
      current_setting('ayca_test.area_andina_id')::uuid,
      current_setting('ayca_test.equipo_x_id')::uuid,     -- mismo equipo que en B
      current_setting('ayca_test.tipo_mant_id')::uuid,
      current_setting('ayca_test.plantilla_id')::uuid,
      current_setting('ayca_test.plantilla_nombre'),
      current_setting('ayca_test.plantilla_version')::int,
      current_setting('ayca_test.evento_id')::uuid,       -- mismo evento que en B
      current_setting('ayca_test.actor_id')::uuid,
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when unique_violation then
    v_fallo := true;
    raise notice '✔ D) OK: insert duplicado rechazado por el índice único parcial — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (D): se permitió agregar el mismo equipo dos veces al mismo evento.';
  end if;
end $$;

-- ── E. Negativo: cambiar equipo_id de la mantención ya creada — debe
--       fallar por el trigger de inmutabilidad ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    update public.mantenciones
      set equipo_id = current_setting('ayca_test.equipo_y_id')::uuid
      where id = current_setting('ayca_test.mant_x_id')::uuid;
  exception when others then
    v_fallo := true;
    raise notice '✔ E) OK: cambio de equipo_id rechazado como se esperaba — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (E): se permitió cambiar el equipo_id de una mantención ya creada.';
  end if;
end $$;

-- ── F. Negativo: desvincular/cambiar evento_mantencion_id de la
--       mantención ya creada — debe fallar por el mismo trigger ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    update public.mantenciones
      set evento_mantencion_id = null
      where id = current_setting('ayca_test.mant_x_id')::uuid;
  exception when others then
    v_fallo := true;
    raise notice '✔ F) OK: cambio de evento_mantencion_id rechazado como se esperaba — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (F): se permitió desvincular una mantención de su evento después de creada.';
  end if;
end $$;

-- ── G. Compatibilidad de mantención suelta con evento_mantencion_id NULL ──
-- G1) Crear una mantención suelta (sin evento) para el equipo Y — debe
--     comportarse exactamente igual que en el flujo 2B/2C actual.
-- G2) A diferencia de la versión original de 2D-02 (bloqueo total), ahora
--     SÍ se puede corregir equipo_id/area_id de una mantención suelta
--     mientras sigue en 'borrador' — se corrige del equipo Y al equipo Z
--     (misma faena Teniente, área distinta: Molienda → Chancado),
--     re-validando la jerarquía completa en el proceso. cliente_id/
--     faena_id se mantienen sin cambios a propósito: ese campo sigue
--     siendo inmutable en cualquier caso, el ajuste solo relaja
--     equipo_id/area_id.
do $$
declare
  v_mant_suelta_id uuid;
begin
  insert into public.mantenciones (
    numero, cliente_id, faena_id, area_id, equipo_id,
    tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
    supervisor_id, creado_por
  ) values (
    fn_generar_numero_mantencion(),
    current_setting('ayca_test.cliente_id')::uuid,
    current_setting('ayca_test.faena_tte_id')::uuid,
    current_setting('ayca_test.area_tte_id')::uuid,
    current_setting('ayca_test.equipo_y_id')::uuid,
    current_setting('ayca_test.tipo_mant_id')::uuid,
    current_setting('ayca_test.plantilla_id')::uuid,
    current_setting('ayca_test.plantilla_nombre'),
    current_setting('ayca_test.plantilla_version')::int,
    current_setting('ayca_test.actor_id')::uuid,
    current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_mant_suelta_id;

  if v_mant_suelta_id is null then
    raise exception 'TEST FALLIDO (G1): no se pudo crear una mantención suelta (evento_mantencion_id NULL).';
  end if;
  raise notice '✔ G1) OK: mantención suelta creada sin evento (id=%).', v_mant_suelta_id;

  -- G2) Corrección de equipo_id/area_id permitida en borrador (equipo Y,
  -- Teniente/Molienda → equipo Z, Teniente/Chancado). faena_id/cliente_id
  -- no cambian — antes del ajuste, esta corrección habría fallado igual
  -- por el bloqueo total original de equipo_id/area_id.
  update public.mantenciones
    set equipo_id = current_setting('ayca_test.equipo_z_id')::uuid,
        area_id   = current_setting('ayca_test.area_tte_chan_id')::uuid
    where id = v_mant_suelta_id;

  raise notice '✔ G2) OK: equipo_id/area_id de una mantención suelta en borrador se corrigieron sin error (misma faena, otra área/equipo).';
end $$;

-- ── H. Después de cancelar una mantención hija, permitir crear una
--       nueva para el mismo equipo dentro del mismo evento ──
do $$
declare
  v_mant_x2_id uuid;
begin
  -- Cancelar la mantención X original del evento (creada en B). Cambiar
  -- "estado" no toca equipo_id/area_id/evento_mantencion_id, así que el
  -- trigger de inmutabilidad no lo bloquea.
  update public.mantenciones
    set estado = 'cancelada'
    where id = current_setting('ayca_test.mant_x_id')::uuid;

  raise notice '✔ H1) OK: mantención X original cancelada.';

  -- Con la fila anterior en 'cancelada', el índice único parcial
  -- (evento_mantencion_id, equipo_id) where estado <> 'cancelada' ya no
  -- la cuenta como activa — debe permitir agregar de nuevo el equipo X
  -- al mismo evento sin violar la restricción.
  insert into public.mantenciones (
    numero, cliente_id, faena_id, area_id, equipo_id,
    tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
    evento_mantencion_id, supervisor_id, creado_por
  ) values (
    fn_generar_numero_mantencion(),
    current_setting('ayca_test.cliente_id')::uuid,
    current_setting('ayca_test.faena_andina_id')::uuid,
    current_setting('ayca_test.area_andina_id')::uuid,
    current_setting('ayca_test.equipo_x_id')::uuid,
    current_setting('ayca_test.tipo_mant_id')::uuid,
    current_setting('ayca_test.plantilla_id')::uuid,
    current_setting('ayca_test.plantilla_nombre'),
    current_setting('ayca_test.plantilla_version')::int,
    current_setting('ayca_test.evento_id')::uuid,
    current_setting('ayca_test.actor_id')::uuid,
    current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_mant_x2_id;

  if v_mant_x2_id is null then
    raise exception 'TEST FALLIDO (H2): no se pudo re-agregar el equipo X al evento tras cancelar la mantención anterior.';
  end if;
  raise notice '✔ H2) OK: equipo X re-agregado al mismo evento tras cancelar su mantención anterior (nueva id=%).', v_mant_x2_id;
end $$;

-- ── I. Verificación final: estado consistente de todo lo creado en
--       este test (ningún escenario negativo dejó datos a medias) ──
select 'MANTENCIONES_FINAL' as chequeo, m.id, m.numero, m.equipo_id, m.evento_mantencion_id, m.estado
  from public.mantenciones m
  where m.evento_mantencion_id = current_setting('ayca_test.evento_id')::uuid
     or m.equipo_id in (
          current_setting('ayca_test.equipo_x_id')::uuid,
          current_setting('ayca_test.equipo_y_id')::uuid,
          current_setting('ayca_test.equipo_z_id')::uuid
        )
  order by m.creado_en;

do $$
begin
  raise notice '✔ TEST 2D.02 COMPLETO: positivo (B), los 4 negativos (C, D, E, F) y los escenarios de compatibilidad (G, H) se comportaron como se esperaba.';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
