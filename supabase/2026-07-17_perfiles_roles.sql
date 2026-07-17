-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Paso 1B: Perfiles y Roles
-- Ejecutar manualmente en el SQL Editor de Supabase.
-- No modifica protocolos_ayca, herramientas ni herramientas_movimientos.
-- ═══════════════════════════════════════════════════════════════

-- ── Tabla de perfiles (1 fila por usuario de auth.users) ──
create table if not exists perfiles_ayca (
  id         uuid primary key references auth.users(id) on delete cascade,
  nombre     text,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

-- ── Tabla puente de roles (N filas por usuario → soporta multi-rol) ──
create table if not exists usuario_roles (
  id         bigint generated always as identity primary key,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  rol        text not null check (rol in ('tecnico','supervisor','planificador','bodega','gerencia','administrador')),
  creado_en  timestamptz not null default now(),
  unique (usuario_id, rol)
);

alter table perfiles_ayca  enable row level security;
alter table usuario_roles  enable row level security;

-- ── Funciones auxiliares (SECURITY DEFINER: evitan recursión de RLS) ──
create or replace function tiene_rol(rol_buscado text) returns boolean
  security definer set search_path = public
  language sql stable as $$
    select exists(
      select 1 from usuario_roles
      where usuario_id = auth.uid() and rol = rol_buscado
    )
  $$;

create or replace function es_admin() returns boolean
  language sql stable as $$ select tiene_rol('administrador') $$;

-- ── Políticas RLS: perfiles_ayca ──
create policy "perfiles_select_propio_o_admin" on perfiles_ayca
  for select using (auth.uid() = id or es_admin());

create policy "perfiles_update_propio_o_admin" on perfiles_ayca
  for update using (auth.uid() = id or es_admin());

create policy "perfiles_insert_admin" on perfiles_ayca
  for insert with check (es_admin());

create policy "perfiles_delete_admin" on perfiles_ayca
  for delete using (es_admin());

-- ── Políticas RLS: usuario_roles ──
create policy "roles_select_propio_o_admin" on usuario_roles
  for select using (auth.uid() = usuario_id or es_admin());

create policy "roles_insert_admin" on usuario_roles
  for insert with check (es_admin());

create policy "roles_update_admin" on usuario_roles
  for update using (es_admin());

create policy "roles_delete_admin" on usuario_roles
  for delete using (es_admin());

-- ═══════════════════════════════════════════════════════════════
-- BOOTSTRAP — asignar el primer administrador para no quedar bloqueado.
-- Reemplaza 'correo@ayca.cl' por el correo real de tu usuario ya
-- registrado en Supabase Auth, y descomenta las dos sentencias.
-- ═══════════════════════════════════════════════════════════════

insert into perfiles_ayca (id, nombre)
select id, 'Daniel Jimenez'
from auth.users
where email = 'djimenez@ayca.cl'
on conflict (id) do nothing;

insert into usuario_roles (usuario_id, rol)
select id, 'administrador'
from auth.users
where email = 'djimenez@ayca.cl'
on conflict (usuario_id, rol) do nothing;