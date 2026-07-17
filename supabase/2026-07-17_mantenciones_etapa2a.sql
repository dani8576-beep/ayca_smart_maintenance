-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2A (v2 — aprobada)
-- Catálogos y Plantillas Maestras de Mantención
-- Ejecutar manualmente en el SQL Editor de Supabase, DESPUÉS de
-- 2026-07-17_perfiles_roles.sql (requiere la función es_admin()).
--
-- NO crea: mantenciones, mantencion_*, solicitudes_bodega,
-- entregas_bodega, devoluciones_bodega, consumos_mantencion,
-- reservas, ni la función de numeración (depende de "mantenciones").
-- NO modifica protocolos_ayca, herramientas, herramientas_movimientos.
-- ═══════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ── 1. tipos_mantencion ──
create table if not exists tipos_mantencion (
  id                 uuid primary key default gen_random_uuid(),
  nombre             text not null unique,
  descripcion        text,
  tipo_equipo_aplica text,
  criticidad_default text check (criticidad_default in ('baja','media','alta','critica')),
  activo             boolean not null default true,
  creado_por         uuid references auth.users(id),
  creado_en          timestamptz not null default now()
);

-- ── 2. plantillas_mantencion ──
create table if not exists plantillas_mantencion (
  id                      uuid primary key default gen_random_uuid(),
  tipo_mantencion_id      uuid not null references tipos_mantencion(id) on delete cascade,
  version                 int not null check (version > 0),
  nombre                  text not null,
  duracion_estimada_horas numeric check (duracion_estimada_horas > 0),
  horas_hombre_estimadas  numeric check (horas_hombre_estimadas > 0),
  criticidad              text check (criticidad in ('baja','media','alta','critica')),
  activa                  boolean not null default true,
  creado_por              uuid references auth.users(id),
  creado_en               timestamptz not null default now(),
  unique (tipo_mantencion_id, version)
);

create unique index if not exists uq_plantilla_activa_por_tipo
  on plantillas_mantencion (tipo_mantencion_id) where activa;

-- ── 3. plantilla_personal ──
create table if not exists plantilla_personal (
  id              uuid primary key default gen_random_uuid(),
  plantilla_id    uuid not null references plantillas_mantencion(id) on delete cascade,
  perfil          text not null,
  cantidad        int not null default 1 check (cantidad > 0),
  especialidad    text,
  obligatorio     boolean not null default true,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz
);

-- ── 4. plantilla_actividades ──
create table if not exists plantilla_actividades (
  id                      uuid primary key default gen_random_uuid(),
  plantilla_id            uuid not null references plantillas_mantencion(id) on delete cascade,
  codigo_actividad        text not null,
  descripcion             text,
  orden                   int not null default 0,
  obligatoria             boolean not null default true,
  depende_de              text,
  duracion_estimada_horas numeric check (duracion_estimada_horas > 0),
  creado_por              uuid references auth.users(id),
  creado_en               timestamptz not null default now(),
  actualizado_por         uuid references auth.users(id),
  actualizado_en          timestamptz
);

-- ── 5. tipos_protocolo (catálogo abierto en vez de CHECK fijo) ──
create table if not exists tipos_protocolo (
  codigo          text primary key,
  nombre          text not null,
  descripcion     text,
  activo          boolean not null default true,
  orden           int not null default 0,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz
);

insert into tipos_protocolo (codigo, nombre, descripcion, orden) values
  ('control_dimensional', 'Control Dimensional',     'Entrehierro y centro magnético',  1),
  ('dielectrico',         'Mediciones Dieléctricas', 'Estator 1, Estator 2 y Rotor',    2),
  ('carbones',            'Carbones',                'Inspección de carbones de motor', 3),
  ('ventilador',          'Ventilador',              'Pruebas PRE/POST de ventilador',  4)
on conflict (codigo) do nothing;

-- ── 6. plantilla_protocolos (tipo_protocolo es FK, no CHECK fijo) ──
create table if not exists plantilla_protocolos (
  id              uuid primary key default gen_random_uuid(),
  plantilla_id    uuid not null references plantillas_mantencion(id) on delete cascade,
  tipo_protocolo  text not null references tipos_protocolo(codigo),
  obligatorio     boolean not null default true,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz
);

-- ── 7. insumos_bodega (EPP, repuestos, consumibles, materiales — stock por cantidad) ──
create table if not exists insumos_bodega (
  codigo          text primary key,
  nombre          text not null,
  categoria       text not null check (categoria in ('epp','repuesto','consumible','material')),
  unidad_medida   text not null,
  stock_actual    numeric not null default 0 check (stock_actual >= 0),
  stock_minimo    numeric default 0 check (stock_minimo >= 0),
  activo          boolean not null default true,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz
);

-- ── 8. plantilla_recursos ──
create table if not exists plantilla_recursos (
  id                 uuid primary key default gen_random_uuid(),
  plantilla_id       uuid not null references plantillas_mantencion(id) on delete cascade,
  categoria_recurso  text not null check (categoria_recurso in
                        ('herramienta','instrumento','equipo_apoyo','epp','repuesto','consumible','material')),
  nombre_generico    text not null,
  herramienta_codigo text references public.herramientas(codigo),
  insumo_codigo      text references insumos_bodega(codigo),
  cantidad_sugerida  numeric not null default 1 check (cantidad_sugerida > 0),
  obligatorio        boolean not null default false,
  creado_por         uuid references auth.users(id),
  creado_en          timestamptz not null default now(),
  actualizado_por    uuid references auth.users(id),
  actualizado_en     timestamptz,
  -- La plantilla sugiere un TIPO de recurso (ej. "Megger de 5 kV", "dinamómetro",
  -- "pie de metro"), NO una unidad física concreta (ej. AYCA-MEG-001) — esa la
  -- selecciona Bodega recién al atender la solicitud. Por eso ambos códigos pueden
  -- quedar en null (recomendación genérica). Cuando sí se fija uno, debe corresponder
  -- a la categoría declarada:
  check (
    (categoria_recurso in ('herramienta','instrumento','equipo_apoyo') and insumo_codigo is null)
    or
    (categoria_recurso in ('epp','repuesto','consumible','material') and herramienta_codigo is null)
  )
);

