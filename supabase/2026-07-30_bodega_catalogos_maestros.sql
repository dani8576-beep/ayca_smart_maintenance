-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Módulo Bodega, Fase 1.2
-- Catálogos maestros: bodega_categorias, bodega_marcas, bodega_ubicaciones
--
-- OBJETIVO:
-- Centralizar valores hoy escritos libremente (categoría, marca,
-- ubicación) para evitar duplicados como "Fluke"/"FLUKE"/"fluke" o
-- "Bodega Central"/"bodega central". Estas 3 tablas son la base sobre la
-- que la futura tabla "equipos_bodega" (NO se crea en esta migración)
-- deberá apoyarse mediante:
--   equipos_bodega.categoria_id  references bodega_categorias(id)
--   equipos_bodega.marca_id      references bodega_marcas(id)
--   equipos_bodega.ubicacion_id  references bodega_ubicaciones(id)
-- Ninguno de esos tres deberá quedar como texto libre — decisión ya
-- aprobada, a aplicar en la migración de "equipos_bodega" (pendiente).
--
-- También queda contemplada (NO se crea aquí) una futura tabla
-- "equipos_bodega_documentos" (certificados/manuales/fotos por equipo,
-- FK a equipos_bodega.id) — se menciona solo para que el diseño de
-- "equipos_bodega" no la bloquee cuando se implemente más adelante.
--
-- DECISIÓN CONFIRMADA: estados y tipos de movimiento NO son catálogo —
-- siguen siendo CHECK fijo por tabla operativa (se definirán junto con
-- "equipos_bodega" y "equipos_bodega_movimientos", no en esta migración).
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - es_admin(), tiene_rol(text)      (2026-07-17_perfiles_roles.sql)
--   - fn_tocar_auditoria()             (2026-07-17_mantenciones_etapa2a5.sql)
--   - fn_normalizar_codigo()           (2026-07-17_mantenciones_etapa2a5.sql)
--   - tabla faenas                    (2026-07-17_mantenciones_etapa2a5.sql)
--
-- NO crea equipos_bodega, equipos_bodega_movimientos ni
-- equipos_bodega_documentos. NO modifica herramientas, herramientas_movimientos
-- ni insumos_bodega. NO instala ninguna extensión (sin citext, sin pg_trgm —
-- la unicidad sin distinguir mayúsculas se resuelve con índices únicos
-- funcionales sobre lower(), justificado en la fase de diseño previa).
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regprocedure('public.es_admin()') is null then
    raise exception 'Falta es_admin() — ejecutar primero 2026-07-17_perfiles_roles.sql';
  end if;

  if to_regprocedure('public.tiene_rol(text)') is null then
    raise exception 'Falta tiene_rol(text) — ejecutar primero 2026-07-17_perfiles_roles.sql';
  end if;

  if to_regprocedure('public.fn_tocar_auditoria()') is null then
    raise exception 'Falta fn_tocar_auditoria() — ejecutar primero 2026-07-17_mantenciones_etapa2a5.sql';
  end if;

  if to_regprocedure('public.fn_normalizar_codigo()') is null then
    raise exception 'Falta fn_normalizar_codigo() — ejecutar primero 2026-07-17_mantenciones_etapa2a5.sql';
  end if;

  if to_regclass('public.faenas') is null then
    raise exception 'Falta la tabla faenas — ejecutar primero 2026-07-17_mantenciones_etapa2a5.sql';
  end if;
end $$;

-- ── 1. fn_normalizar_nombre_bodega() — NUEVA, no duplica fn_normalizar_codigo().
--       Esa función fuerza mayúsculas (correcto para códigos); esta solo
--       recorta espacios, preservando la capitalización natural de un
--       nombre de catálogo (ej. "Eléctrico", "Fluke"). Sin esto, "Fluke "
--       y "Fluke" serían duplicados que el índice lower() no atraparía. ──
create or replace function fn_normalizar_nombre_bodega()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.nombre := trim(new.nombre);
  return new;
end;
$$;

