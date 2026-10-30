-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.05
-- Trazabilidad de origen — evento_personal_origen / evento_recursos_origen
--
-- PROPÓSITO:
-- Registrar, por cada equipo (mantención) que aporta a una línea
-- consolidada del evento (evento_personal_requerido / evento_recursos),
-- cuánto aportó y desde qué fila de plantilla — para poder recalcular
-- correctamente la cantidad_sugerida cuando un equipo se agrega o se
-- retira del evento, SIN perder historial y SIN destruir ajustes
-- manuales del supervisor (necesidad ya identificada en el diseño
-- aprobado, ver conversación previa).
--
-- Estas tablas son un LIBRO DE REGISTRO, no una tabla editable: una fila
-- se crea una vez, y su único cambio de estado permitido en el tiempo es
-- "activo" → "retirado" (nunca al revés, y nunca DELETE físico). Por eso
-- NO llevan actualizado_por/actualizado_en genéricos — el propio
-- "retiro" ya queda con su firma (retirado_por/retirado_en/motivo_retiro).
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-17_mantenciones_etapa2a.sql               (plantilla_personal, plantilla_recursos)
--   - 2026-07-17_mantenciones_etapa2b.sql                (mantenciones)
--   - 2026-07-18_mantenciones_etapa2d_03_personal.sql    (evento_personal_requerido)
--   - 2026-07-18_mantenciones_etapa2d_04_recursos.sql    (evento_recursos)
--
-- NO crea todavía las funciones de consolidación (fn_agregar_equipo_evento,
-- etc. — 2D-06) ni las de recálculo al agregar/quitar un equipo (2D-07).
-- Esta migración solo deja la estructura de datos, sus validaciones de
-- integridad, y el bloqueo de mutaciones no permitidas.
--
-- RLS: HABILITADO y SIN políticas — deny-all por defecto, igual que el
-- resto de 2D-01/03/04. Las políticas funcionales llegan en 2D-09.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regclass('public.plantilla_personal') is null then
    raise exception 'Falta la tabla plantilla_personal — ejecutar primero 2026-07-17_mantenciones_etapa2a.sql';
  end if;

  if to_regclass('public.plantilla_recursos') is null then
    raise exception 'Falta la tabla plantilla_recursos — ejecutar primero 2026-07-17_mantenciones_etapa2a.sql';
  end if;

  if to_regclass('public.mantenciones') is null then
    raise exception 'Falta la tabla mantenciones — ejecutar primero 2026-07-17_mantenciones_etapa2b.sql';
  end if;

  if to_regclass('public.evento_personal_requerido') is null then
    raise exception 'Falta la tabla evento_personal_requerido — ejecutar primero 2026-07-18_mantenciones_etapa2d_03_personal.sql';
  end if;

  if to_regclass('public.evento_recursos') is null then
    raise exception 'Falta la tabla evento_recursos — ejecutar primero 2026-07-18_mantenciones_etapa2d_04_recursos.sql';
  end if;
end $$;

-- ── 1. evento_personal_origen ──
-- Las tres FK de identidad (evento_personal_requerido_id, mantencion_id,
-- plantilla_personal_id) usan ON DELETE RESTRICT/NO ACTION a propósito:
-- ninguna de las tres debe poder desaparecer mientras exista un registro
-- de origen que la referencie — perderla rompería el historial que esta
-- tabla existe para preservar.
create table if not exists evento_personal_origen (
  id                            uuid primary key default gen_random_uuid(),
  evento_personal_requerido_id  uuid not null references public.evento_personal_requerido(id),
  mantencion_id                 uuid not null references public.mantenciones(id),
  plantilla_personal_id         uuid not null references public.plantilla_personal(id),
  cantidad_aportada             numeric not null check (cantidad_aportada > 0),
  estado                        text not null default 'activo' check (estado in ('activo','retirado')),
  retirado_por                  uuid references auth.users(id),
  retirado_en                   timestamptz,
  motivo_retiro                 text,
  creado_por                    uuid references auth.users(id),
  creado_en                     timestamptz not null default now(),

  -- estado activo ⇔ campos de retiro null; estado retirado ⇔ los tres informados.
  check (
    (estado = 'activo'    and retirado_por is null     and retirado_en is null     and motivo_retiro is null)
    or
    (estado = 'retirado'  and retirado_por is not null and retirado_en is not null and motivo_retiro is not null)
  )
);

