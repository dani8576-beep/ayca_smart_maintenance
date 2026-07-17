-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2A.5 — migración incremental
-- Agrega la columna "tag" a public.equipos (ya existente y ya ejecutada
-- en Supabase sin esta columna). Segura de re-ejecutar: cada paso
-- verifica su propio estado antes de actuar.
--
-- Ejecutar DESPUÉS de 2026-07-17_mantenciones_etapa2a5.sql (versión
-- original, ya aplicada). NO reemplaza ese archivo ni requiere
-- volver a correrlo.
--
-- NO modifica: mantenciones, mantencion_*, solicitudes_bodega,
-- protocolos_ayca, herramientas, herramientas_movimientos,
-- clientes, faenas, areas. NO toca la ETAPA 2B.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Diagnóstico: ¿equipos tiene registros? (solo informativo) ──
do $$
declare
  v_total bigint;
begin
  select count(*) into v_total from public.equipos;
  raise notice 'public.equipos tiene % registro(s) actualmente.', v_total;
end $$;

-- ── 2. Agregar la columna "tag" (nullable por ahora; idempotente) ──
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'equipos' and column_name = 'tag'
  ) then
    alter table public.equipos add column tag text;
    raise notice 'Columna "tag" agregada a public.equipos.';
  else
    raise notice 'Columna "tag" ya existía en public.equipos, no se modifica.';
  end if;
end $$;

-- ── 3. y ── 4. Restricciones: CHECK y UNIQUE (idempotentes, con nombre
--       explícito para poder verificar su existencia). Ambas son seguras
--       de agregar aunque existan filas con "tag" en null: CHECK con NULL
--       se evalúa como cumplido, y UNIQUE permite múltiples NULL en
--       PostgreSQL — no bloquean equipos que todavía no tienen tag.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.equipos'::regclass and conname = 'equipos_tag_not_empty'
  ) then
    alter table public.equipos
      add constraint equipos_tag_not_empty check (trim(tag) <> '');
    raise notice 'CHECK equipos_tag_not_empty agregado.';
  else
    raise notice 'CHECK equipos_tag_not_empty ya existía, no se modifica.';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.equipos'::regclass and conname = 'equipos_tag_key'
  ) then
    alter table public.equipos
      add constraint equipos_tag_key unique (tag);
    raise notice 'UNIQUE equipos_tag_key agregado.';
  else
    raise notice 'UNIQUE equipos_tag_key ya existía, no se modifica.';
  end if;
end $$;

-- ── 5. Función de normalización (crear o reutilizar; CREATE OR REPLACE
--       ya es idempotente por sí solo) ──
create or replace function public.fn_normalizar_tag()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.tag := upper(trim(new.tag));
  return new;
end;
$$;

-- ── 6. Trigger BEFORE INSERT OR UPDATE (Postgres no soporta
--       "CREATE TRIGGER IF NOT EXISTS"; se usa DROP + CREATE, seguro
--       de re-ejecutar) ──
drop trigger if exists trg_normalizar_tag_equipos on public.equipos;

create trigger trg_normalizar_tag_equipos
  before insert or update on public.equipos
  for each row execute function public.fn_normalizar_tag();

-- ── 7. Decisión final de NOT NULL, según el estado real de los datos ──
do $$
declare
  v_total    bigint;
  v_sin_tag  bigint;
  v_ya_notnull boolean;
begin
  select count(*) into v_total from public.equipos;
  select count(*) into v_sin_tag from public.equipos where tag is null;

  select not attnotnull into v_ya_notnull
    from pg_attribute
    where attrelid = 'public.equipos'::regclass and attname = 'tag';
  -- v_ya_notnull = true significa "todavía permite null" (negado abajo para claridad)

  if v_total = 0 then
    if v_ya_notnull then
      alter table public.equipos alter column tag set not null;
      raise notice 'public.equipos está vacía: "tag" quedó NOT NULL.';
    else
      raise notice '"tag" ya era NOT NULL. Sin cambios.';
    end if;

  elsif v_sin_tag = 0 then
    if v_ya_notnull then
      alter table public.equipos alter column tag set not null;
      raise notice 'Los % registro(s) existentes ya tienen "tag" asignado: se aplicó NOT NULL.', v_total;
    else
      raise notice '"tag" ya era NOT NULL. Sin cambios.';
    end if;

  else
    raise notice '⚠ public.equipos tiene % registro(s), % sin "tag" asignado. '
                 'La columna queda NULLABLE a propósito — no se inventan tags. '
                 'Asigna manualmente un tag único y válido a cada equipo pendiente '
                 'y luego ejecuta: alter table public.equipos alter column tag set not null;',
                 v_total, v_sin_tag;
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop trigger if exists trg_normalizar_tag_equipos on public.equipos;
-- drop function if exists public.fn_normalizar_tag();
-- alter table public.equipos drop constraint if exists equipos_tag_key;
-- alter table public.equipos drop constraint if exists equipos_tag_not_empty;
-- alter table public.equipos alter column tag drop not null;
-- alter table public.equipos drop column if exists tag;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Columna y nulabilidad actual:
-- select column_name, is_nullable, data_type
--   from information_schema.columns
--   where table_schema = 'public' and table_name = 'equipos' and column_name = 'tag';
--
-- 2) Restricciones presentes en equipos:
-- select conname, contype
--   from pg_constraint
--   where conrelid = 'public.equipos'::regclass
--   order by conname;
--
-- 3) Cuántos equipos existen y cuántos aún no tienen tag:
-- select count(*) as total, count(*) filter (where tag is null) as sin_tag
--   from public.equipos;
--
-- 4) Confirmar que el trigger quedó activo:
-- select tgname, tgenabled
--   from pg_trigger
--   where tgrelid = 'public.equipos'::regclass and tgname = 'trg_normalizar_tag_equipos';
--
-- 5) Probar la normalización sobre un registro existente (revertir el
--    valor de prueba después si no corresponde al equipo real):
-- update public.equipos set tag = '  gmd-sag-01  ' where id = (select id from public.equipos limit 1);
-- select tag from public.equipos where id = (select id from public.equipos limit 1); -- debe verse "GMD-SAG-01"