-- ── 2. bodega_categorias ──
create table if not exists bodega_categorias (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  tipo_recurso    text not null,
  descripcion     text,
  icono           text,
  color           text,
  activo          boolean not null default true,
  orden           int not null default 0 check (orden >= 0),
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz,

  check (trim(nombre) <> ''),
  check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
  constraint bodega_categorias_tipo_recurso_check
    check (tipo_recurso in ('equipo','herramienta','insumo'))
);

-- Unicidad sin distinguir mayúsculas, DENTRO del mismo tipo_recurso — permite
-- "Eléctrico|equipo" y "Eléctrico|herramienta" a la vez, pero no duplicados
-- del mismo tipo_recurso.
create unique index if not exists uq_bodega_categorias_tipo_nombre
  on bodega_categorias (tipo_recurso, lower(nombre));

create index if not exists idx_bodega_categorias_tipo_recurso on bodega_categorias(tipo_recurso);
create index if not exists idx_bodega_categorias_activo       on bodega_categorias(activo);

drop trigger if exists trg_normalizar_nombre_bodega_categorias on bodega_categorias;
create trigger trg_normalizar_nombre_bodega_categorias
  before insert or update on bodega_categorias
  for each row execute function fn_normalizar_nombre_bodega();

drop trigger if exists trg_auditoria_bodega_categorias on bodega_categorias;
create trigger trg_auditoria_bodega_categorias
  before update on bodega_categorias
  for each row execute function fn_tocar_auditoria();

-- ── 3. bodega_marcas ──
-- Sin "pais_origen": se evaluó en el diseño previo, pero no quedó
-- confirmada en el ajuste final — se deja fuera de esta migración.
create table if not exists bodega_marcas (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  descripcion     text,
  activo          boolean not null default true,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz,

  check (trim(nombre) <> '')
);

create unique index if not exists uq_bodega_marcas_nombre on bodega_marcas (lower(nombre));
create index if not exists idx_bodega_marcas_activo       on bodega_marcas(activo);

drop trigger if exists trg_normalizar_nombre_bodega_marcas on bodega_marcas;
create trigger trg_normalizar_nombre_bodega_marcas
  before insert or update on bodega_marcas
  for each row execute function fn_normalizar_nombre_bodega();

drop trigger if exists trg_auditoria_bodega_marcas on bodega_marcas;
create trigger trg_auditoria_bodega_marcas
  before update on bodega_marcas
  for each row execute function fn_tocar_auditoria();

-- ── 4. bodega_ubicaciones ──
create table if not exists bodega_ubicaciones (
  id              uuid primary key default gen_random_uuid(),
  codigo          text not null,
  nombre          text not null,
  tipo_ubicacion  text not null,
  faena_id        uuid references faenas(id),
  descripcion     text,
  activo          boolean not null default true,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz,

  check (trim(codigo) <> ''),
  check (trim(nombre) <> ''),
  constraint bodega_ubicaciones_tipo_check
    check (tipo_ubicacion in ('bodega','laboratorio','vehiculo','faena','tecnico','otro')),
  -- Si es faena, faena_id es obligatorio; si no, debe quedar nulo (ambas
  -- direcciones a la vez, vía equivalencia lógica).
  constraint bodega_ubicaciones_faena_check
    check ((tipo_ubicacion = 'faena') = (faena_id is not null))
);

create unique index if not exists uq_bodega_ubicaciones_codigo  on bodega_ubicaciones (lower(codigo));
create unique index if not exists uq_bodega_ubicaciones_nombre  on bodega_ubicaciones (lower(nombre));
-- Una faena no puede tener dos filas de ubicación distintas apuntándole.
create unique index if not exists uq_bodega_ubicaciones_faena
  on bodega_ubicaciones (faena_id) where tipo_ubicacion = 'faena';

create index if not exists idx_bodega_ubicaciones_tipo   on bodega_ubicaciones(tipo_ubicacion);
create index if not exists idx_bodega_ubicaciones_activo on bodega_ubicaciones(activo);

-- codigo se normaliza en mayúsculas igual que en clientes/faenas/areas/equipos
-- (reutiliza fn_normalizar_codigo(), no se duplica); nombre solo se recorta.
drop trigger if exists trg_normalizar_codigo_bodega_ubicaciones on bodega_ubicaciones;
create trigger trg_normalizar_codigo_bodega_ubicaciones
  before insert or update on bodega_ubicaciones
  for each row execute function fn_normalizar_codigo();