create index if not exists idx_evento_personal_origen_requerido
  on evento_personal_origen(evento_personal_requerido_id);

create index if not exists idx_evento_personal_origen_requerido_estado
  on evento_personal_origen(evento_personal_requerido_id, estado);

create index if not exists idx_evento_personal_origen_mantencion
  on evento_personal_origen(mantencion_id);

create index if not exists idx_evento_personal_origen_plantilla_personal
  on evento_personal_origen(plantilla_personal_id);

-- Impide duplicados ACTIVOS para la misma combinación (línea consolidada
-- + equipo + fila de plantilla). Al quedar fuera del índice todo lo que
-- no sea 'activo', un equipo que se retira y luego se reincorpora crea
-- una fila NUEVA sin chocar con la anterior, ya retirada — exactamente
-- el comportamiento pedido ("no reactivar la antigua").
create unique index if not exists uq_evento_personal_origen_activo
  on evento_personal_origen (evento_personal_requerido_id, mantencion_id, plantilla_personal_id)
  where estado = 'activo';

alter table evento_personal_origen enable row level security;

-- ── 2. Validación cruzada al crear una fila de origen ──
-- (mismo evento entre la mantención y la línea consolidada; la fila de
-- plantilla debe corresponder a la plantilla real de esa mantención)
create or replace function fn_validar_evento_personal_origen()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requerido_evento_id  uuid;
  v_mant_evento_id       uuid;
  v_mant_plantilla_id    uuid;
  v_pp_plantilla_id      uuid;
begin
  select evento_mantencion_id into v_requerido_evento_id
    from evento_personal_requerido where id = NEW.evento_personal_requerido_id;
  if not found then
    raise exception 'La línea de personal requerido indicada (%) no existe.', NEW.evento_personal_requerido_id;
  end if;

  select evento_mantencion_id, plantilla_id into v_mant_evento_id, v_mant_plantilla_id
    from mantenciones where id = NEW.mantencion_id;
  if not found then
    raise exception 'La mantención indicada (%) no existe.', NEW.mantencion_id;
  end if;

  if v_mant_evento_id is null then
    raise exception 'La mantención indicada (%) no pertenece a ningún evento — no puede aportar a una consolidación de evento.', NEW.mantencion_id;
  end if;

  if v_mant_evento_id <> v_requerido_evento_id then
    raise exception 'La mantención indicada pertenece a un evento distinto al de la línea de personal requerido.';
  end if;

  select plantilla_id into v_pp_plantilla_id
    from plantilla_personal where id = NEW.plantilla_personal_id;
  if not found then
    raise exception 'La fila de plantilla_personal indicada (%) no existe.', NEW.plantilla_personal_id;
  end if;

  if v_pp_plantilla_id <> v_mant_plantilla_id then
    raise exception 'La fila de plantilla_personal indicada no corresponde a la plantilla de la mantención.';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_validar_evento_personal_origen on evento_personal_origen;
create trigger trg_validar_evento_personal_origen
  before insert on evento_personal_origen
  for each row execute function fn_validar_evento_personal_origen();

-- ── 3. Inmutabilidad + transición de estado permitida ──
-- Todo dato de identidad/cantidad es inmutable después de creado. El
-- único cambio permitido es 'activo' → 'retirado'; el sentido inverso
-- está prohibido explícitamente (si el equipo vuelve, se crea una fila
-- nueva — ver el índice único parcial del punto 1).
create or replace function fn_bloquear_cambios_evento_personal_origen()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if NEW.evento_personal_requerido_id <> OLD.evento_personal_requerido_id
     or NEW.mantencion_id <> OLD.mantencion_id
     or NEW.plantilla_personal_id <> OLD.plantilla_personal_id
     or NEW.cantidad_aportada <> OLD.cantidad_aportada then
    raise exception 'No se pueden modificar los datos de una fila de evento_personal_origen ya creada — solo se puede retirarla.';
  end if;

  if OLD.estado = 'retirado' and NEW.estado = 'activo' then
    raise exception 'No se puede reactivar una fila de evento_personal_origen ya retirada — cree una fila nueva si el equipo se reincorpora.';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_bloquear_cambios_evento_personal_origen on evento_personal_origen;
create trigger trg_bloquear_cambios_evento_personal_origen
  before update on evento_personal_origen
  for each row execute function fn_bloquear_cambios_evento_personal_origen();

