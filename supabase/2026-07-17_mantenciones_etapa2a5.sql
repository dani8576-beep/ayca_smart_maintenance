-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2A.5
-- Catálogos maestros: clientes, faenas, areas, equipos
-- Ejecutar manualmente en el SQL Editor de Supabase, DESPUÉS de
-- 2026-07-17_perfiles_roles.sql (requiere es_admin()) y de
-- 2026-07-17_mantenciones_etapa2a.sql.
--
-- NO crea ni modifica: mantenciones, mantencion_*, solicitudes_bodega,
-- reservas, entregas, devoluciones, consumos, protocolos_ayca,
-- herramientas, herramientas_movimientos. NO crea pantallas.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. clientes ──
create table if not exists clientes (
  id              uuid primary key default gen_random_uuid(),
  codigo          text not null unique,
  nombre          text not null,
  razon_social    text,
  rut             text,
  activo          boolean not null default true,
  orden           int not null default 0 check (orden >= 0),
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz,
  check (trim(codigo) <> ''),
  check (trim(nombre) <> '')
);

create unique index if not exists uq_clientes_rut
  on clientes (rut) where rut is not null and trim(rut) <> '';

-- ── 2. faenas ──
create table if not exists faenas (
  id              uuid primary key default gen_random_uuid(),
  cliente_id      uuid not null references public.clientes(id) on delete restrict,
  codigo          text not null,
  nombre          text not null,
  ubicacion       text,
  activo          boolean not null default true,
  orden           int not null default 0 check (orden >= 0),
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz,
  unique (cliente_id, codigo),
  unique (cliente_id, nombre),
  check (trim(codigo) <> ''),
  check (trim(nombre) <> '')
);

-- ── 3. areas ──
create table if not exists areas (
  id              uuid primary key default gen_random_uuid(),
  faena_id        uuid not null references public.faenas(id) on delete restrict,
  codigo          text not null,
  nombre          text not null,
  descripcion     text,
  activo          boolean not null default true,
  orden           int not null default 0 check (orden >= 0),
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz,
  unique (faena_id, codigo),
  unique (faena_id, nombre),
  check (trim(codigo) <> ''),
  check (trim(nombre) <> '')
);

-- ── 4. equipos ──
-- "tag" = identificación técnica/industrial del activo (ej. GMD-SAG-01, MTR-4201);
-- "nombre" sigue siendo la descripción legible. "tag" es lo que usarán mantenciones,
-- protocolos, informes PDF, búsquedas, dashboard e historial.
create table if not exists equipos (
  id              uuid primary key default gen_random_uuid(),
  area_id         uuid not null references public.areas(id) on delete restrict,
  codigo          text not null,
  tag             text not null unique,
  nombre          text not null,
  tipo_equipo     text,
  fabricante      text,
  modelo          text,
  numero_serie    text,
  potencia_kw     numeric check (potencia_kw > 0),
  tension_v       numeric check (tension_v > 0),
  criticidad      text check (criticidad is null or criticidad in ('baja','media','alta','critica')),
  activo          boolean not null default true,
  observaciones   text,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz,
  unique (area_id, codigo),
  check (trim(codigo) <> ''),
  check (trim(nombre) <> ''),
  check (trim(tag) <> '')
);

create unique index if not exists uq_equipos_numero_serie
  on equipos (numero_serie) where numero_serie is not null and trim(numero_serie) <> '';

-- Nota: "tag" ya es "not null unique" sin condición, por lo que Postgres crea su propio
-- índice único automáticamente; no hace falta un índice adicional (a diferencia de "rut"
-- y "numero_serie", que son nullable y por eso requieren índice único parcial).

-- ── Índices ──
create index if not exists idx_clientes_activo on clientes(activo);
create index if not exists idx_clientes_nombre on clientes(nombre);
create index if not exists idx_clientes_orden  on clientes(orden);

create index if not exists idx_faenas_cliente on faenas(cliente_id);
create index if not exists idx_faenas_activo  on faenas(activo);
create index if not exists idx_faenas_nombre  on faenas(nombre);
create index if not exists idx_faenas_orden   on faenas(orden);

create index if not exists idx_areas_faena  on areas(faena_id);
create index if not exists idx_areas_activo on areas(activo);
create index if not exists idx_areas_nombre on areas(nombre);
create index if not exists idx_areas_orden  on areas(orden);