drop trigger if exists trg_normalizar_nombre_bodega_ubicaciones on bodega_ubicaciones;
create trigger trg_normalizar_nombre_bodega_ubicaciones
  before insert or update on bodega_ubicaciones
  for each row execute function fn_normalizar_nombre_bodega();

drop trigger if exists trg_auditoria_bodega_ubicaciones on bodega_ubicaciones;
create trigger trg_auditoria_bodega_ubicaciones
  before update on bodega_ubicaciones
  for each row execute function fn_tocar_auditoria();

-- ── 5. RLS — lectura abierta a cualquier autenticado (mismo criterio que
--       tipos_evento_mantencion/tipos_mantencion: son catálogos sin datos
--       sensibles); escritura solo admin/bodega; sin DELETE en ningún rol
--       (soft-delete vía "activo" únicamente).
--
--       DROP POLICY IF EXISTS + CREATE POLICY en cada una para que la
--       migración completa sea idempotente (segura de reejecutar).
--
--       RLS no sustituye los privilegios de PostgreSQL: sin el GRANT de
--       tabla correspondiente, "authenticated" no podría ejecutar la
--       sentencia aunque la política de fila lo permitiera. Se otorgan
--       explícitamente SELECT/INSERT/UPDATE (nunca DELETE). ──
alter table bodega_categorias  enable row level security;
alter table bodega_marcas      enable row level security;
alter table bodega_ubicaciones enable row level security;

grant select, insert, update on bodega_categorias  to authenticated;
grant select, insert, update on bodega_marcas      to authenticated;
grant select, insert, update on bodega_ubicaciones to authenticated;

drop policy if exists "bodega_categorias_select" on bodega_categorias;
create policy "bodega_categorias_select" on bodega_categorias
  for select using (auth.uid() is not null);
drop policy if exists "bodega_categorias_insert" on bodega_categorias;
create policy "bodega_categorias_insert" on bodega_categorias
  for insert with check (es_admin() or tiene_rol('bodega'));
drop policy if exists "bodega_categorias_update" on bodega_categorias;
create policy "bodega_categorias_update" on bodega_categorias
  for update using (es_admin() or tiene_rol('bodega'));

drop policy if exists "bodega_marcas_select" on bodega_marcas;
create policy "bodega_marcas_select" on bodega_marcas
  for select using (auth.uid() is not null);
drop policy if exists "bodega_marcas_insert" on bodega_marcas;
create policy "bodega_marcas_insert" on bodega_marcas
  for insert with check (es_admin() or tiene_rol('bodega'));
drop policy if exists "bodega_marcas_update" on bodega_marcas;
create policy "bodega_marcas_update" on bodega_marcas
  for update using (es_admin() or tiene_rol('bodega'));

drop policy if exists "bodega_ubicaciones_select" on bodega_ubicaciones;
create policy "bodega_ubicaciones_select" on bodega_ubicaciones
  for select using (auth.uid() is not null);
drop policy if exists "bodega_ubicaciones_insert" on bodega_ubicaciones;
create policy "bodega_ubicaciones_insert" on bodega_ubicaciones
  for insert with check (es_admin() or tiene_rol('bodega'));
drop policy if exists "bodega_ubicaciones_update" on bodega_ubicaciones;
create policy "bodega_ubicaciones_update" on bodega_ubicaciones
  for update using (es_admin() or tiene_rol('bodega'));

-- ── 6. Semillas mínimas (idempotente — on conflict do nothing) ──
insert into bodega_categorias (nombre, tipo_recurso, orden) values
  ('Eléctrico',  'equipo',      1),
  ('Mecánico',   'equipo',      2),
  ('Térmico',    'equipo',      3),
  ('Eléctrico',  'herramienta', 1),
  ('Manual',     'herramienta', 2),
  ('Consumible', 'insumo',      1),
  ('Repuesto',   'insumo',      2)
on conflict do nothing;

insert into bodega_marcas (nombre) values
  ('Fluke'), ('Megger'), ('FLIR'), ('SKF')