-- ── 4. Prohibir DELETE físico (para cualquier rol, sin excepción) ──
create or replace function fn_bloquear_delete_evento_personal_origen()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'No se puede eliminar físicamente una fila de evento_personal_origen — retírela (estado = ''retirado'') para conservar el historial.';
end;
$$;

drop trigger if exists trg_bloquear_delete_evento_personal_origen on evento_personal_origen;
create trigger trg_bloquear_delete_evento_personal_origen
  before delete on evento_personal_origen
  for each row execute function fn_bloquear_delete_evento_personal_origen();


-- ═══════════════════════════════════════════════════════════════
-- evento_recursos_origen — misma estructura y mismas reglas que
-- evento_personal_origen, aplicadas a evento_recursos en vez de
-- evento_personal_requerido.
-- ═══════════════════════════════════════════════════════════════

-- ── 5. evento_recursos_origen ──
create table if not exists evento_recursos_origen (
  id                     uuid primary key default gen_random_uuid(),
  evento_recursos_id     uuid not null references public.evento_recursos(id),
  mantencion_id          uuid not null references public.mantenciones(id),
  plantilla_recurso_id   uuid not null references public.plantilla_recursos(id),
  cantidad_aportada      numeric not null check (cantidad_aportada > 0),
  estado                 text not null default 'activo' check (estado in ('activo','retirado')),
  retirado_por           uuid references auth.users(id),
  retirado_en            timestamptz,
  motivo_retiro          text,
  creado_por             uuid references auth.users(id),
  creado_en              timestamptz not null default now(),

  check (
    (estado = 'activo'    and retirado_por is null     and retirado_en is null     and motivo_retiro is null)
    or
    (estado = 'retirado'  and retirado_por is not null and retirado_en is not null and motivo_retiro is not null)
  )
);

create index if not exists idx_evento_recursos_origen_recurso
  on evento_recursos_origen(evento_recursos_id);

create index if not exists idx_evento_recursos_origen_recurso_estado
  on evento_recursos_origen(evento_recursos_id, estado);

create index if not exists idx_evento_recursos_origen_mantencion
  on evento_recursos_origen(mantencion_id);

create index if not exists idx_evento_recursos_origen_plantilla_recurso
  on evento_recursos_origen(plantilla_recurso_id);

create unique index if not exists uq_evento_recursos_origen_activo
  on evento_recursos_origen (evento_recursos_id, mantencion_id, plantilla_recurso_id)
  where estado = 'activo';

alter table evento_recursos_origen enable row level security;

-- ── 6. Validación cruzada al crear una fila de origen ──
create or replace function fn_validar_evento_recursos_origen()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recurso_evento_id uuid;
  v_mant_evento_id    uuid;
  v_mant_plantilla_id uuid;
  v_pr_plantilla_id   uuid;
begin
  select evento_mantencion_id into v_recurso_evento_id
    from evento_recursos where id = NEW.evento_recursos_id;
  if not found then
    raise exception 'La línea de recursos indicada (%) no existe.', NEW.evento_recursos_id;
  end if;

  select evento_mantencion_id, plantilla_id into v_mant_evento_id, v_mant_plantilla_id
    from mantenciones where id = NEW.mantencion_id;
  if not found then
    raise exception 'La mantención indicada (%) no existe.', NEW.mantencion_id;
  end if;

  if v_mant_evento_id is null then
    raise exception 'La mantención indicada (%) no pertenece a ningún evento — no puede aportar a una consolidación de evento.', NEW.mantencion_id;
  end if;

  if v_mant_evento_id <> v_recurso_evento_id then
    raise exception 'La mantención indicada pertenece a un evento distinto al de la línea de recursos.';
  end if;

  select plantilla_id into v_pr_plantilla_id
    from plantilla_recursos where id = NEW.plantilla_recurso_id;
  if not found then
    raise exception 'La fila de plantilla_recursos indicada (%) no existe.', NEW.plantilla_recurso_id;
  end if;

  if v_pr_plantilla_id <> v_mant_plantilla_id then
    raise exception 'La fila de plantilla_recursos indicada no corresponde a la plantilla de la mantención.';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_validar_evento_recursos_origen on evento_recursos_origen;