-- ── 9. correlativos_mantencion (soporte de numeración anual; la función que la usa
--       se crea junto con "mantenciones" en la próxima etapa) ──
create table if not exists correlativos_mantencion (
  anio          int primary key check (anio >= 2020),
  ultimo_numero int not null default 0 check (ultimo_numero >= 0)
);

-- ── Índices ──
create index if not exists idx_plantilla_personal_plantilla    on plantilla_personal(plantilla_id);
create index if not exists idx_plantilla_actividades_plantilla on plantilla_actividades(plantilla_id);
create index if not exists idx_plantilla_protocolos_plantilla  on plantilla_protocolos(plantilla_id);
create index if not exists idx_plantilla_protocolos_tipo       on plantilla_protocolos(tipo_protocolo);
create index if not exists idx_plantilla_recursos_plantilla    on plantilla_recursos(plantilla_id);
create index if not exists idx_plantilla_recursos_herramienta  on plantilla_recursos(herramienta_codigo);
create index if not exists idx_plantilla_recursos_insumo       on plantilla_recursos(insumo_codigo);
create index if not exists idx_insumos_bodega_categoria        on insumos_bodega(categoria);
create index if not exists idx_tipos_protocolo_activo          on tipos_protocolo(activo);

-- ── RLS ──
alter table tipos_mantencion        enable row level security;
alter table plantillas_mantencion   enable row level security;
alter table plantilla_personal      enable row level security;
alter table plantilla_actividades   enable row level security;
alter table tipos_protocolo         enable row level security;
alter table plantilla_protocolos    enable row level security;
alter table insumos_bodega          enable row level security;
alter table plantilla_recursos      enable row level security;
alter table correlativos_mantencion enable row level security;

-- Catálogos: lectura para cualquier usuario autenticado; escritura solo administrador
-- (reutiliza es_admin() de 2026-07-17_perfiles_roles.sql)

create policy "tipos_mantencion_select_auth"   on tipos_mantencion   for select using (auth.uid() is not null);
create policy "tipos_mantencion_insert_admin"  on tipos_mantencion   for insert with check (es_admin());
create policy "tipos_mantencion_update_admin"  on tipos_mantencion   for update using (es_admin());
create policy "tipos_mantencion_delete_admin"  on tipos_mantencion   for delete using (es_admin());

create policy "plantillas_mantencion_select_auth"  on plantillas_mantencion for select using (auth.uid() is not null);
create policy "plantillas_mantencion_insert_admin" on plantillas_mantencion for insert with check (es_admin());
create policy "plantillas_mantencion_update_admin" on plantillas_mantencion for update using (es_admin());
create policy "plantillas_mantencion_delete_admin" on plantillas_mantencion for delete using (es_admin());

create policy "plantilla_personal_select_auth"  on plantilla_personal for select using (auth.uid() is not null);
create policy "plantilla_personal_insert_admin" on plantilla_personal for insert with check (es_admin());
create policy "plantilla_personal_update_admin" on plantilla_personal for update using (es_admin());
create policy "plantilla_personal_delete_admin" on plantilla_personal for delete using (es_admin());

create policy "plantilla_actividades_select_auth"  on plantilla_actividades for select using (auth.uid() is not null);
create policy "plantilla_actividades_insert_admin" on plantilla_actividades for insert with check (es_admin());
create policy "plantilla_actividades_update_admin" on plantilla_actividades for update using (es_admin());
create policy "plantilla_actividades_delete_admin" on plantilla_actividades for delete using (es_admin());

create policy "tipos_protocolo_select_auth"  on tipos_protocolo for select using (auth.uid() is not null);
create policy "tipos_protocolo_insert_admin" on tipos_protocolo for insert with check (es_admin());
create policy "tipos_protocolo_update_admin" on tipos_protocolo for update using (es_admin());
create policy "tipos_protocolo_delete_admin" on tipos_protocolo for delete using (es_admin());

create policy "plantilla_protocolos_select_auth"  on plantilla_protocolos for select using (auth.uid() is not null);
create policy "plantilla_protocolos_insert_admin" on plantilla_protocolos for insert with check (es_admin());
create policy "plantilla_protocolos_update_admin" on plantilla_protocolos for update using (es_admin());
create policy "plantilla_protocolos_delete_admin" on plantilla_protocolos for delete using (es_admin());

create policy "insumos_bodega_select_auth"  on insumos_bodega for select using (auth.uid() is not null);
create policy "insumos_bodega_insert_admin" on insumos_bodega for insert with check (es_admin());
create policy "insumos_bodega_update_admin" on insumos_bodega for update using (es_admin());
create policy "insumos_bodega_delete_admin" on insumos_bodega for delete using (es_admin());

create policy "plantilla_recursos_select_auth"  on plantilla_recursos for select using (auth.uid() is not null);
create policy "plantilla_recursos_insert_admin" on plantilla_recursos for insert with check (es_admin());
create policy "plantilla_recursos_update_admin" on plantilla_recursos for update using (es_admin());
create policy "plantilla_recursos_delete_admin" on plantilla_recursos for delete using (es_admin());

-- Tabla interna de soporte: sin necesidad de lectura general
create policy "correlativos_mantencion_admin_only" on correlativos_mantencion
  for all using (es_admin()) with check (es_admin());