on conflict do nothing;

-- Solo ubicaciones genéricas — las de tipo 'faena' se crean después,
-- contra faenas reales ya existentes, no se inventan aquí.
insert into bodega_ubicaciones (codigo, nombre, tipo_ubicacion) values
  ('BOD-01', 'Bodega Central', 'bodega'),
  ('LAB-01', 'Laboratorio',    'laboratorio'),
  ('TEC-01', 'Técnico',        'tecnico')
on conflict do nothing;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Tablas y columnas creadas:
-- select table_name, column_name, data_type
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name in ('bodega_categorias','bodega_marcas','bodega_ubicaciones')
--   order by table_name, ordinal_position;
--
-- 2) Restricciones (CHECK, unique):
-- select conrelid::regclass as tabla, conname, pg_get_constraintdef(oid)
--   from pg_constraint
--   where conrelid::regclass::text in ('bodega_categorias','bodega_marcas','bodega_ubicaciones')
--   order by tabla, conname;
--
-- 3) Índices creados:
-- select tablename, indexname from pg_indexes
--   where tablename in ('bodega_categorias','bodega_marcas','bodega_ubicaciones')
--   order by tablename, indexname;
--
-- 4) RLS habilitado + políticas + privilegios de tabla:
-- select relname, relrowsecurity from pg_class
--   where relname in ('bodega_categorias','bodega_marcas','bodega_ubicaciones');
-- select tablename, policyname, cmd from pg_policies
--   where tablename in ('bodega_categorias','bodega_marcas','bodega_ubicaciones')
--   order by tablename, policyname;
-- select table_name, grantee, privilege_type from information_schema.role_table_grants
--   where table_schema = 'public' and grantee = 'authenticated'
--     and table_name in ('bodega_categorias','bodega_marcas','bodega_ubicaciones')
--   order by table_name, privilege_type;
-- -- Debe mostrar SELECT/INSERT/UPDATE para las 3 tablas — nunca DELETE.
--
-- 5) Prueba de duplicados (debe fallar / no insertar nada nuevo):
-- insert into bodega_marcas (nombre) values ('FLUKE') on conflict do nothing;
-- select count(*) from bodega_marcas where lower(nombre) = 'fluke'; -- debe dar 1
--
-- 6) Semillas cargadas:
-- select tipo_recurso, nombre from bodega_categorias order by tipo_recurso, orden;
-- select nombre from bodega_marcas order by nombre;
-- select codigo, nombre, tipo_ubicacion from bodega_ubicaciones order by codigo;
--
-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- (orden: políticas → privilegios → tablas → función; cada DROP TABLE ya
-- elimina en cascada sus propios triggers e índices, pero las políticas
-- y los GRANT deben quitarse explícitamente antes, por prolijidad y para
-- dejar rastro claro de qué se está deshaciendo)
-- ═══════════════════════════════════════════════════════════════
-- drop policy if exists "bodega_categorias_select" on public.bodega_categorias;
-- drop policy if exists "bodega_categorias_insert" on public.bodega_categorias;
-- drop policy if exists "bodega_categorias_update" on public.bodega_categorias;
-- drop policy if exists "bodega_marcas_select" on public.bodega_marcas;
-- drop policy if exists "bodega_marcas_insert" on public.bodega_marcas;
-- drop policy if exists "bodega_marcas_update" on public.bodega_marcas;
-- drop policy if exists "bodega_ubicaciones_select" on public.bodega_ubicaciones;
-- drop policy if exists "bodega_ubicaciones_insert" on public.bodega_ubicaciones;
-- drop policy if exists "bodega_ubicaciones_update" on public.bodega_ubicaciones;
--
-- revoke select, insert, update on public.bodega_categorias  from authenticated;
-- revoke select, insert, update on public.bodega_marcas      from authenticated;
-- revoke select, insert, update on public.bodega_ubicaciones from authenticated;
--
-- drop table if exists public.bodega_ubicaciones;
-- drop table if exists public.bodega_marcas;
-- drop table if exists public.bodega_categorias;
-- drop function if exists public.fn_normalizar_nombre_bodega();
