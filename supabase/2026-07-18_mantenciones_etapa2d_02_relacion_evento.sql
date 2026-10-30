-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.02
-- Relación mantenciones ↔ eventos_mantencion
--
-- PROPÓSITO:
-- Agregar el enlace opcional de cada "mantención" (una fila por equipo)
-- hacia el "evento_mantencion" (parada/mantención general) al que
-- pertenece, si corresponde. Incluye la validación de que el equipo de
-- esa mantención pertenezca al mismo cliente/faena del evento, y el
-- control de qué se puede corregir después de creada la fila:
-- inmutabilidad TOTAL de equipo_id/area_id/evento_mantencion_id para
-- mantenciones que pertenecen a un evento; para mantenciones sueltas,
-- evento_mantencion_id sigue sin poder tocarse nunca por UPDATE directo
-- (esa vinculación es exclusiva de las funciones de 2D-06), pero
-- equipo_id/area_id sí se pueden corregir mientras la mantención sigue
-- en borrador, revalidando la jerarquía completa (ver punto 5).
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-17_mantenciones_etapa2b.sql            (tabla mantenciones,
--                                                       fn_validar_jerarquia_equipo())
--   - 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql
--                                                     (tabla eventos_mantencion)
--
-- NO modifica: fn_crear_mantencion() ni el Snapshot (mantencion_personal,
-- mantencion_actividades, mantencion_protocolos, mantencion_recursos) —
-- eso sigue exactamente igual que en 2B/2C. NO crea fn_crear_evento_mantencion
-- ni fn_agregar_equipo_evento (2D-06). NO modifica las políticas RLS de
-- mantenciones ni de eventos_mantencion (2D-09).
--
-- COMPATIBILIDAD CON MANTENCIONES SUELTAS: "evento_mantencion_id" es
-- nullable. Toda mantención existente y toda mantención futura creada
-- sin evento (flujo 2B/2C actual) queda con este campo en NULL y no se
-- ve afectada por ninguna validación ni índice de esta migración — los
-- triggers nuevos solo actúan cuando evento_mantencion_id no es NULL, o
-- cuando alguien intenta modificar equipo_id/area_id/evento_mantencion_id
-- después de creada la fila (algo que el flujo actual tampoco hace).
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regclass('public.mantenciones') is null then
    raise exception 'Falta la tabla mantenciones — ejecutar primero 2026-07-17_mantenciones_etapa2b.sql';
  end if;

  if to_regclass('public.eventos_mantencion') is null then
    raise exception 'Falta la tabla eventos_mantencion — ejecutar primero 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql';
  end if;

  if to_regprocedure('public.fn_validar_jerarquia_equipo(uuid,uuid,uuid,uuid)') is null then
    raise exception 'Falta fn_validar_jerarquia_equipo() — ejecutar primero 2026-07-17_mantenciones_etapa2b.sql';
  end if;
end $$;

-- ── 1. Columna evento_mantencion_id (nullable, idempotente) ──
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'mantenciones' and column_name = 'evento_mantencion_id'
  ) then
    alter table public.mantenciones
      add column evento_mantencion_id uuid references public.eventos_mantencion(id) on delete restrict;
    raise notice 'Columna "evento_mantencion_id" agregada a public.mantenciones.';
  else
    raise notice 'Columna "evento_mantencion_id" ya existía en public.mantenciones, no se modifica.';
  end if;
end $$;

-- Nota sobre ON DELETE RESTRICT: no se puede borrar un evento mientras
-- exista al menos una mantención que lo referencie (cualquiera sea su
-- estado, incluso "cancelada" — el filtro por estado solo aplica al
-- índice único de abajo, no a esta FK). Como evento_mantencion_id queda
-- inmutable (punto 4), no existe una vía para "desvincular" una
-- mantención de su evento — en la práctica, un evento con al menos un
-- equipo agregado nunca podrá borrarse físicamente, solo cancelarse a
-- nivel de sus propias mantenciones y de su propio estado. Coherente con
-- el mismo criterio ya usado en mantenciones_delete (2B): borrar es la
-- excepción, no la vía normal de cierre.

-- Nota sobre permisos: "evento_mantencion_id" NO se agrega a la lista de
-- columnas de "grant update (...) on mantenciones to authenticated" (2B).
-- Un GRANT UPDATE por columnas solo habilita las columnas listadas
-- explícitamente — una columna nueva no queda incluida automáticamente,
-- así que ya queda inmutable vía UPDATE directo por el simple hecho de
-- no otorgarla, igual que equipo_id/area_id/etc. desde 2B. El trigger del
-- punto 4 es una segunda capa de protección (ver ese punto para el motivo).
-- "grant select on mantenciones to authenticated" (2B) sí es un grant de
-- tabla completa (sin lista de columnas), así que la nueva columna ya es
-- legible sin cambios adicionales.

