-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.03
-- Personal del evento — requerido vs. asignado
--
-- PROPÓSITO:
-- Crear las dos tablas que reemplazan, para el flujo multiequipo, el rol
-- que "mantencion_personal" cumple en una mantención suelta (2C):
--   - evento_personal_requerido: cuántas personas de qué perfil hacen
--     falta para TODO el evento (consolidado de las plantillas de sus
--     equipos), con su propio ciclo de aprobación.
--   - evento_personal_asignado: qué persona real cubre (o no) cada
--     necesidad, con vínculo OPCIONAL hacia la línea de requerimiento
--     que cubre.
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-17_perfiles_roles.sql                    (es_admin(), tiene_rol())
--   - 2026-07-17_mantenciones_etapa2a5.sql              (fn_tocar_auditoria())
--   - 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql (eventos_mantencion)
--
-- NO crea todavía: evento_personal_origen (2D-05), evento_recursos ni su
-- propia trazabilidad (2D-04/2D-05), ni las funciones de consolidación/
-- alta/baja/aprobación (2D-06/2D-07). Esta migración solo deja la
-- estructura de datos y sus validaciones de integridad; nada aquí
-- consolida todavía plantillas hacia estas tablas.
--
-- RLS: ambas tablas quedan con row level security HABILITADO y SIN
-- políticas — deny-all por defecto, igual que eventos_mantencion (2D-01)
-- y por el mismo motivo: las políticas funcionales llegan recién en
-- 2D-09, cuando ya exista el resto del modelo del que dependen.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regprocedure('public.es_admin()') is null then
    raise exception 'Falta es_admin() — ejecutar primero 2026-07-17_perfiles_roles.sql';
  end if;

  if to_regprocedure('public.fn_tocar_auditoria()') is null then
    raise exception 'Falta fn_tocar_auditoria() — ejecutar primero 2026-07-17_mantenciones_etapa2a5.sql';
  end if;

  if to_regclass('public.eventos_mantencion') is null then
    raise exception 'Falta la tabla eventos_mantencion — ejecutar primero 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql';
  end if;
end $$;

-- ── 1. evento_personal_requerido ──
-- Vocabulario origen/estado_fila/motivo_modificacion idéntico al ya usado
-- en mantencion_personal (2C), para que 2D-06/2D-07 puedan reutilizar el
-- mismo patrón de alta/baja/modificación sin inventar uno nuevo.
--
-- "origen" solo admite 'plantilla'/'manual' por ahora — igual que
-- mantencion_personal en 2C. 'excel' se agregará (ALTER TABLE ... DROP
-- CONSTRAINT / ADD CONSTRAINT) cuando exista la sub-etapa de importación
-- (ETAPA 2D.2) — no tiene sentido permitir un valor que ninguna función
-- puede producir todavía.
create table if not exists evento_personal_requerido (
  id                  uuid primary key default gen_random_uuid(),
  evento_mantencion_id uuid not null references public.eventos_mantencion(id) on delete cascade,
  perfil              text not null,
  especialidad        text,
  cantidad_sugerida   numeric not null,
  cantidad_aprobada   numeric,
  origen              text not null check (origen in ('plantilla','manual')),
  estado_fila         text not null default 'sugerido' check (estado_fila in ('sugerido','agregado','eliminado','modificado')),
  motivo_modificacion text,
  aprobado_por        uuid references auth.users(id),
  aprobado_en         timestamptz,
  creado_por          uuid references auth.users(id),
  creado_en           timestamptz not null default now(),
  actualizado_por     uuid references auth.users(id),
  actualizado_en      timestamptz,

  check (cantidad_sugerida >= 0),
  check (cantidad_aprobada is null or cantidad_aprobada >= 0),
  -- Mismo criterio que las 4 tablas Snapshot de 2C: un cambio de estado
  -- que retira o modifica una línea debe quedar explicado.
  check (estado_fila not in ('eliminado','modificado') or motivo_modificacion is not null)
);

create index if not exists idx_evento_personal_requerido_evento
  on evento_personal_requerido(evento_mantencion_id);

create index if not exists idx_evento_personal_requerido_evento_estado
  on evento_personal_requerido(evento_mantencion_id, estado_fila);

alter table evento_personal_requerido enable row level security;

create trigger trg_auditoria_evento_personal_requerido
  before update on evento_personal_requerido
  for each row execute function fn_tocar_auditoria();

