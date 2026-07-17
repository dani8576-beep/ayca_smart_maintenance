-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2C.4 — migración incremental
-- Agrega una columna "codigo" real a public.tipos_mantencion, con el
-- mismo principio ya usado en public.tipos_protocolo (código corto,
-- estable, normalizado en mayúsculas). Segura de re-ejecutar.
--
-- Ejecutar DESPUÉS de mantenciones_etapa2a.sql (crea tipos_mantencion)
-- y ANTES de mantenciones_etapa2c5_datos_maestros.sql (que insertará
-- usando "codigo"). No depende de la ETAPA 2B/2C (mantenciones /
-- Snapshot) — solo toca public.tipos_mantencion.
--
-- NO modifica ni elimina "nombre" ni ningún otro dato existente.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Diagnóstico (informativo) ──
do $$
declare
  v_total bigint;
begin
  select count(*) into v_total from public.tipos_mantencion;
  raise notice 'public.tipos_mantencion tiene % registro(s) actualmente.', v_total;
end $$;

-- ── 2. Agregar la columna "codigo" (nullable por ahora; idempotente) ──
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tipos_mantencion' and column_name = 'codigo'
  ) then
    alter table public.tipos_mantencion add column codigo text;
    raise notice 'Columna "codigo" agregada a public.tipos_mantencion.';
  else
    raise notice 'Columna "codigo" ya existía en public.tipos_mantencion, no se modifica.';
  end if;
end $$;

-- ── 3. Backfill seguro para filas existentes sin código (si las hubiera).
--       Se deriva mecánicamente desde "nombre" (mayúsculas, todo lo que no
--       sea A-Z/0-9 se reemplaza por "_") — no se inventa significado de
--       negocio, solo se normaliza el nombre ya existente para que ninguna
--       fila quede sin código. "nombre" no se toca en ningún momento. ──
update public.tipos_mantencion
set codigo = upper(regexp_replace(trim(nombre), '[^a-zA-Z0-9]+', '_', 'g'))
where codigo is null;

-- ── 4. Normalizar códigos ya presentes que no vengan en upper(trim(...)) ──
update public.tipos_mantencion
set codigo = upper(trim(codigo))
where codigo is not null and codigo <> upper(trim(codigo));

-- ── 5. CHECK: código no vacío (idempotente; valida el estado ya normalizado) ──
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tipos_mantencion'::regclass and conname = 'tipos_mantencion_codigo_not_empty'
  ) then
    alter table public.tipos_mantencion
      add constraint tipos_mantencion_codigo_not_empty check (codigo is null or trim(codigo) <> '');
    raise notice 'CHECK tipos_mantencion_codigo_not_empty agregado.';
  else
    raise notice 'CHECK tipos_mantencion_codigo_not_empty ya existía, no se modifica.';
  end if;
end $$;

-- ── 6. UNIQUE sobre "codigo" — solo si el backfill no dejó duplicados.
--       Si los hay, se avisa y NO se fuerza la restricción (evita romper
--       la migración por datos preexistentes en conflicto). ──
do $$
declare
  v_duplicados int;
begin
  select count(*) into v_duplicados from (
    select codigo from public.tipos_mantencion
    where codigo is not null
    group by codigo having count(*) > 1
  ) d;

  if v_duplicados > 0 then
    raise notice '⚠ Hay % código(s) duplicado(s) tras el backfill — revísalos manualmente antes de poder aplicar UNIQUE. Consulta: select codigo, array_agg(nombre) from public.tipos_mantencion group by codigo having count(*) > 1;', v_duplicados;
  else
    if not exists (
      select 1 from pg_constraint
      where conrelid = 'public.tipos_mantencion'::regclass and conname = 'tipos_mantencion_codigo_key'
    ) then
      alter table public.tipos_mantencion add constraint tipos_mantencion_codigo_key unique (codigo);
      raise notice 'UNIQUE tipos_mantencion_codigo_key agregado.';
    else
      raise notice 'UNIQUE tipos_mantencion_codigo_key ya existía, no se modifica.';
    end if;
  end if;
end $$;

-- ── 7. Normalización automática hacia adelante — reutiliza fn_normalizar_codigo()
--       (genérica, ya creada en la ETAPA 2A.5: new.codigo := upper(trim(new.codigo))),
--       sin duplicar función. DROP + CREATE porque Postgres no soporta
--       "CREATE TRIGGER IF NOT EXISTS". ──
drop trigger if exists trg_normalizar_codigo_tipos_mantencion on public.tipos_mantencion;

create trigger trg_normalizar_codigo_tipos_mantencion
  before insert or update on public.tipos_mantencion
  for each row execute function public.fn_normalizar_codigo();

-- ── 8. Aplicar NOT NULL solo si TODOS los registros ya tienen código ──
do $$
declare
  v_total      bigint;
  v_sin_codigo bigint;
  v_ya_notnull boolean;
begin
  select count(*) into v_total      from public.tipos_mantencion;
  select count(*) into v_sin_codigo from public.tipos_mantencion where codigo is null;

  select not attnotnull into v_ya_notnull
    from pg_attribute
    where attrelid = 'public.tipos_mantencion'::regclass and attname = 'codigo';

  if v_sin_codigo = 0 then
    if v_ya_notnull then
      alter table public.tipos_mantencion alter column codigo set not null;
      raise notice 'Todos los % registro(s) tienen código: se aplicó NOT NULL.', v_total;
    else
      raise notice '"codigo" ya era NOT NULL. Sin cambios.';
    end if;
  else
    raise notice '⚠ % registro(s) sin código todavía (probablemente por duplicado pendiente de resolver en el paso 6). "codigo" queda NULLABLE. Ejecuta luego: alter table public.tipos_mantencion alter column codigo set not null;', v_sin_codigo;
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop trigger if exists trg_normalizar_codigo_tipos_mantencion on public.tipos_mantencion;
-- alter table public.tipos_mantencion drop constraint if exists tipos_mantencion_codigo_key;
-- alter table public.tipos_mantencion drop constraint if exists tipos_mantencion_codigo_not_empty;
-- alter table public.tipos_mantencion alter column codigo drop not null;
-- alter table public.tipos_mantencion drop column if exists codigo;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- select column_name, is_nullable, data_type
--   from information_schema.columns
--   where table_schema = 'public' and table_name = 'tipos_mantencion' and column_name = 'codigo';
--
-- select conname, contype
--   from pg_constraint
--   where conrelid = 'public.tipos_mantencion'::regclass
--   order by conname;
--
-- select codigo, nombre from public.tipos_mantencion order by nombre;