-- ── 2. Índice único parcial: un equipo no puede estar dos veces activo
--       en el mismo evento ──
-- Filtra solo por "estado <> 'cancelada'" (tal como se pidió): una
-- mantención "cerrada" para ese equipo en ese evento sigue bloqueando
-- que se vuelva a agregar el mismo equipo al mismo evento.
-- Las filas con evento_mantencion_id NULL (mantención suelta) no
-- participan en este índice de forma práctica: Postgres trata cada NULL
-- como distinto de cualquier otro NULL en un índice único, así que varias
-- mantenciones sueltas del mismo equipo (ej. mantenciones mensuales
-- recurrentes) nunca chocan entre sí — el índice solo importa cuando
-- evento_mantencion_id tiene un valor real.
create unique index if not exists uq_mantenciones_evento_equipo
  on mantenciones (evento_mantencion_id, equipo_id)
  where estado <> 'cancelada';

-- ── 3. Índice simple para listar las mantenciones de un evento ──
create index if not exists idx_mantenciones_evento on mantenciones(evento_mantencion_id);

-- ── 4. Trigger BEFORE INSERT: valida la jerarquía completa
--       equipo → área → faena → cliente, y que coincida con el
--       cliente/faena del evento cuando corresponda ──
-- Reutiliza fn_validar_jerarquia_equipo() (2B) SIN modificarla — la
-- llama de nuevo aquí para que la validación exista a nivel de tabla,
-- independiente de qué función futura inserte la fila (fn_crear_mantencion
-- hoy, fn_agregar_equipo_evento en 2D-06 mañana, o cualquier otra vía).
create or replace function fn_validar_jerarquia_mantencion_evento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_cliente_id uuid;
  v_evento_faena_id   uuid;
begin
  perform fn_validar_jerarquia_equipo(NEW.cliente_id, NEW.faena_id, NEW.area_id, NEW.equipo_id);

  if NEW.evento_mantencion_id is not null then
    select em.cliente_id, em.faena_id
      into v_evento_cliente_id, v_evento_faena_id
      from eventos_mantencion em
      where em.id = NEW.evento_mantencion_id;

    if v_evento_faena_id is null then
      raise exception 'El evento de mantención indicado (%) no existe.', NEW.evento_mantencion_id;
    end if;

    if NEW.faena_id <> v_evento_faena_id then
      raise exception 'El equipo de esta mantención pertenece a una faena distinta a la del evento.';
    end if;

    if NEW.cliente_id <> v_evento_cliente_id then
      raise exception 'El equipo de esta mantención pertenece a un cliente distinto al del evento.';
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_validar_jerarquia_mantencion_evento on mantenciones;
create trigger trg_validar_jerarquia_mantencion_evento
  before insert on mantenciones
  for each row execute function fn_validar_jerarquia_mantencion_evento();

