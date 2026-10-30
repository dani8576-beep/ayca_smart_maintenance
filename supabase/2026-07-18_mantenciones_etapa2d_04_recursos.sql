-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.04
-- Recursos del evento — evento_recursos
--
-- PROPÓSITO:
-- Crear la lista única de recursos (herramientas, instrumentos, equipos
-- de apoyo, EPP, repuestos, consumibles y materiales) para TODO el
-- evento multiequipo, análoga a "mantencion_recursos" (2C) pero a nivel
-- de evento en vez de por equipo — mismo criterio ya aplicado en 2D-03
-- para personal.
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-17_perfiles_roles.sql                    (es_admin(), tiene_rol())
--   - 2026-07-17_mantenciones_etapa2a5.sql              (fn_tocar_auditoria())
--   - 2026-07-17_mantenciones_etapa2a.sql               (herramientas ya existente,
--                                                          insumos_bodega)
--   - 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql (eventos_mantencion)
--
-- NO crea todavía: evento_recursos_origen (2D-05), ni las funciones de
-- consolidación/alta/baja/aprobación (2D-06/2D-07). Esta migración solo
-- deja la estructura de datos y sus validaciones de integridad.
--
-- RLS: HABILITADO y SIN políticas — deny-all por defecto, igual que
-- eventos_mantencion (2D-01) y evento_personal_* (2D-03). Las políticas
-- funcionales llegan en 2D-09.
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

  if to_regclass('public.herramientas') is null then
    raise exception 'Falta la tabla herramientas — debe existir de una fase previa (módulo Bodega).';
  end if;

  if to_regclass('public.insumos_bodega') is null then
    raise exception 'Falta la tabla insumos_bodega — ejecutar primero 2026-07-17_mantenciones_etapa2a.sql';
  end if;
end $$;

-- ── 1. evento_recursos ──
-- Vocabulario categoria_recurso/origen/estado_fila/motivo_modificacion
-- idéntico al ya usado en mantencion_recursos (2C). El CHECK de
-- exclusividad entre herramienta_codigo/insumo_codigo es EL MISMO,
-- textualmente, que el de mantencion_recursos — no una reinterpretación:
-- ata cada categoria_recurso a cuál de los dos códigos debe quedar en
-- null, lo que como efecto garantiza que nunca puedan estar ambos
-- informados a la vez (y permite el recurso genérico con ambos null).
create table if not exists evento_recursos (
  id                   uuid primary key default gen_random_uuid(),
  evento_mantencion_id uuid not null references public.eventos_mantencion(id) on delete cascade,
  categoria_recurso    text not null check (categoria_recurso in
                          ('herramienta','instrumento','equipo_apoyo','epp','repuesto','consumible','material')),
  nombre_generico      text not null,
  herramienta_codigo   text references public.herramientas(codigo),
  insumo_codigo        text references public.insumos_bodega(codigo),
  cantidad_sugerida    numeric not null,
  cantidad_aprobada    numeric,
  origen               text not null check (origen in ('plantilla','manual')),
  estado_fila          text not null default 'sugerido' check (estado_fila in ('sugerido','agregado','eliminado','modificado')),
  motivo_modificacion  text,
  aprobado_por         uuid references auth.users(id),
  aprobado_en          timestamptz,
  creado_por           uuid references auth.users(id),
  creado_en            timestamptz not null default now(),
  actualizado_por      uuid references auth.users(id),
  actualizado_en       timestamptz,

  check (trim(nombre_generico) <> ''),
  check (cantidad_sugerida >= 0),
  check (cantidad_aprobada is null or cantidad_aprobada >= 0),
  -- Mismo CHECK de exclusividad que mantencion_recursos (2C), sin cambios:
  check (
    (categoria_recurso in ('herramienta','instrumento','equipo_apoyo') and insumo_codigo is null)
    or
    (categoria_recurso in ('epp','repuesto','consumible','material') and herramienta_codigo is null)
  ),
  -- Mismo criterio que evento_personal_requerido (2D-03) y las 4 tablas
  -- Snapshot de 2C: retirar o modificar una línea debe quedar explicado.
  check (estado_fila not in ('eliminado','modificado') or motivo_modificacion is not null)
);

create index if not exists idx_evento_recursos_evento
  on evento_recursos(evento_mantencion_id);

create index if not exists idx_evento_recursos_evento_estado
  on evento_recursos(evento_mantencion_id, estado_fila);

create index if not exists idx_evento_recursos_herramienta
  on evento_recursos(herramienta_codigo);

create index if not exists idx_evento_recursos_insumo
  on evento_recursos(insumo_codigo);