-- ── 2. evento_personal_asignado ──
create table if not exists evento_personal_asignado (
  id                            uuid primary key default gen_random_uuid(),
  evento_mantencion_id          uuid not null references public.eventos_mantencion(id) on delete cascade,
  evento_personal_requerido_id  uuid references public.evento_personal_requerido(id) on delete set null,
  usuario_id                    uuid not null references auth.users(id),
  perfil                        text not null,
  especialidad                  text,
  estado_asignacion             text not null default 'propuesto'
                                   check (estado_asignacion in ('propuesto','confirmado','en_terreno','liberado')),
  fecha_desde                   timestamptz,
  fecha_hasta                   timestamptz,
  observaciones                 text,
  creado_por                    uuid references auth.users(id),
  creado_en                     timestamptz not null default now(),
  actualizado_por               uuid references auth.users(id),
  actualizado_en                timestamptz,

  check (fecha_hasta is null or fecha_desde is null or fecha_hasta >= fecha_desde)
);

create index if not exists idx_evento_personal_asignado_evento
  on evento_personal_asignado(evento_mantencion_id);

create index if not exists idx_evento_personal_asignado_usuario
  on evento_personal_asignado(usuario_id);

create index if not exists idx_evento_personal_asignado_requerido
  on evento_personal_asignado(evento_personal_requerido_id);

-- Un mismo usuario no puede tener dos asignaciones activas en el mismo
-- evento; "liberado" queda fuera del índice a propósito — una asignación
-- ya liberada no bloquea que esa persona vuelva a asignarse más tarde.
create unique index if not exists uq_evento_personal_asignado_usuario_activo
  on evento_personal_asignado (evento_mantencion_id, usuario_id)
  where estado_asignacion <> 'liberado';

alter table evento_personal_asignado enable row level security;

create trigger trg_auditoria_evento_personal_asignado
  before update on evento_personal_asignado
  for each row execute function fn_tocar_auditoria();

-- ── 3. Trigger: evento_personal_requerido_id (si viene informado) debe
--       pertenecer al MISMO evento, y no puede apuntar a una línea
--       eliminada ──
create or replace function fn_validar_evento_personal_asignado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requerido_evento_id  uuid;
  v_requerido_estado_fila text;
begin
  if NEW.evento_personal_requerido_id is not null then
    select epr.evento_mantencion_id, epr.estado_fila
      into v_requerido_evento_id, v_requerido_estado_fila
      from evento_personal_requerido epr
      where epr.id = NEW.evento_personal_requerido_id;

    if v_requerido_evento_id is null then
      raise exception 'La línea de personal requerido indicada (%) no existe.', NEW.evento_personal_requerido_id;
    end if;

    if v_requerido_evento_id <> NEW.evento_mantencion_id then
      raise exception 'La línea de personal requerido indicada pertenece a otro evento.';
    end if;

    if v_requerido_estado_fila = 'eliminado' then
      raise exception 'No se puede asignar personal a una línea de personal requerido que fue eliminada.';
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_validar_evento_personal_asignado on evento_personal_asignado;
create trigger trg_validar_evento_personal_asignado
  before insert or update on evento_personal_asignado
  for each row execute function fn_validar_evento_personal_asignado();

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Tablas y columnas:
-- select table_name, column_name, data_type, is_nullable
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name in ('evento_personal_requerido', 'evento_personal_asignado')
--   order by table_name, ordinal_position;
--
-- 2) Restricciones:
-- select conrelid::regclass as tabla, conname, contype
--   from pg_constraint
--   where conrelid in ('public.evento_personal_requerido'::regclass, 'public.evento_personal_asignado'::regclass)
--   order by tabla, conname;
--
-- 3) Índices (incluye el único parcial):
-- select tablename, indexname, indexdef
--   from pg_indexes
--   where tablename in ('evento_personal_requerido', 'evento_personal_asignado');
--
-- 4) RLS activo y sin políticas (debe devolver 0 filas):
-- select relname, relrowsecurity from pg_class
--   where oid in ('public.evento_personal_requerido'::regclass, 'public.evento_personal_asignado'::regclass);
-- select tablename, policyname from pg_policies
--   where tablename in ('evento_personal_requerido', 'evento_personal_asignado');
--
-- 5) Triggers activos:
-- select tgrelid::regclass as tabla, tgname
--   from pg_trigger
--   where tgrelid in ('public.evento_personal_requerido'::regclass, 'public.evento_personal_asignado'::regclass)
--   order by tabla, tgname;
--
-- 6) Pruebas completas (con datos reales, dentro de una transacción que
--    termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_personal_etapa2d03.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- (orden inverso: trigger de validación → asignado → requerido)
-- ═══════════════════════════════════════════════════════════════
-- drop trigger if exists trg_validar_evento_personal_asignado on public.evento_personal_asignado;
-- drop function if exists public.fn_validar_evento_personal_asignado();
-- drop trigger if exists trg_auditoria_evento_personal_asignado on public.evento_personal_asignado;
-- drop table if exists public.evento_personal_asignado;
-- drop trigger if exists trg_auditoria_evento_personal_requerido on public.evento_personal_requerido;
-- drop table if exists public.evento_personal_requerido;