-- ── 5. Trigger BEFORE UPDATE: bloquea cambios a equipo_id/area_id/
--       evento_mantencion_id de forma distinta según si la mantención
--       pertenece a un evento o es una mantención suelta ──
-- cliente_id/faena_id siguen siendo inmutables en cualquier caso (no
-- forman parte de este ajuste). Este trigger corre para CUALQUIER rol,
-- sin excepción — protege incluso contra una sesión con privilegios de
-- tabla más amplios que el GRANT de "authenticated" (ver 2D-02 original).
--
-- Regla aplicada (ajuste sobre la versión inicial de 2D-02, que bloqueaba
-- todo sin distinción y habría impedido corregir un error de tipeo en
-- una mantención suelta recién creada, todavía en borrador):
--
--   a) Mantención que YA pertenece a un evento (evento_mantencion_id no
--      nulo antes del UPDATE): bloqueo TOTAL y definitivo de equipo_id,
--      area_id y evento_mantencion_id. Para corregir el equipo de un
--      evento hay que cancelar esa mantención y agregar el equipo
--      correcto mediante las funciones de la ETAPA 2D-06 (ver prueba H).
--
--   b) Mantención suelta (evento_mantencion_id nulo):
--      - evento_mantencion_id NUNCA se puede establecer ni quitar
--        mediante UPDATE directo, bajo ninguna circunstancia — vincular
--        una mantención a un evento es exclusivo de las funciones
--        controladas de la ETAPA 2D-06, nunca de un UPDATE libre.
--      - equipo_id/area_id SÍ se pueden corregir, pero solo mientras la
--        mantención sigue en estado 'borrador' (antes de comprometerse
--        con planificación/ejecución/Snapshot en curso), y solo si la
--        combinación resultante vuelve a pasar la validación completa de
--        jerarquía (fn_validar_jerarquia_equipo, 2B, sin modificar).
create or replace function fn_bloquear_cambio_jerarquia_mantencion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.cliente_id <> OLD.cliente_id then
    raise exception 'No se puede cambiar el cliente de una mantención ya creada.';
  end if;

  if NEW.faena_id <> OLD.faena_id then
    raise exception 'No se puede cambiar la faena de una mantención ya creada.';
  end if;

  if OLD.evento_mantencion_id is not null then
    -- (a) Mantención de evento: bloqueo total, sin excepciones.
    if NEW.equipo_id <> OLD.equipo_id then
      raise exception 'No se puede cambiar el equipo de una mantención que pertenece a un evento. Cancele esta mantención y agregue el equipo correcto al evento (ETAPA 2D-06).';
    end if;

    if NEW.area_id <> OLD.area_id then
      raise exception 'No se puede cambiar el área de una mantención que pertenece a un evento.';
    end if;

    if NEW.evento_mantencion_id is distinct from OLD.evento_mantencion_id then
      raise exception 'No se puede cambiar el evento de mantención asociado a una mantención ya creada.';
    end if;

    return NEW;
  end if;

  -- (b) Mantención suelta: evento_mantencion_id nunca se establece ni se
  -- quita mediante UPDATE directo.
  if NEW.evento_mantencion_id is distinct from OLD.evento_mantencion_id then
    raise exception 'No se puede vincular ni desvincular una mantención de un evento mediante UPDATE directo — use las funciones de la ETAPA 2D-06.';
  end if;

  -- equipo_id/area_id de una mantención suelta: corregibles solo en
  -- borrador, y solo si la jerarquía resultante sigue siendo válida.
  if NEW.equipo_id <> OLD.equipo_id or NEW.area_id <> OLD.area_id then
    if OLD.estado <> 'borrador' then
      raise exception 'Solo se puede corregir el equipo o el área de una mantención suelta mientras está en estado borrador.';
    end if;

    perform fn_validar_jerarquia_equipo(NEW.cliente_id, NEW.faena_id, NEW.area_id, NEW.equipo_id);
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_bloquear_cambio_jerarquia_mantencion on mantenciones;
create trigger trg_bloquear_cambio_jerarquia_mantencion
  before update on mantenciones
  for each row execute function fn_bloquear_cambio_jerarquia_mantencion();

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Columna y FK creadas:
-- select column_name, is_nullable, data_type
--   from information_schema.columns
--   where table_schema = 'public' and table_name = 'mantenciones' and column_name = 'evento_mantencion_id';
--
-- select conname, confrelid::regclass, confdeltype
--   from pg_constraint
--   where conrelid = 'public.mantenciones'::regclass and confrelid = 'public.eventos_mantencion'::regclass;
-- -- confdeltype debe ser 'r' (RESTRICT).
--
-- 2) Índices creados:
-- select indexname, indexdef
--   from pg_indexes
--   where tablename = 'mantenciones' and indexname in ('uq_mantenciones_evento_equipo', 'idx_mantenciones_evento');
--
-- 3) Triggers activos:
-- select tgname, tgenabled, tgtype
--   from pg_trigger
--   where tgrelid = 'public.mantenciones'::regclass
--     and tgname in ('trg_validar_jerarquia_mantencion_evento', 'trg_bloquear_cambio_jerarquia_mantencion');
--
-- 4) Compatibilidad con mantenciones sueltas — no debe fallar por NULLs
--    repetidos (dos o más mantenciones del mismo equipo sin evento):
-- select equipo_id, count(*) from public.mantenciones
--   where evento_mantencion_id is null group by equipo_id having count(*) > 1;
-- -- Filas devueltas aquí son NORMALES y esperadas (mantenciones recurrentes
-- -- del mismo equipo) — el índice único parcial no las afecta.
--
-- 5) Pruebas negativas completas (con datos reales, dentro de una
--    transacción que termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_evento_equipo_etapa2d02.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- (orden inverso: triggers → funciones de trigger → índices → columna)
-- ═══════════════════════════════════════════════════════════════
-- drop trigger if exists trg_bloquear_cambio_jerarquia_mantencion on public.mantenciones;
-- drop function if exists public.fn_bloquear_cambio_jerarquia_mantencion();
-- drop trigger if exists trg_validar_jerarquia_mantencion_evento on public.mantenciones;
-- drop function if exists public.fn_validar_jerarquia_mantencion_evento();
-- drop index if exists public.uq_mantenciones_evento_equipo;
-- drop index if exists public.idx_mantenciones_evento;
-- alter table public.mantenciones drop column if exists evento_mantencion_id;