-- ── 2. Duplicados vigentes dentro del mismo evento ──
-- Índice único POR EXPRESIÓN (no una columna simple), porque en
-- PostgreSQL un índice único trata cada NULL como distinto de cualquier
-- otro NULL — dos filas genéricas (herramienta_codigo e insumo_codigo
-- ambos null) para el mismo nombre_generico NO chocarían entre sí si
-- se indexaran las columnas tal cual, dejando pasar duplicados exactos
-- del caso más común (recurso sin código todavía asignado).
--
-- Se resuelve normalizando la clave de comparación:
--   - nombre_generico se compara en mayúsculas y sin espacios sobrantes
--     (mismo criterio que fn_normalizar_codigo(), sin modificar la
--     columna real — solo la expresión del índice).
--   - herramienta_codigo/insumo_codigo se combinan con coalesce(...,'')
--     en una sola expresión: como el CHECK de exclusividad de arriba
--     garantiza que como máximo uno de los dos puede estar informado,
--     coalesce(herramienta_codigo, insumo_codigo, '') captura "el código
--     real, si existe, o vacío si el recurso es genérico" sin perder
--     información y sin necesitar dos expresiones coalesce separadas.
-- estado_fila <> 'eliminado' queda en el WHERE parcial: una fila
-- retirada no bloquea volver a agregar el mismo recurso más adelante.
create unique index if not exists uq_evento_recursos_vigente
  on evento_recursos (
    evento_mantencion_id,
    categoria_recurso,
    upper(trim(nombre_generico)),
    coalesce(herramienta_codigo, insumo_codigo, '')
  )
  where estado_fila <> 'eliminado';

alter table evento_recursos enable row level security;

create trigger trg_auditoria_evento_recursos
  before update on evento_recursos
  for each row execute function fn_tocar_auditoria();

-- ── 3. Consistencia categoria_recurso ↔ catálogo real, cuando el
--       catálogo lo permite ──
-- insumos_bodega SÍ tiene una columna "categoria" con CHECK sobre el
-- MISMO vocabulario ('epp','repuesto','consumible','material') que la
-- mitad "consumible" de categoria_recurso (2A) — se puede y se valida
-- aquí: si insumo_codigo viene informado, su categoria real debe
-- coincidir con la categoria_recurso declarada.
--
-- herramientas SÍ tiene una columna "categoria", pero es texto libre sin
-- CHECK (usada por el módulo Bodega preexistente para clasificaciones
-- propias, ej. marca/tipo) — no comparte vocabulario con
-- categoria_recurso ('herramienta'/'instrumento'/'equipo_apoyo'), así
-- que NO es posible validarla de forma confiable todavía. Por eso el
-- enunciado "cuando sea posible con los catálogos actuales" se cumple
-- solo para insumo_codigo — queda documentado aquí, no omitido en
-- silencio.
create or replace function fn_validar_categoria_evento_recursos()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_categoria_insumo text;
begin
  if NEW.insumo_codigo is not null then
    select ib.categoria into v_categoria_insumo
      from insumos_bodega ib
      where ib.codigo = NEW.insumo_codigo;

    if v_categoria_insumo is null then
      raise exception 'El insumo indicado (%) no existe en insumos_bodega.', NEW.insumo_codigo;
    end if;

    if v_categoria_insumo <> NEW.categoria_recurso then
      raise exception 'La categoría real del insumo % (%) no coincide con la categoria_recurso indicada (%).',
        NEW.insumo_codigo, v_categoria_insumo, NEW.categoria_recurso;
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_validar_categoria_evento_recursos on evento_recursos;
create trigger trg_validar_categoria_evento_recursos
  before insert or update on evento_recursos
  for each row execute function fn_validar_categoria_evento_recursos();

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Tabla y columnas:
-- select column_name, data_type, is_nullable
--   from information_schema.columns
--   where table_schema = 'public' and table_name = 'evento_recursos'
--   order by ordinal_position;
--
-- 2) Restricciones:
-- select conname, contype
--   from pg_constraint
--   where conrelid = 'public.evento_recursos'::regclass
--   order by conname;
--
-- 3) Índices (incluye el único por expresión):
-- select indexname, indexdef from pg_indexes where tablename = 'evento_recursos';
--
-- 4) RLS activo y sin políticas (debe devolver 0 filas):
-- select relrowsecurity from pg_class where oid = 'public.evento_recursos'::regclass;
-- select policyname from pg_policies where tablename = 'evento_recursos';
--
-- 5) Triggers activos:
-- select tgname from pg_trigger
--   where tgrelid = 'public.evento_recursos'::regclass and not tgisinternal;
--
-- 6) Pruebas completas (con datos reales, dentro de una transacción que
--    termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_recursos_etapa2d04.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop trigger if exists trg_validar_categoria_evento_recursos on public.evento_recursos;
-- drop function if exists public.fn_validar_categoria_evento_recursos();
-- drop trigger if exists trg_auditoria_evento_recursos on public.evento_recursos;
-- drop index if exists public.uq_evento_recursos_vigente;
-- drop table if exists public.evento_recursos;