create trigger trg_validar_evento_recursos_origen
  before insert on evento_recursos_origen
  for each row execute function fn_validar_evento_recursos_origen();

-- ── 7. Inmutabilidad + transición de estado permitida ──
create or replace function fn_bloquear_cambios_evento_recursos_origen()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if NEW.evento_recursos_id <> OLD.evento_recursos_id
     or NEW.mantencion_id <> OLD.mantencion_id
     or NEW.plantilla_recurso_id <> OLD.plantilla_recurso_id
     or NEW.cantidad_aportada <> OLD.cantidad_aportada then
    raise exception 'No se pueden modificar los datos de una fila de evento_recursos_origen ya creada — solo se puede retirarla.';
  end if;

  if OLD.estado = 'retirado' and NEW.estado = 'activo' then
    raise exception 'No se puede reactivar una fila de evento_recursos_origen ya retirada — cree una fila nueva si el equipo se reincorpora.';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_bloquear_cambios_evento_recursos_origen on evento_recursos_origen;
create trigger trg_bloquear_cambios_evento_recursos_origen
  before update on evento_recursos_origen
  for each row execute function fn_bloquear_cambios_evento_recursos_origen();

-- ── 8. Prohibir DELETE físico ──
create or replace function fn_bloquear_delete_evento_recursos_origen()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'No se puede eliminar físicamente una fila de evento_recursos_origen — retírela (estado = ''retirado'') para conservar el historial.';
end;
$$;

drop trigger if exists trg_bloquear_delete_evento_recursos_origen on evento_recursos_origen;
create trigger trg_bloquear_delete_evento_recursos_origen
  before delete on evento_recursos_origen
  for each row execute function fn_bloquear_delete_evento_recursos_origen();

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Tablas y columnas:
-- select table_name, column_name, data_type, is_nullable
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name in ('evento_personal_origen', 'evento_recursos_origen')
--   order by table_name, ordinal_position;
--
-- 2) Restricciones:
-- select conrelid::regclass as tabla, conname, contype
--   from pg_constraint
--   where conrelid in ('public.evento_personal_origen'::regclass, 'public.evento_recursos_origen'::regclass)
--   order by tabla, conname;
--
-- 3) Índices (incluye los únicos parciales "_activo"):
-- select tablename, indexname, indexdef from pg_indexes
--   where tablename in ('evento_personal_origen', 'evento_recursos_origen');
--
-- 4) RLS activo y sin políticas (debe devolver 0 filas):
-- select relname, relrowsecurity from pg_class
--   where oid in ('public.evento_personal_origen'::regclass, 'public.evento_recursos_origen'::regclass);
-- select tablename, policyname from pg_policies
--   where tablename in ('evento_personal_origen', 'evento_recursos_origen');
--
-- 5) Triggers activos (3 por tabla: validar, bloquear cambios, bloquear delete):
-- select tgrelid::regclass as tabla, tgname from pg_trigger
--   where tgrelid in ('public.evento_personal_origen'::regclass, 'public.evento_recursos_origen'::regclass)
--     and not tgisinternal
--   order by tabla, tgname;
--
-- 6) Pruebas completas (con datos reales, dentro de una transacción que
--    termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_trazabilidad_etapa2d05.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop trigger if exists trg_bloquear_delete_evento_recursos_origen on public.evento_recursos_origen;
-- drop function if exists public.fn_bloquear_delete_evento_recursos_origen();
-- drop trigger if exists trg_bloquear_cambios_evento_recursos_origen on public.evento_recursos_origen;
-- drop function if exists public.fn_bloquear_cambios_evento_recursos_origen();
-- drop trigger if exists trg_validar_evento_recursos_origen on public.evento_recursos_origen;
-- drop function if exists public.fn_validar_evento_recursos_origen();
-- drop table if exists public.evento_recursos_origen;
--
-- drop trigger if exists trg_bloquear_delete_evento_personal_origen on public.evento_personal_origen;
-- drop function if exists public.fn_bloquear_delete_evento_personal_origen();
-- drop trigger if exists trg_bloquear_cambios_evento_personal_origen on public.evento_personal_origen;
-- drop function if exists public.fn_bloquear_cambios_evento_personal_origen();
-- drop trigger if exists trg_validar_evento_personal_origen on public.evento_personal_origen;
-- drop function if exists public.fn_validar_evento_personal_origen();
-- drop table if exists public.evento_personal_origen;
