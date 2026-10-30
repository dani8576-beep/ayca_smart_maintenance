-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — RLS: ampliar UPDATE por columna en
-- public.mantencion_actividades para incluir resultado/num_observacion
-- (Orden de Trabajo — captura de resultado corporativo, previa al PDF)
--
-- CONTEXTO:
-- 2026-07-22_mantencion_actividades_rls_update.sql ya otorgó UPDATE por
-- columna sobre (estado_ejecucion, actualizado_por, actualizado_en) y creó
-- la política de fila "mantencion_actividades_update" (solo supervisor de
-- la mantención o admin, y solo si la mantención no está 'cerrada'). Esta
-- migración NO toca esa política — solo amplía qué columnas puede tocar
-- un UPDATE que ya pasó esa política.
--
-- OBJETIVO:
-- Permitir que el supervisor registre, por actividad, el resultado del
-- formato corporativo (resultado: 'si'/'no'/'na', ya con ese CHECK desde
-- 2026-07-17_mantenciones_etapa2c.sql) y una referencia de observación
-- (num_observacion, texto libre, ya existente) — SIN modificar el
-- concepto de estado_ejecucion ('pendiente'/'completada', ya implementado
-- en la pantalla Orden de Trabajo). Son dos conceptos independientes:
-- estado_ejecucion = ¿ya se ejecutó la actividad?
-- resultado        = ¿cuál fue el resultado registrado en el formato?
--
-- ALCANCE — ÚNICAMENTE:
-- 1. REVOKE + GRANT por columna, ampliando la lista de 3 a 5 columnas.
-- NO crea ninguna política nueva, NO modifica la política existente,
-- NO agrega ninguna columna, NO crea ninguna función. La política
-- "mantencion_actividades_update" (incluido el bloqueo de mantenciones
-- 'cerrada') permanece exactamente igual a como quedó en la migración
-- anterior — no se ejecuta ningún DROP POLICY / CREATE POLICY aquí.
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - Tabla mantencion_actividades con las columnas resultado y
--     num_observacion (2026-07-17_mantenciones_etapa2c.sql)
--   - Política "mantencion_actividades_update" y el GRANT de 3 columnas
--     (2026-07-22_mantencion_actividades_rls_update.sql)
--
-- NO ejecutar automáticamente — este archivo se entrega para revisión.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regclass('public.mantencion_actividades') is null then
    raise exception 'Falta la tabla mantencion_actividades — ejecutar primero 2026-07-17_mantenciones_etapa2c.sql';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'mantencion_actividades' and column_name = 'resultado'
  ) then
    raise exception 'mantencion_actividades.resultado no existe — revisar antes de continuar.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'mantencion_actividades' and column_name = 'num_observacion'
  ) then
    raise exception 'mantencion_actividades.num_observacion no existe — revisar antes de continuar.';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'mantencion_actividades' and policyname = 'mantencion_actividades_update'
  ) then
    raise exception 'Falta la política "mantencion_actividades_update" — ejecutar primero 2026-07-22_mantencion_actividades_rls_update.sql';
  end if;

  if not exists (
    select 1 from pg_class where relname = 'mantencion_actividades' and relrowsecurity = true
  ) then
    raise exception 'mantencion_actividades no tiene RLS habilitado — revisar antes de continuar.';
  end if;
end $$;

-- ── 1. Privilegios — se reemplaza el GRANT de 3 columnas por uno de 5.
--       La política de fila NO se toca: sigue siendo exactamente la misma
--       que ya evalúa "supervisor de la mantención o admin, y mantención
--       no cerrada" para CUALQUIER columna incluida en este GRANT. ──
revoke update on public.mantencion_actividades from authenticated;

grant update (
  estado_ejecucion,
  actualizado_por,
  actualizado_en,
  resultado,
  num_observacion
)
on public.mantencion_actividades
to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Privilegios de columna otorgados — debe devolver EXACTAMENTE 5 filas:
--    actualizado_en, actualizado_por, estado_ejecucion, num_observacion, resultado.
-- select grantee, column_name, privilege_type
--   from information_schema.column_privileges
--   where table_schema = 'public' and table_name = 'mantencion_actividades'
--     and grantee = 'authenticated' and privilege_type = 'UPDATE'
--   order by column_name;
--
-- 2) Confirmar que sigue sin haber UPDATE de tabla completa:
-- select privilege_type from information_schema.role_table_grants
--   where table_schema = 'public' and table_name = 'mantencion_actividades'
--     and grantee = 'authenticated';
-- -- Debe mostrar SELECT únicamente a nivel de tabla (el UPDATE es solo de columna).
--
-- 3) Confirmar que la política de fila NO cambió (mismo texto que antes,
--    debe seguir incluyendo "estado <> 'cerrada'"):
-- select policyname, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public' and tablename = 'mantencion_actividades' and policyname = 'mantencion_actividades_update';
--
-- 4) RLS sigue habilitado:
-- select relrowsecurity from pg_class where oid = 'public.mantencion_actividades'::regclass;
-- -- Debe devolver "true".
--
-- 5) La política SELECT existente sigue intacta:
-- select policyname from pg_policies
--   where schemaname = 'public' and tablename = 'mantencion_actividades' and cmd = 'r';
--
-- ═══════════════════════════════════════════════════════════════
-- PRUEBA FUNCIONAL — hacer DESDE LA APLICACIÓN (fase siguiente), no con
-- SQL suelto contra datos reales:
-- ═══════════════════════════════════════════════════════════════
-- a) Supervisor autorizado marca un resultado (Sí/No/N/A) y escribe un
--    N° Obs. en una actividad de su mantención — debe guardar.
-- b) Lo mismo sobre una mantención que no administra, o que está
--    'cerrada' — debe rechazarse (0 filas afectadas).
-- c) Confirmar que estado_ejecucion sigue funcionando exactamente igual
--    que antes de esta migración (no se vio afectado por este cambio).
--
-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- (vuelve al estado anterior: 3 columnas, no a cero)
-- ═══════════════════════════════════════════════════════════════
-- revoke update on public.mantencion_actividades from authenticated;
-- grant update (estado_ejecucion, actualizado_por, actualizado_en)
--   on public.mantencion_actividades to authenticated;
-- -- La política "mantencion_actividades_update" no se ve afectada por
-- -- este rollback (nunca se tocó en esta migración).