create index if not exists idx_equipos_area        on equipos(area_id);
create index if not exists idx_equipos_activo      on equipos(activo);
create index if not exists idx_equipos_tipo_equipo on equipos(tipo_equipo);
create index if not exists idx_equipos_criticidad  on equipos(criticidad);
create index if not exists idx_equipos_nombre      on equipos(nombre);

-- ── Normalización de "codigo" (genérica, reutilizable en cualquier tabla con esa columna) ──
create or replace function fn_normalizar_codigo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.codigo := upper(trim(new.codigo));
  return new;
end;
$$;

create trigger trg_normalizar_codigo_clientes
  before insert or update on clientes
  for each row execute function fn_normalizar_codigo();

create trigger trg_normalizar_codigo_faenas
  before insert or update on faenas
  for each row execute function fn_normalizar_codigo();

create trigger trg_normalizar_codigo_areas
  before insert or update on areas
  for each row execute function fn_normalizar_codigo();

create trigger trg_normalizar_codigo_equipos
  before insert or update on equipos
  for each row execute function fn_normalizar_codigo();

-- ── Normalización de "tag" (solo equipos; función separada porque no todas las
--    tablas con fn_normalizar_codigo tienen columna "tag") ──
create or replace function fn_normalizar_tag()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.tag := upper(trim(new.tag));
  return new;
end;
$$;

create trigger trg_normalizar_tag_equipos
  before insert or update on equipos
  for each row execute function fn_normalizar_tag();

-- ── Auditoría (genérica, reutilizable en cualquier tabla con creado_por/creado_en/
--    actualizado_por/actualizado_en; no existía una equivalente ya creada en el proyecto) ──
create or replace function fn_tocar_auditoria()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.actualizado_en := now();
  new.actualizado_por := auth.uid();
  new.creado_por := old.creado_por;
  new.creado_en  := old.creado_en;
  return new;
end;
$$;

create trigger trg_auditoria_clientes
  before update on clientes
  for each row execute function fn_tocar_auditoria();

create trigger trg_auditoria_faenas
  before update on faenas
  for each row execute function fn_tocar_auditoria();

create trigger trg_auditoria_areas
  before update on areas
  for each row execute function fn_tocar_auditoria();

create trigger trg_auditoria_equipos
  before update on equipos
  for each row execute function fn_tocar_auditoria();

-- ── RLS ──
alter table clientes enable row level security;
alter table faenas   enable row level security;
alter table areas    enable row level security;
alter table equipos  enable row level security;

create policy "clientes_select_auth"  on clientes for select using (auth.uid() is not null);
create policy "clientes_insert_admin" on clientes for insert with check (es_admin());
create policy "clientes_update_admin" on clientes for update using (es_admin());
create policy "clientes_delete_admin" on clientes for delete using (es_admin());

create policy "faenas_select_auth"  on faenas for select using (auth.uid() is not null);
create policy "faenas_insert_admin" on faenas for insert with check (es_admin());
create policy "faenas_update_admin" on faenas for update using (es_admin());
create policy "faenas_delete_admin" on faenas for delete using (es_admin());

create policy "areas_select_auth"  on areas for select using (auth.uid() is not null);
create policy "areas_insert_admin" on areas for insert with check (es_admin());
create policy "areas_update_admin" on areas for update using (es_admin());
create policy "areas_delete_admin" on areas for delete using (es_admin());

create policy "equipos_select_auth"  on equipos for select using (auth.uid() is not null);
create policy "equipos_insert_admin" on equipos for insert with check (es_admin());
create policy "equipos_update_admin" on equipos for update using (es_admin());
create policy "equipos_delete_admin" on equipos for delete using (es_admin());

-- ═══════════════════════════════════════════════════════════════
-- BLOQUE OPCIONAL DE SEMILLAS — NO SE EJECUTA AUTOMÁTICAMENTE.
-- Todo está comentado a propósito. Descomenta y ejecuta manualmente
-- solo tras aprobación explícita separada de este script.
-- ═══════════════════════════════════════════════════════════════

-- insert into clientes (codigo, nombre) values
--   ('CODELCO', 'CODELCO'),
--   ('ANGLO',   'Anglo American'),
--   ('SGSCM',   'Sierra Gorda SCM'),
--   ('LUNDIN',  'Lundin Mining'),
--   ('KINROSS', 'Kinross')
-- on conflict (codigo) do nothing;
