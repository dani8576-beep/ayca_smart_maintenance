-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Test funcional de la ETAPA 2D.04
-- (evento_recursos)
--
-- Requiere que ya estén ejecutadas: perfiles_roles.sql,
-- mantenciones_etapa2a.sql, mantenciones_etapa2a5.sql,
-- mantenciones_etapa2d_01_eventos_numeracion.sql,
-- mantenciones_etapa2d_04_recursos.sql.
--
-- NO modifica nada de forma permanente: todo corre dentro de una
-- transacción y termina en ROLLBACK. Usa cliente/faena REALES
-- (CODELCO → Andina) para un evento de prueba, y un insumo de prueba
-- TEMPORAL en insumos_bodega (con categoria conocida = 'epp') para
-- poder probar la consistencia categoria_recurso ↔ catálogo real sin
-- depender de datos de bodega preexistentes. No se crea ninguna
-- herramienta de prueba (no se conoce su DDL completo fuera de estas
-- migraciones) — los escenarios con categoria "herramienta" usan
-- herramienta_codigo NULL (recurso genérico), que es un caso válido
-- según el diseño.
--
-- Escenarios cubiertos:
--   A) Setup: evento de prueba, insumo de prueba temporal.
--   B) Positivo: recurso genérico de categoría "herramienta" (ambos
--      códigos null).
--   C) Negativo: categoria "herramienta" con insumo_codigo informado —
--      viola el CHECK de exclusividad.
--   D) Negativo: cantidad_sugerida negativa.
--   E) Negativo: nombre_generico vacío/solo espacios.
--   F) Negativo: categoria_recurso declarada no coincide con la
--      categoria real del insumo referenciado.
--   G) Negativo: duplicado vigente del mismo recurso genérico (mismo
--      nombre_generico salvo mayúsculas/espacios) — índice único por
--      expresión.
--   H) Positivo: tras marcar la fila original como 'eliminado', se
--      puede volver a agregar el mismo recurso.
--   I) Negativo: marcar una fila como 'eliminado' sin motivo_modificacion.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── A. Setup: actor, evento de prueba, insumo de prueba temporal ──
do $$
declare
  v_actor_id   uuid;
  v_cliente_id uuid;
  v_faena_id   uuid;
  v_evento_id  uuid;
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
  values (fn_generar_numero_evento_mantencion(), v_cliente_id, v_faena_id, 'PROGRAMADA', 'TEST evento 2D.04', v_actor_id, v_actor_id)
  returning id into v_evento_id;

  -- Insumo de prueba temporal: categoria real conocida = 'epp'.
  insert into public.insumos_bodega (codigo, nombre, categoria, unidad_medida)
  values ('TEST-INSUMO-2D04', 'Insumo de prueba 2D.04 (guantes dieléctricos)', 'epp', 'par')
  on conflict (codigo) do nothing;

  raise notice 'Setup completo -> actor=%, evento=%', v_actor_id, v_evento_id;

  perform set_config('ayca_test.actor_id',  v_actor_id::text, true);
  perform set_config('ayca_test.evento_id', v_evento_id::text, true);
end $$;

-- ── B. Positivo: recurso genérico de categoría "herramienta" ──
do $$
declare
  v_recurso_id uuid;
begin
  insert into public.evento_recursos (
    evento_mantencion_id, categoria_recurso, nombre_generico, cantidad_sugerida, origen, creado_por
  ) values (
    current_setting('ayca_test.evento_id')::uuid, 'herramienta', 'Megger 5kV', 2, 'plantilla',
    current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_recurso_id;

  perform set_config('ayca_test.recurso_megger_id', v_recurso_id::text, true);
  raise notice '✔ B) OK: recurso genérico (Megger 5kV) creado (id=%).', v_recurso_id;
end $$;

-- ── C. Negativo: categoria "herramienta" con insumo_codigo informado ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_recursos (
      evento_mantencion_id, categoria_recurso, nombre_generico, insumo_codigo, cantidad_sugerida, origen, creado_por
    ) values (
      current_setting('ayca_test.evento_id')::uuid, 'herramienta', 'Recurso inválido', 'TEST-INSUMO-2D04', 1, 'manual',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ C) OK: herramienta con insumo_codigo informado rechazado — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (C): se permitió categoria "herramienta" con insumo_codigo informado.';
  end if;
end $$;

-- ── D. Negativo: cantidad_sugerida negativa ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_recursos (
      evento_mantencion_id, categoria_recurso, nombre_generico, cantidad_sugerida, origen, creado_por
    ) values (
      current_setting('ayca_test.evento_id')::uuid, 'instrumento', 'Pie de metro', -1, 'manual',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ D) OK: cantidad_sugerida negativa rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (D): se permitió cantidad_sugerida negativa.';
  end if;
end $$;

-- ── E. Negativo: nombre_generico vacío/solo espacios ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_recursos (
      evento_mantencion_id, categoria_recurso, nombre_generico, cantidad_sugerida, origen, creado_por
    ) values (
      current_setting('ayca_test.evento_id')::uuid, 'material', '   ', 1, 'manual',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ E) OK: nombre_generico vacío rechazado — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (E): se permitió nombre_generico vacío.';
  end if;
end $$;

-- ── F. Negativo: categoria_recurso declarada no coincide con la
--       categoria real del insumo referenciado (insumo es 'epp', se
--       declara 'consumible') ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_recursos (
      evento_mantencion_id, categoria_recurso, nombre_generico, insumo_codigo, cantidad_sugerida, origen, creado_por
    ) values (
      current_setting('ayca_test.evento_id')::uuid, 'consumible', 'Guantes dieléctricos (mal clasificados)',
      'TEST-INSUMO-2D04', 5, 'manual', current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ F) OK: categoria_recurso inconsistente con el catálogo de insumos rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (F): se permitió una categoria_recurso que no coincide con la categoria real del insumo.';
  end if;
end $$;

-- ── G. Negativo: duplicado vigente del mismo recurso genérico (mismo
--       nombre_generico salvo mayúsculas/espacios) ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_recursos (
      evento_mantencion_id, categoria_recurso, nombre_generico, cantidad_sugerida, origen, creado_por
    ) values (
      current_setting('ayca_test.evento_id')::uuid, 'herramienta', '  megger 5kv  ', 1, 'manual',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when unique_violation then
    v_fallo := true;
    raise notice '✔ G) OK: duplicado normalizado (mayúsculas/espacios) rechazado por el índice único — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (G): se permitió un duplicado vigente del mismo recurso genérico.';
  end if;
end $$;

-- ── H. Positivo: tras marcar la fila original como 'eliminado', se
--       puede volver a agregar el mismo recurso ──
do $$
declare
  v_recurso_nuevo_id uuid;
begin
  update public.evento_recursos
    set estado_fila = 'eliminado', motivo_modificacion = 'Ya no se requiere (prueba 2D.04)'
    where id = current_setting('ayca_test.recurso_megger_id')::uuid;

  raise notice '✔ H1) OK: recurso Megger 5kV original marcado como eliminado.';

  insert into public.evento_recursos (
    evento_mantencion_id, categoria_recurso, nombre_generico, cantidad_sugerida, origen, creado_por
  ) values (
    current_setting('ayca_test.evento_id')::uuid, 'herramienta', 'Megger 5kV', 3, 'manual',
    current_setting('ayca_test.actor_id')::uuid
  )
  returning id into v_recurso_nuevo_id;

  if v_recurso_nuevo_id is null then
    raise exception 'TEST FALLIDO (H2): no se pudo volver a agregar el recurso tras eliminar el anterior.';
  end if;
  raise notice '✔ H2) OK: recurso Megger 5kV vuelto a agregar tras eliminar el anterior (nueva id=%).', v_recurso_nuevo_id;
end $$;

-- ── I. Negativo: marcar una fila como 'eliminado' sin motivo_modificacion ──
do $$
declare
  v_fallo boolean := false;
begin
  begin
    insert into public.evento_recursos (
      evento_mantencion_id, categoria_recurso, nombre_generico, cantidad_sugerida, origen, estado_fila, creado_por
    ) values (
      current_setting('ayca_test.evento_id')::uuid, 'material', 'Cinta aislante', 1, 'manual', 'eliminado',
      current_setting('ayca_test.actor_id')::uuid
    );
  exception when others then
    v_fallo := true;
    raise notice '✔ I) OK: fila eliminada sin motivo_modificacion rechazada — %', sqlerrm;
  end;

  if not v_fallo then
    raise exception 'TEST FALLIDO (I): se permitió marcar una fila como eliminada sin motivo_modificacion.';
  end if;
end $$;

do $$
begin
  raise notice '✔ TEST 2D.04 COMPLETO: positivos (B, H) y negativos (C, D, E, F, G, I) se comportaron como se esperaba.';
end $$;

-- ── No dejar ningún dato de prueba en la base ──
rollback;
