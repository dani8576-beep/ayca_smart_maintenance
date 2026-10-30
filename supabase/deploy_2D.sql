-- AYCA SMART MAINTENANCE
-- DEPLOY CONSOLIDADO ETAPA 2D
-- Ejecutar solo después de completar las migraciones 2A, 2A.5, 2B y 2C.
-- No ejecutar dos veces sin verificar previamente el estado de la base.

BEGIN;

-- ============================================================
-- ETAPA 2D-01 — EVENTOS Y NUMERACIÓN
-- Archivo original: 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql
-- ============================================================

-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.01
-- Evento Multiequipo — tabla "eventos_mantencion" y numeración anual propia
--
-- PROPÓSITO:
-- Crear la tabla padre que agrupará varias "mantenciones" (una por
-- equipo) bajo un mismo evento de parada/mantención general (ej.
-- "MLCC Caserones — Motor Bolas 1 + Motor Bolas 2 + Motor SAG").
-- Esta migración SOLO crea la tabla, su numeración anual propia y
-- el trigger de auditoría. No crea la columna de enlace en
-- "mantenciones" (eso es 2D-02), no crea personal/recursos del
-- evento (2D-03/2D-04), no crea funciones de creación (2D-06) ni
-- las políticas RLS de acceso funcional (2D-09).
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-17_perfiles_roles.sql          (es_admin(), tiene_rol())
--   - 2026-07-17_mantenciones_etapa2a5.sql   (clientes, faenas, fn_tocar_auditoria())
--   - 2026-07-17_mantenciones_etapa2b.sql    (patrón de numeración anual,
--                                              referencia de diseño para
--                                              correlativos_evento_mantencion)
--
-- NO crea ni modifica: mantenciones, mantencion_*, evento_personal_*,
-- evento_recursos*, correlativos_mantencion, plantillas_*, protocolos_ayca,
-- herramientas, herramientas_movimientos, clientes, faenas, areas, equipos.
--
-- Además de "eventos_mantencion", esta migración crea el catálogo abierto
-- "tipos_evento_mantencion" (Programada/Correctiva/Emergencia/Proyecto/
-- Parada General/…), del que "eventos_mantencion.tipo_evento" es FK.
--
-- RLS: se habilita "row level security" en eventos_mantencion SIN
-- políticas todavía. Esto es intencional y seguro: una tabla con RLS
-- activo y cero políticas deniega el acceso a cualquier rol no-superusuario
-- por defecto. Las políticas funcionales (quién ve/edita qué) llegan en
-- 2D-09, una vez que exista el resto del modelo (personal, recursos,
-- estado de las mantenciones hijas) del cual dependen esas políticas.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas — aborta con mensaje claro si falta una
--       dependencia, en vez de fallar a medio camino con un error críptico ──
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

  if to_regclass('public.clientes') is null then
    raise exception 'Falta la tabla clientes — ejecutar primero 2026-07-17_mantenciones_etapa2a5.sql';
  end if;

  if to_regclass('public.faenas') is null then
    raise exception 'Falta la tabla faenas — ejecutar primero 2026-07-17_mantenciones_etapa2a5.sql';
  end if;

  if to_regprocedure('public.fn_normalizar_codigo()') is null then
    raise exception 'Falta fn_normalizar_codigo() — ejecutar primero 2026-07-17_mantenciones_etapa2a5.sql';
  end if;

  if to_regclass('public.eventos_mantencion') is not null then
    raise notice 'public.eventos_mantencion ya existe — esta migración es idempotente, continúa sin recrear la tabla.';
  end if;
end $$;

-- ── 1. correlativos_evento_mantencion (numeración anual propia del evento,
--       independiente de correlativos_mantencion — evita mezclar dos
--       secuencias distintas en un mismo contador) ──
create table if not exists correlativos_evento_mantencion (
  anio          int primary key check (anio >= 2020),
  ultimo_numero int not null default 0 check (ultimo_numero >= 0)
);

alter table correlativos_evento_mantencion enable row level security;

create policy "correlativos_evento_mantencion_admin_only" on correlativos_evento_mantencion
  for all using (es_admin()) with check (es_admin());

-- ── 2. Función de numeración — mismo patrón que fn_generar_numero_mantencion()
--       (2B), formato distinguible: AYCA-EVT-{año}-{000000} ──
create or replace function fn_generar_numero_evento_mantencion()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anio int := extract(year from now())::int;
  v_num  int;
begin
  insert into correlativos_evento_mantencion (anio, ultimo_numero)
    values (v_anio, 0)
    on conflict (anio) do nothing;

  update correlativos_evento_mantencion
    set ultimo_numero = ultimo_numero + 1
    where anio = v_anio
    returning ultimo_numero into v_num;

  return 'AYCA-EVT-' || v_anio || '-' || lpad(v_num::text, 6, '0');
end;
$$;

-- Igual que fn_generar_numero_mantencion(): de uso interno únicamente,
-- llamada desde fn_crear_evento_mantencion() (SECURITY DEFINER, 2D-06).
revoke all on function fn_generar_numero_evento_mantencion() from public, authenticated;

-- ── 3. tipos_evento_mantencion (catálogo abierto, no CHECK fijo) ──
-- Mismo criterio ya usado en tipos_mantencion (2C.4: columna "codigo" propia,
-- normalizada en mayúsculas) en vez del catálogo-sin-normalizar de
-- tipos_protocolo (2A). Abierto a propósito: "Programada, Correctiva,
-- Emergencia, Proyecto, Parada General, etc." — la lista crecerá sin
-- requerir una migración de esquema cada vez.
create table if not exists tipos_evento_mantencion (
  codigo          text primary key,
  nombre          text not null,
  descripcion     text,
  activo          boolean not null default true,
  orden           int not null default 0,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz,
  check (trim(codigo) <> ''),
  check (trim(nombre) <> '')
);

create index if not exists idx_tipos_evento_mantencion_activo on tipos_evento_mantencion(activo);

drop trigger if exists trg_normalizar_codigo_tipos_evento_mantencion on tipos_evento_mantencion;
create trigger trg_normalizar_codigo_tipos_evento_mantencion
  before insert or update on tipos_evento_mantencion
  for each row execute function fn_normalizar_codigo();

alter table tipos_evento_mantencion enable row level security;

create policy "tipos_evento_mantencion_select_auth"  on tipos_evento_mantencion for select using (auth.uid() is not null);
create policy "tipos_evento_mantencion_insert_admin" on tipos_evento_mantencion for insert with check (es_admin());
create policy "tipos_evento_mantencion_update_admin" on tipos_evento_mantencion for update using (es_admin());
create policy "tipos_evento_mantencion_delete_admin" on tipos_evento_mantencion for delete using (es_admin());

-- Semilla inicial — idempotente, no pisa códigos ya existentes.
insert into tipos_evento_mantencion (codigo, nombre, orden) values
  ('PROGRAMADA',     'Programada',      1),
  ('CORRECTIVA',     'Correctiva',      2),
  ('EMERGENCIA',     'Emergencia',      3),
  ('PROYECTO',       'Proyecto',        4),
  ('PARADA_GENERAL', 'Parada General',  5)
on conflict (codigo) do nothing;

-- ── 4. Tabla eventos_mantencion ──
-- Vocabulario de estados idéntico al ya usado en "mantenciones" (2B),
-- para que el rollup (2D-08) compare valores del mismo dominio.
-- "personal_estado" y "recursos_estado" son propios del evento (no existen
-- en "mantenciones"): reflejan el avance de revisión/aprobación de las
-- listas generales de personal y recursos (2D-03/2D-04), no el estado de
-- ejecución de cada equipo.
--
-- "codigo": identificador operativo opcional, independiente de "numero"
-- (AYCA-EVT-AAAA-000000). Lo define el supervisor/planificador para uso
-- interno en documentos y comunicación de terreno (ej. "PARADA-JUL26-SAG");
-- "numero" sigue siendo el único identificador oficial e inmutable.
--
-- "criticidad": se mantiene como texto + CHECK con nombre explícito
-- (eventos_mantencion_criticidad_check) — igual que en equipos/mantenciones/
-- plantillas_mantencion hoy — para no romper consistencia con el resto del
-- esquema. Queda preparada para una futura migración a catálogo (mismo
-- patrón de tipos_evento_mantencion): agregar columna FK nullable, hacer
-- backfill por texto, eliminar esta columna y el CHECK nombrado, renombrar.
-- No se crea el catálogo ahora porque ningún otro "criticidad" del esquema
-- lo tiene todavía — hacerlo solo aquí generaría dos formas de representar
-- el mismo concepto en paralelo.
--
-- FK de usuario: por decisión explícita, se mantiene auth.users(id) directo
-- (igual que en 2A-2C), no perfiles_ayca(id). Motivo: perfiles_ayca solo se
-- llena manualmente hoy (el bootstrap de perfiles_roles.sql solo inserta al
-- admin) — apuntar ahí generaría FK rota para supervisores/planificadores
-- sin fila propia. La migración a una tabla propia de usuarios/personal
-- queda pendiente como cambio futuro aplicable a todo el esquema a la vez,
-- no solo a esta tabla.
create table if not exists eventos_mantencion (
  id                   uuid primary key default gen_random_uuid(),
  numero               text not null unique,
  codigo               text,
  cliente_id           uuid not null references public.clientes(id) on delete restrict,
  faena_id             uuid not null references public.faenas(id) on delete restrict,
  tipo_evento          text not null references tipos_evento_mantencion(codigo),
  nombre               text not null,
  descripcion          text,
  estado               text not null default 'borrador',
  planificacion_estado text not null default 'pendiente',
  ejecucion_estado     text not null default 'sin_equipos',
  revision_estado      text not null default 'no_aplica',
  personal_estado      text not null default 'pendiente',
  recursos_estado      text not null default 'pendiente',
  criticidad           text,
  fecha_plan_inicio    timestamptz,
  fecha_plan_termino   timestamptz,
  fecha_real_inicio    timestamptz,
  fecha_real_termino   timestamptz,
  supervisor_id        uuid not null references auth.users(id),
  planificador_id      uuid references auth.users(id),
  observaciones        text,
  creado_por           uuid not null references auth.users(id),
  creado_en            timestamptz not null default now(),
  actualizado_por      uuid references auth.users(id),
  actualizado_en       timestamptz,

  check (trim(nombre) <> ''),
  check (codigo is null or trim(codigo) <> ''),
  -- Vocabulario de estado/ejecucion_estado/revision_estado ACTUALIZADO
  -- en la ETAPA 2D-08 (rollup automático) — reemplaza el vocabulario
  -- original de esta migración. Los 3 CHECK ahora tienen nombre
  -- explícito para evitar el mismo problema de nombres autogenerados
  -- que motivó este cambio (ver encabezado de 2D-08 para el detalle).
  -- planificacion_estado NO cambia — sigue siendo de uso manual del
  -- planificador, ajeno al rollup automático.
  constraint eventos_mantencion_estado_check
    check (estado in ('borrador','planificado','en_ejecucion','finalizado','cancelado')),
  check (planificacion_estado in ('pendiente','en_proceso','lista')),
  constraint eventos_mantencion_ejecucion_estado_check
    check (ejecucion_estado in ('sin_equipos','pendiente','en_ejecucion','parcial','completado')),
  constraint eventos_mantencion_revision_estado_check
    check (revision_estado in ('pendiente','en_revision','parcial','aprobado','no_aplica')),
  check (personal_estado in ('pendiente','en_revision','parcial','aprobado')),
  check (recursos_estado in ('pendiente','en_revision','parcial','aprobado')),
  constraint eventos_mantencion_criticidad_check check (criticidad is null or criticidad in ('baja','media','alta','critica')),
  check (fecha_plan_termino is null or fecha_plan_inicio is null or fecha_plan_termino >= fecha_plan_inicio),
  check (fecha_real_termino is null or fecha_real_inicio is null or fecha_real_termino >= fecha_real_inicio)
  -- Los dos CHECK cruzados que existían aquí originalmente
  -- ("estado <> 'cerrada' or (ejecucion_estado = 'completada' and
  -- revision_estado = 'aprobada')" y "estado <> 'en_ejecucion' or
  -- fecha_real_inicio is not null") se ELIMINAN en 2D-08: asumían que
  -- "estado" solo cambiaba manualmente y en conjunto con los otros
  -- campos. Con el rollup automático (2D-08), estado/ejecucion_estado/
  -- revision_estado son 3 dimensiones calculadas de forma INDEPENDIENTE
  -- a partir de las mantenciones hijas — un evento puede legítimamente
  -- quedar "finalizado" (todas las mantenciones completadas) con
  -- revision_estado todavía en 'parcial' (aprobaciones pendientes), y la
  -- segunda restricción habría bloqueado la propia actualización
  -- automática a 'en_ejecucion' mientras fecha_real_inicio siga sin
  -- fijarse a mano. fecha_real_inicio/fecha_real_termino quedan como
  -- campos informativos de uso manual, sin acoplarse al rollup.
);

create unique index if not exists uq_eventos_mantencion_codigo
  on eventos_mantencion (codigo) where codigo is not null and trim(codigo) <> '';

drop trigger if exists trg_normalizar_codigo_eventos_mantencion on eventos_mantencion;
create trigger trg_normalizar_codigo_eventos_mantencion
  before insert or update on eventos_mantencion
  for each row execute function fn_normalizar_codigo();

-- ── 5. Índices ──
create index if not exists idx_eventos_mantencion_cliente            on eventos_mantencion(cliente_id);
create index if not exists idx_eventos_mantencion_faena              on eventos_mantencion(faena_id);
create index if not exists idx_eventos_mantencion_tipo_evento        on eventos_mantencion(tipo_evento);
create index if not exists idx_eventos_mantencion_estado             on eventos_mantencion(estado);
create index if not exists idx_eventos_mantencion_supervisor         on eventos_mantencion(supervisor_id);
create index if not exists idx_eventos_mantencion_planificador       on eventos_mantencion(planificador_id);
create index if not exists idx_eventos_mantencion_fecha_plan_inicio  on eventos_mantencion(fecha_plan_inicio);
create index if not exists idx_eventos_mantencion_fecha_plan_termino on eventos_mantencion(fecha_plan_termino);
create index if not exists idx_eventos_mantencion_creado_en          on eventos_mantencion(creado_en);

-- ── 6. RLS: habilitado, SIN políticas (deny-all por defecto hasta 2D-09) ──
alter table eventos_mantencion enable row level security;

-- ── 7. Auditoría — reutiliza fn_tocar_auditoria() (2A.5), sin duplicar ──
create trigger trg_auditoria_eventos_mantencion
  before update on eventos_mantencion
  for each row execute function fn_tocar_auditoria();

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Tabla y columnas creadas:
-- select column_name, data_type, is_nullable
--   from information_schema.columns
--   where table_schema = 'public' and table_name = 'eventos_mantencion'
--   order by ordinal_position;
--
-- 2) Restricciones (CHECK, FK, UNIQUE):
-- select conname, contype
--   from pg_constraint
--   where conrelid = 'public.eventos_mantencion'::regclass
--   order by conname;
--
-- 3) RLS activo y sin políticas (debe devolver 0 filas en la segunda consulta):
-- select relrowsecurity from pg_class where oid = 'public.eventos_mantencion'::regclass;
-- select policyname from pg_policies where tablename = 'eventos_mantencion';
--
-- 4) Numeración: probar dos llamadas consecutivas (requiere estar autenticado
--    como un rol con privilegios para ejecutar la función; recuerda que está
--    revocada de "authenticated" — pruébala como owner/servicio):
-- select fn_generar_numero_evento_mantencion();
-- select fn_generar_numero_evento_mantencion();
-- select * from correlativos_evento_mantencion;
--
-- 5) Trigger de auditoría activo:
-- select tgname, tgenabled
--   from pg_trigger
--   where tgrelid = 'public.eventos_mantencion'::regclass and tgname = 'trg_auditoria_eventos_mantencion';
--
-- 6) Catálogo de tipos de evento sembrado y normalizado:
-- select codigo, nombre, activo, orden from public.tipos_evento_mantencion order by orden;
--
-- 7) Código operativo único cuando está presente (debe fallar si se repite):
-- select codigo, count(*) from public.eventos_mantencion
--   where codigo is not null group by codigo having count(*) > 1;

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- (orden inverso: trigger → tabla principal → función → tabla de soporte)
-- ═══════════════════════════════════════════════════════════════
-- drop trigger if exists trg_auditoria_eventos_mantencion on public.eventos_mantencion;
-- drop trigger if exists trg_normalizar_codigo_eventos_mantencion on public.eventos_mantencion;
-- drop table if exists public.eventos_mantencion;
-- drop trigger if exists trg_normalizar_codigo_tipos_evento_mantencion on public.tipos_evento_mantencion;
-- drop table if exists public.tipos_evento_mantencion;
-- drop function if exists public.fn_generar_numero_evento_mantencion();
-- drop table if exists public.correlativos_evento_mantencion;

-- ============================================================
-- ETAPA 2D-02 — RELACIÓN MANTENCIONES-EVENTO
-- Archivo original: 2026-07-18_mantenciones_etapa2d_02_relacion_evento.sql
-- ============================================================

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

-- ============================================================
-- ETAPA 2D-03 — PERSONAL DEL EVENTO (REQUERIDO / ASIGNADO)
-- Archivo original: 2026-07-18_mantenciones_etapa2d_03_personal.sql
-- ============================================================

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

-- ============================================================
-- ETAPA 2D-04 — RECURSOS DEL EVENTO
-- Archivo original: 2026-07-18_mantenciones_etapa2d_04_recursos.sql
-- ============================================================

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

-- ============================================================
-- ETAPA 2D-05 — TRAZABILIDAD DE ORIGEN
-- Archivo original: 2026-07-18_mantenciones_etapa2d_05_trazabilidad.sql
-- ============================================================

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

-- ============================================================
-- ETAPA 2D-06 — FUNCIONES DE CREACIÓN
-- Archivo original: 2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql
-- ============================================================

-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.06
-- Funciones de creación: evento y agregado de equipo
--
-- PROPÓSITO:
-- Entregar las dos funciones públicas que arman el flujo multiequipo:
--   - fn_crear_evento_mantencion(): crea SOLO la fila del evento
--     (eventos_mantencion). Responsabilidad única — no toca equipos,
--     personal ni recursos.
--   - fn_agregar_equipo_evento(): agrega UN equipo a un evento ya
--     existente. Es la función "pesada" de esta etapa: crea la
--     mantención de ese equipo, su snapshot reducido, consolida
--     personal/recursos del evento y actualiza los estados agregados.
--     Se puede llamar tantas veces como equipos tenga el evento.
--
-- Ambas funciones NO tocan fn_crear_mantencion() (2B/2C) — siguen
-- existiendo sin cambios para el flujo de mantención suelta.
--
-- ── FLUJO COMPLETO DE fn_agregar_equipo_evento() ──
--   1. validar        → rol, evento existe y no está cerrado/cancelado,
--                        quien llama es el supervisor del evento o admin,
--                        jerarquía equipo→área→faena→cliente contra el
--                        cliente/faena REALES del evento, el equipo NO
--                        está ya activo en este evento (verificado en
--                        código, no solo confiando en el índice único de
--                        2D-02 — ver nota más abajo), tipo de mantención
--                        activo, plantilla activa y del tipo correcto.
--   2. crear mantención     → inserta en "mantenciones" con
--                             evento_mantencion_id = el evento.
--   3. snapshot reducido    → copia SOLO plantilla_actividades y
--                             plantilla_protocolos hacia
--                             mantencion_actividades/mantencion_protocolos
--                             (idéntico, línea por línea, al bloque de
--                             snapshot que ya usa fn_crear_mantencion
--                             para esas dos tablas — sin reinventarlo).
--                             Personal y recursos NO se snapshotean por
--                             equipo: van a los pasos 4-6.
--   4. consolidar personal  → fn_consolidar_personal_evento() (privada)
--                             encuentra o crea, por cada fila de
--                             plantilla_personal del equipo, la línea
--                             evento_personal_requerido correspondiente
--                             (match por perfil+especialidad).
--   5. consolidar recursos  → fn_consolidar_recursos_evento() (privada),
--                             mismo criterio, usando la misma clave
--                             normalizada que el índice único de
--                             evento_recursos (2D-04): categoria +
--                             nombre_generico normalizado + código.
--   6. crear tablas de origen → el resultado de los pasos 4 y 5 (qué
--                             línea corresponde a cada fila de
--                             plantilla) se usa directamente para
--                             insertar en evento_personal_origen /
--                             evento_recursos_origen (2D-05) — fusionado
--                             en el mismo INSERT ... SELECT que consume
--                             la función de consolidación.
--   7. recalcular cantidades → fn_recalcular_personal_evento() /
--                             fn_recalcular_recursos_evento() (privadas)
--                             recomputan cantidad_sugerida de TODAS las
--                             líneas vigentes del evento, sumando las
--                             filas de origen ACTIVAS. Nunca tocan
--                             cantidad_aprobada — son las mismas
--                             funciones que reutilizará 2D-07 al quitar
--                             un equipo.
--   8. actualizar estados   → personal_estado/recursos_estado del evento
--                             pasan a 'en_revision' (cualquier cambio en
--                             las listas exige que el supervisor revise
--                             de nuevo antes de aprobar).
--
-- TRANSACCIONALIDAD: todo el flujo ocurre dentro de UNA sola función
-- PL/pgSQL. En PostgreSQL, una función completa se ejecuta como parte de
-- la transacción que la invoca — si CUALQUIER paso lanza una excepción
-- (incluida cualquiera de las validaciones del paso 1, o un CHECK/FK de
-- alguna de las tablas), ningún efecto de los pasos anteriores queda
-- aplicado: no hay mantención a medio crear, ni snapshot parcial, ni
-- consolidación incompleta. No se necesita (ni es posible) un BEGIN/COMMIT
-- explícito dentro de la función — la atomicidad es una propiedad del
-- lenguaje, no algo que este archivo deba programar aparte.
--
-- DUPLICADOS: el índice único uq_mantenciones_evento_equipo (2D-02) sigue
-- siendo el resguardo final ante condiciones de carrera (dos llamadas
-- simultáneas). Pero esta función NO se apoya solo en él: valida
-- explícitamente la ausencia de una mantención activa del mismo equipo en
-- el mismo evento ANTES de intentar el insert, y lanza un mensaje de
-- error claro y específico en vez de dejar que el usuario vea el error
-- genérico de una restricción de base de datos violada.
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-17_mantenciones_etapa2a.sql     (plantilla_actividades, plantilla_protocolos,
--                                                plantilla_personal, plantilla_recursos)
--   - 2026-07-17_mantenciones_etapa2b.sql      (mantenciones, fn_validar_jerarquia_equipo(),
--                                                fn_generar_numero_mantencion())
--   - 2026-07-17_mantenciones_etapa2c.sql      (mantencion_actividades, mantencion_protocolos)
--   - 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql
--   - 2026-07-18_mantenciones_etapa2d_02_relacion_evento.sql
--   - 2026-07-18_mantenciones_etapa2d_03_personal.sql
--   - 2026-07-18_mantenciones_etapa2d_04_recursos.sql
--   - 2026-07-18_mantenciones_etapa2d_05_trazabilidad.sql
--
-- NO crea todavía: funciones de alta/baja/modificación/aprobación manual
-- de evento_personal_requerido/evento_recursos/evento_personal_asignado,
-- ni la función de "quitar equipo" con su propio recálculo (todo eso es
-- 2D-07). NO modifica RLS (2D-09).
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regprocedure('public.tiene_rol(text)') is null then
    raise exception 'Falta tiene_rol() — ejecutar primero 2026-07-17_perfiles_roles.sql';
  end if;

  if to_regprocedure('public.fn_validar_jerarquia_equipo(uuid,uuid,uuid,uuid)') is null then
    raise exception 'Falta fn_validar_jerarquia_equipo() — ejecutar primero 2026-07-17_mantenciones_etapa2b.sql';
  end if;

  if to_regprocedure('public.fn_generar_numero_mantencion()') is null then
    raise exception 'Falta fn_generar_numero_mantencion() — ejecutar primero 2026-07-17_mantenciones_etapa2b.sql';
  end if;

  if to_regprocedure('public.fn_generar_numero_evento_mantencion()') is null then
    raise exception 'Falta fn_generar_numero_evento_mantencion() — ejecutar primero 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql';
  end if;

  if to_regclass('public.mantencion_actividades') is null or to_regclass('public.mantencion_protocolos') is null then
    raise exception 'Faltan mantencion_actividades/mantencion_protocolos — ejecutar primero 2026-07-17_mantenciones_etapa2c.sql';
  end if;

  if to_regclass('public.evento_personal_requerido') is null then
    raise exception 'Falta evento_personal_requerido — ejecutar primero 2026-07-18_mantenciones_etapa2d_03_personal.sql';
  end if;

  if to_regclass('public.evento_recursos') is null then
    raise exception 'Falta evento_recursos — ejecutar primero 2026-07-18_mantenciones_etapa2d_04_recursos.sql';
  end if;

  if to_regclass('public.evento_personal_origen') is null or to_regclass('public.evento_recursos_origen') is null then
    raise exception 'Faltan evento_personal_origen/evento_recursos_origen — ejecutar primero 2026-07-18_mantenciones_etapa2d_05_trazabilidad.sql';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'mantenciones' and column_name = 'evento_mantencion_id'
  ) then
    raise exception 'Falta la columna mantenciones.evento_mantencion_id — ejecutar primero 2026-07-18_mantenciones_etapa2d_02_relacion_evento.sql';
  end if;
end $$;

-- ── 1. fn_crear_evento_mantencion() — responsabilidad única: crear el
--       evento. No agrega equipos, no toca personal ni recursos. ──
create or replace function fn_crear_evento_mantencion(
  p_cliente_id         uuid,
  p_faena_id           uuid,
  p_tipo_evento        text,
  p_nombre             text,
  p_supervisor_id      uuid default auth.uid(),
  p_planificador_id    uuid default null,
  p_codigo             text default null,
  p_criticidad         text default null,
  p_fecha_plan_inicio  timestamptz default null,
  p_fecha_plan_termino timestamptz default null,
  p_descripcion        text default null,
  p_observaciones      text default null
)
returns table (id uuid, numero text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente_activo      boolean;
  v_faena_activo        boolean;
  v_faena_cliente_id    uuid;
  v_tipo_evento_activo  boolean;
  v_numero              text;
  v_id                  uuid;
begin
  if not (tiene_rol('supervisor') or es_admin()) then
    raise exception 'Solo supervisores o administradores pueden crear eventos de mantención.';
  end if;

  if p_supervisor_id <> auth.uid() and not es_admin() then
    raise exception 'No puede crear un evento asignando a otro supervisor.';
  end if;

  select c.activo into v_cliente_activo from clientes c where c.id = p_cliente_id;
  if v_cliente_activo is null then
    raise exception 'Cliente no encontrado.';
  elsif not v_cliente_activo then
    raise exception 'El cliente está inactivo.';
  end if;

  select f.activo, f.cliente_id into v_faena_activo, v_faena_cliente_id from faenas f where f.id = p_faena_id;
  if v_faena_cliente_id is null then
    raise exception 'Faena no encontrada.';
  elsif not v_faena_activo then
    raise exception 'La faena está inactiva.';
  elsif v_faena_cliente_id <> p_cliente_id then
    raise exception 'La faena no pertenece al cliente seleccionado.';
  end if;

  select tem.activo into v_tipo_evento_activo from tipos_evento_mantencion tem where tem.codigo = p_tipo_evento;
  if v_tipo_evento_activo is null then
    raise exception 'Tipo de evento no encontrado.';
  elsif not v_tipo_evento_activo then
    raise exception 'El tipo de evento está inactivo.';
  end if;

  if trim(coalesce(p_nombre, '')) = '' then
    raise exception 'El evento debe tener un nombre.';
  end if;

  v_numero := fn_generar_numero_evento_mantencion();

  insert into eventos_mantencion as em (
    numero, codigo, cliente_id, faena_id, tipo_evento, nombre, descripcion,
    criticidad, fecha_plan_inicio, fecha_plan_termino,
    supervisor_id, planificador_id, observaciones, creado_por
  ) values (
    v_numero, p_codigo, p_cliente_id, p_faena_id, p_tipo_evento, p_nombre, p_descripcion,
    p_criticidad, p_fecha_plan_inicio, p_fecha_plan_termino,
    p_supervisor_id, p_planificador_id, p_observaciones, auth.uid()
  )
  returning em.id into v_id;

  return query select v_id, v_numero;
end;
$$;

revoke all on function fn_crear_evento_mantencion(
  uuid, uuid, text, text, uuid, uuid, text, text, timestamptz, timestamptz, text, text
) from public;
grant execute on function fn_crear_evento_mantencion(
  uuid, uuid, text, text, uuid, uuid, text, text, timestamptz, timestamptz, text, text
) to authenticated;

-- ── 2. fn_consolidar_personal_evento() — PRIVADA. Encuentra o crea, por
--       cada fila de plantilla_personal de la plantilla dada, la línea
--       evento_personal_requerido correspondiente en el evento dado.
--       Match por (perfil, especialidad) sobre líneas vigentes
--       (estado_fila <> 'eliminado'). Si no existe, la crea con
--       cantidad_sugerida = 0 (el valor real lo fija el recálculo del
--       paso 7, sumando TODAS las filas de origen activas — no solo la
--       de este equipo). Devuelve el mapeo necesario para crear la fila
--       de origen (paso 6). ──
create or replace function fn_consolidar_personal_evento(
  p_evento_id    uuid,
  p_plantilla_id uuid
)
returns table (plantilla_personal_id uuid, evento_personal_requerido_id uuid, cantidad numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pp           record;
  v_requerido_id uuid;
begin
  for v_pp in
    select pp.id, pp.perfil, pp.especialidad, pp.cantidad
    from plantilla_personal pp
    where pp.plantilla_id = p_plantilla_id
  loop
    select epr.id into v_requerido_id
      from evento_personal_requerido epr
      where epr.evento_mantencion_id = p_evento_id
        and epr.perfil = v_pp.perfil
        and epr.especialidad is not distinct from v_pp.especialidad
        and epr.estado_fila <> 'eliminado'
      limit 1;

    if v_requerido_id is null then
      insert into evento_personal_requerido (
        evento_mantencion_id, perfil, especialidad, cantidad_sugerida, origen, estado_fila, creado_por
      ) values (
        p_evento_id, v_pp.perfil, v_pp.especialidad, 0, 'plantilla', 'sugerido', auth.uid()
      )
      returning evento_personal_requerido.id into v_requerido_id;
    end if;

    plantilla_personal_id := v_pp.id;
    evento_personal_requerido_id := v_requerido_id;
    cantidad := v_pp.cantidad;
    return next;
  end loop;
end;
$$;

revoke all on function fn_consolidar_personal_evento(uuid, uuid) from public, authenticated;

-- ── 3. fn_consolidar_recursos_evento() — PRIVADA. Mismo criterio que la
--       anterior, para plantilla_recursos/evento_recursos. La clave de
--       coincidencia replica EXACTAMENTE la del índice único
--       uq_evento_recursos_vigente (2D-04): categoria_recurso +
--       nombre_generico normalizado (mayúsculas/trim) + coalesce de
--       ambos códigos — así una línea encontrada aquí es, por
--       construcción, la misma que protege ese índice. ──
create or replace function fn_consolidar_recursos_evento(
  p_evento_id    uuid,
  p_plantilla_id uuid
)
returns table (plantilla_recurso_id uuid, evento_recursos_id uuid, cantidad numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pr         record;
  v_recurso_id uuid;
begin
  for v_pr in
    select prec.id, prec.categoria_recurso, prec.nombre_generico,
           prec.herramienta_codigo, prec.insumo_codigo, prec.cantidad_sugerida
    from plantilla_recursos prec
    where prec.plantilla_id = p_plantilla_id
  loop
    select er.id into v_recurso_id
      from evento_recursos er
      where er.evento_mantencion_id = p_evento_id
        and er.categoria_recurso = v_pr.categoria_recurso
        and upper(trim(er.nombre_generico)) = upper(trim(v_pr.nombre_generico))
        and coalesce(er.herramienta_codigo, er.insumo_codigo, '') = coalesce(v_pr.herramienta_codigo, v_pr.insumo_codigo, '')
        and er.estado_fila <> 'eliminado'
      limit 1;

    if v_recurso_id is null then
      insert into evento_recursos (
        evento_mantencion_id, categoria_recurso, nombre_generico, herramienta_codigo, insumo_codigo,
        cantidad_sugerida, origen, estado_fila, creado_por
      ) values (
        p_evento_id, v_pr.categoria_recurso, v_pr.nombre_generico, v_pr.herramienta_codigo, v_pr.insumo_codigo,
        0, 'plantilla', 'sugerido', auth.uid()
      )
      returning evento_recursos.id into v_recurso_id;
    end if;

    plantilla_recurso_id := v_pr.id;
    evento_recursos_id := v_recurso_id;
    cantidad := v_pr.cantidad_sugerida;
    return next;
  end loop;
end;
$$;

revoke all on function fn_consolidar_recursos_evento(uuid, uuid) from public, authenticated;

-- ── 4. fn_recalcular_personal_evento() — PRIVADA y REUTILIZABLE: la
--       llamará tanto este archivo (paso 7, al agregar un equipo) como
--       2D-07 (al quitar uno). Recalcula cantidad_sugerida de TODAS las
--       líneas vigentes del evento como la suma de sus filas de origen
--       ACTIVAS — nunca escribe cantidad_aprobada. ──
create or replace function fn_recalcular_personal_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update evento_personal_requerido epr
  set cantidad_sugerida = coalesce((
        select sum(epo.cantidad_aportada)
        from evento_personal_origen epo
        where epo.evento_personal_requerido_id = epr.id
          and epo.estado = 'activo'
      ), 0)
  where epr.evento_mantencion_id = p_evento_id
    and epr.estado_fila <> 'eliminado';
end;
$$;

revoke all on function fn_recalcular_personal_evento(uuid) from public, authenticated;

-- ── 5. fn_recalcular_recursos_evento() — PRIVADA y REUTILIZABLE, mismo
--       criterio que la anterior para evento_recursos/evento_recursos_origen. ──
create or replace function fn_recalcular_recursos_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update evento_recursos er
  set cantidad_sugerida = coalesce((
        select sum(ero.cantidad_aportada)
        from evento_recursos_origen ero
        where ero.evento_recursos_id = er.id
          and ero.estado = 'activo'
      ), 0)
  where er.evento_mantencion_id = p_evento_id
    and er.estado_fila <> 'eliminado';
end;
$$;

revoke all on function fn_recalcular_recursos_evento(uuid) from public, authenticated;

-- ── 6. fn_agregar_equipo_evento() — orquesta los 8 pasos documentados
--       arriba, usando las 4 funciones privadas anteriores. ──
create or replace function fn_agregar_equipo_evento(
  p_evento_id          uuid,
  p_area_id            uuid,
  p_equipo_id          uuid,
  p_tipo_mantencion_id uuid,
  p_plantilla_id       uuid,
  p_criticidad         text default null,
  p_fecha_plan_inicio  timestamptz default null,
  p_fecha_plan_termino timestamptz default null,
  p_observaciones      text default null
)
returns table (mantencion_id uuid, numero text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_cliente_id  uuid;
  v_evento_faena_id    uuid;
  v_evento_estado      text;
  v_evento_supervisor  uuid;
  v_tipo_activo        boolean;
  v_plantilla_activa   boolean;
  v_plantilla_tipo_id  uuid;
  v_plantilla_nombre   text;
  v_plantilla_version  int;
  v_numero             text;
  v_mant_id            uuid;
begin
  -- ═══ Paso 1: validar ═══
  if not (tiene_rol('supervisor') or es_admin()) then
    raise exception 'Solo supervisores o administradores pueden agregar equipos a un evento.';
  end if;

  select em.cliente_id, em.faena_id, em.estado, em.supervisor_id
    into v_evento_cliente_id, v_evento_faena_id, v_evento_estado, v_evento_supervisor
    from eventos_mantencion em
    where em.id = p_evento_id;

  if v_evento_faena_id is null then
    raise exception 'El evento de mantención indicado (%) no existe.', p_evento_id;
  end if;

  if v_evento_estado in ('cerrada','cancelada') then
    raise exception 'No se pueden agregar equipos a un evento en estado %.', v_evento_estado;
  end if;

  if auth.uid() <> v_evento_supervisor and not es_admin() then
    raise exception 'Solo el supervisor del evento o un administrador puede agregar equipos.';
  end if;

  -- Jerarquía completa equipo → área → faena → cliente, validada contra
  -- el cliente/faena REALES del evento (reutiliza fn_validar_jerarquia_equipo, 2B).
  perform fn_validar_jerarquia_equipo(v_evento_cliente_id, v_evento_faena_id, p_area_id, p_equipo_id);

  -- Duplicado: verificado EN CÓDIGO antes del insert — no se confía solo
  -- en uq_mantenciones_evento_equipo (2D-02), que sigue existiendo como
  -- resguardo ante condiciones de carrera, no como única defensa.
  if exists (
    select 1 from mantenciones m
    where m.evento_mantencion_id = p_evento_id
      and m.equipo_id = p_equipo_id
      and m.estado <> 'cancelada'
  ) then
    raise exception 'Este equipo ya tiene una mantención activa dentro de este evento. Cancele la mantención existente antes de volver a agregarlo.';
  end if;

  select tm.activo into v_tipo_activo from tipos_mantencion tm where tm.id = p_tipo_mantencion_id;
  if v_tipo_activo is null then
    raise exception 'Tipo de mantención no encontrado.';
  elsif not v_tipo_activo then
    raise exception 'El tipo de mantención está inactivo.';
  end if;

  select pm.activa, pm.tipo_mantencion_id, pm.nombre, pm.version
    into v_plantilla_activa, v_plantilla_tipo_id, v_plantilla_nombre, v_plantilla_version
    from plantillas_mantencion pm
    where pm.id = p_plantilla_id;
  if v_plantilla_tipo_id is null then
    raise exception 'Plantilla no encontrada.';
  elsif not v_plantilla_activa then
    raise exception 'La plantilla seleccionada está inactiva.';
  elsif v_plantilla_tipo_id <> p_tipo_mantencion_id then
    raise exception 'La plantilla no pertenece al tipo de mantención seleccionado.';
  end if;

  -- ═══ Paso 2: crear mantención ═══
  v_numero := fn_generar_numero_mantencion();

  insert into mantenciones as m (
    numero, cliente_id, faena_id, area_id, equipo_id,
    tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
    evento_mantencion_id,
    estado, planificacion_estado, recursos_estado, ejecucion_estado, revision_estado,
    criticidad, fecha_plan_inicio, fecha_plan_termino,
    supervisor_id, observaciones, creado_por
  ) values (
    v_numero, v_evento_cliente_id, v_evento_faena_id, p_area_id, p_equipo_id,
    p_tipo_mantencion_id, p_plantilla_id, v_plantilla_nombre, v_plantilla_version,
    p_evento_id,
    'borrador', 'pendiente', 'pendiente', 'no_iniciada', 'pendiente',
    p_criticidad, p_fecha_plan_inicio, p_fecha_plan_termino,
    v_evento_supervisor, p_observaciones, auth.uid()
  )
  returning m.id into v_mant_id;

  -- ═══ Paso 3: snapshot reducido (solo actividades + protocolos) ═══
  -- Idéntico, línea por línea, al bloque equivalente de fn_crear_mantencion
  -- (2C) — mismo criterio, sin modificar esa función.
  insert into mantencion_actividades (
    mantencion_id, plantilla_actividad_id, codigo_actividad, descripcion, orden,
    depende_de, duracion_estimada_horas, obligatoria, origen, estado_fila, creado_por
  )
  select v_mant_id, pa.id, pa.codigo_actividad, pa.descripcion, pa.orden,
         pa.depende_de, pa.duracion_estimada_horas, pa.obligatoria, 'plantilla', 'sugerido', auth.uid()
  from plantilla_actividades pa
  where pa.plantilla_id = p_plantilla_id;

  insert into mantencion_protocolos (
    mantencion_id, plantilla_protocolo_id, tipo_protocolo, obligatorio, origen, estado_fila, creado_por
  )
  select v_mant_id, ppr.id, ppr.tipo_protocolo, ppr.obligatorio, 'plantilla', 'sugerido', auth.uid()
  from plantilla_protocolos ppr
  where ppr.plantilla_id = p_plantilla_id;

  -- ═══ Pasos 4 y 6 (personal): consolidar + crear fila de origen ═══
  -- fn_consolidar_personal_evento() (paso 4) resuelve o crea cada línea;
  -- el INSERT ... SELECT que consume su resultado crea la fila de origen
  -- (paso 6) para cada una, en el mismo recorrido.
  insert into evento_personal_origen (
    evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
  )
  select cp.evento_personal_requerido_id, v_mant_id, cp.plantilla_personal_id, cp.cantidad, auth.uid()
  from fn_consolidar_personal_evento(p_evento_id, p_plantilla_id) cp;

  -- ═══ Pasos 5 y 6 (recursos): mismo criterio que personal ═══
  insert into evento_recursos_origen (
    evento_recursos_id, mantencion_id, plantilla_recurso_id, cantidad_aportada, creado_por
  )
  select cr.evento_recursos_id, v_mant_id, cr.plantilla_recurso_id, cr.cantidad, auth.uid()
  from fn_consolidar_recursos_evento(p_evento_id, p_plantilla_id) cr;

  -- ═══ Paso 7: recalcular cantidades sugeridas ═══
  perform fn_recalcular_personal_evento(p_evento_id);
  perform fn_recalcular_recursos_evento(p_evento_id);

  -- ═══ Paso 8: actualizar estados del evento ═══
  -- Cualquier cambio en las listas consolidadas exige nueva revisión del
  -- supervisor. cantidad_aprobada nunca se toca aquí (solo la tocan las
  -- funciones de aprobación de 2D-07).
  update eventos_mantencion as em2
  set personal_estado = 'en_revision',
      recursos_estado = 'en_revision'
  where em2.id = p_evento_id;

  return query select v_mant_id, v_numero;
end;
$$;

revoke all on function fn_agregar_equipo_evento(
  uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text
) from public;
grant execute on function fn_agregar_equipo_evento(
  uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text
) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Funciones creadas y sus privilegios:
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace
--     and p.proname in (
--       'fn_crear_evento_mantencion', 'fn_agregar_equipo_evento',
--       'fn_consolidar_personal_evento', 'fn_consolidar_recursos_evento',
--       'fn_recalcular_personal_evento', 'fn_recalcular_recursos_evento'
--     )
--   order by p.proname;
-- -- Las 4 funciones privadas deben mostrar "false"; las 2 públicas, "true".
--
-- 2) Prueba de punta a punta (con datos reales, dentro de una transacción
--    que termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_funciones_creacion_etapa2d06.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop function if exists public.fn_agregar_equipo_evento(uuid, uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, text);
-- drop function if exists public.fn_recalcular_recursos_evento(uuid);
-- drop function if exists public.fn_recalcular_personal_evento(uuid);
-- drop function if exists public.fn_consolidar_recursos_evento(uuid, uuid);
-- drop function if exists public.fn_consolidar_personal_evento(uuid, uuid);
-- drop function if exists public.fn_crear_evento_mantencion(uuid, uuid, text, text, uuid, uuid, text, text, timestamptz, timestamptz, text, text);

-- ============================================================
-- ETAPA 2D-07 — FUNCIONES DE AJUSTE Y APROBACIÓN
-- Archivo original: 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql
-- ============================================================

-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.07
-- Funciones de ajuste manual y aprobación — cierre del flujo de
-- planificación multiequipo
--
-- PROPÓSITO:
-- Dejar operativo el ciclo completo de planificación de un evento:
-- quitar un equipo, y que el supervisor pueda agregar/quitar/modificar/
-- aprobar personal y recursos de forma manual, sin que el "motor"
-- automático (consolidación + recálculo) pise nunca una aprobación ya
-- dada.
--
-- ── SEPARACIÓN MOTOR vs. MANUAL (principio rector de este archivo) ──
--   MOTOR (automático, dispara con agregar/quitar un equipo):
--     - fn_consolidar_personal_evento() / fn_consolidar_recursos_evento() (2D-06)
--     - fn_recalcular_personal_evento() / fn_recalcular_recursos_evento() (2D-06,
--       CORREGIDAS aquí — ver más abajo)
--     - fn_quitar_equipo_evento() (nueva en este archivo)
--     El motor SOLO escribe cantidad_sugerida. NUNCA escribe
--     cantidad_aprobada — esa columna es exclusivamente del supervisor.
--   MANUAL (el supervisor decide, nunca se dispara solo):
--     - agregar/quitar/modificar líneas de origen 'manual'
--     - aprobar (fija cantidad_aprobada), sea el origen que sea
--
-- ── CORRECCIÓN A 2D-06 (antes de agregar funciones nuevas) ──
-- Al diseñar el alta manual se detectó un defecto real en las funciones
-- de recálculo de 2D-06: recalculaban cantidad_sugerida de TODAS las
-- líneas vigentes del evento, sin distinguir origen. Eso significa que
-- una línea 'manual' (que no tiene filas de origen por equipo, porque no
-- proviene de ninguna plantilla) quedaría en cantidad_sugerida = 0 la
-- próxima vez que se agregara o quitara cualquier equipo — borrando
-- silenciosamente el valor que el supervisor acaba de definir. Se
-- corrige aquí restringiendo el recálculo a origen = 'plantilla'
-- (CREATE OR REPLACE, misma firma, mismo contrato — igual criterio que
-- ya usó el archivo de corrección de 2C para fn_crear_mantencion()).
--
-- También se actualiza fn_agregar_equipo_evento() (2D-06) para que su
-- paso 8 use la nueva función reutilizable fn_actualizar_estado_revision()
-- en vez de fijar 'en_revision' de forma directa — así el paso 8 de
-- agregar un equipo y el de quitarlo (este archivo) comparten EXACTAMENTE
-- la misma lógica de estados, sin duplicarla.
--
-- ── FUNCIÓN REUTILIZABLE DE ESTADOS ──
-- fn_actualizar_estado_revision(p_evento_id, p_ambito) centraliza la
-- regla de personal_estado/recursos_estado, para no repetirla en cada
-- función de ajuste/aprobación:
--   - 0 líneas vigentes                          → 'pendiente'
--   - todas las líneas vigentes aprobadas Y con
--     cantidad_aprobada = cantidad_sugerida       → 'aprobado'
--   - ninguna línea vigente está en ese estado
--     "aprobada y conforme"                       → 'en_revision'
--   - una mezcla de ambas                         → 'parcial'
-- "Conforme" excluye a propósito una aprobación que quedó desalineada
-- tras un recálculo (aprobada ≠ sugerida) — necesita revisión igual que
-- una línea nunca aprobada, que es exactamente el caso que pide cubrir
-- "si una modificación manual cambia el equilibrio entre sugerido y
-- aprobado".
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-18_mantenciones_etapa2d_03_personal.sql
--   - 2026-07-18_mantenciones_etapa2d_04_recursos.sql
--   - 2026-07-18_mantenciones_etapa2d_05_trazabilidad.sql
--   - 2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql
--
-- NO modifica RLS (2D-09). NO crea funciones para evento_personal_asignado
-- (asignación de personas reales) — no estaba en el alcance pedido para
-- esta etapa; queda pendiente para cuando se aborde ese frente.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regprocedure('public.fn_recalcular_personal_evento(uuid)') is null
     or to_regprocedure('public.fn_recalcular_recursos_evento(uuid)') is null
     or to_regprocedure('public.fn_agregar_equipo_evento(uuid,uuid,uuid,uuid,uuid,text,timestamptz,timestamptz,text)') is null then
    raise exception 'Faltan funciones de 2D-06 — ejecutar primero 2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql';
  end if;

  if to_regclass('public.evento_personal_origen') is null or to_regclass('public.evento_recursos_origen') is null then
    raise exception 'Faltan evento_personal_origen/evento_recursos_origen — ejecutar primero 2026-07-18_mantenciones_etapa2d_05_trazabilidad.sql';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN A — Correcciones a funciones de 2D-06
-- ═══════════════════════════════════════════════════════════════

-- ── A.1 fn_recalcular_personal_evento() — agrega "and origen = 'plantilla'" ──
create or replace function fn_recalcular_personal_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update evento_personal_requerido epr
  set cantidad_sugerida = coalesce((
        select sum(epo.cantidad_aportada)
        from evento_personal_origen epo
        where epo.evento_personal_requerido_id = epr.id
          and epo.estado = 'activo'
      ), 0)
  where epr.evento_mantencion_id = p_evento_id
    and epr.estado_fila <> 'eliminado'
    and epr.origen = 'plantilla';
end;
$$;

-- ── A.2 fn_recalcular_recursos_evento() — mismo criterio ──
create or replace function fn_recalcular_recursos_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update evento_recursos er
  set cantidad_sugerida = coalesce((
        select sum(ero.cantidad_aportada)
        from evento_recursos_origen ero
        where ero.evento_recursos_id = er.id
          and ero.estado = 'activo'
      ), 0)
  where er.evento_mantencion_id = p_evento_id
    and er.estado_fila <> 'eliminado'
    and er.origen = 'plantilla';
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN B — Función reutilizable de estados de revisión
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_actualizar_estado_revision(
  p_evento_id uuid,
  p_ambito    text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total      int;
  v_conformes  int;
  v_nuevo_estado text;
begin
  if p_ambito = 'personal' then
    select count(*),
           count(*) filter (where cantidad_aprobada is not null and cantidad_aprobada = cantidad_sugerida)
      into v_total, v_conformes
      from evento_personal_requerido
      where evento_mantencion_id = p_evento_id and estado_fila <> 'eliminado';
  elsif p_ambito = 'recursos' then
    select count(*),
           count(*) filter (where cantidad_aprobada is not null and cantidad_aprobada = cantidad_sugerida)
      into v_total, v_conformes
      from evento_recursos
      where evento_mantencion_id = p_evento_id and estado_fila <> 'eliminado';
  else
    raise exception 'Ámbito no reconocido: % (debe ser ''personal'' o ''recursos'').', p_ambito;
  end if;

  if v_total = 0 then
    v_nuevo_estado := 'pendiente';
  elsif v_conformes = v_total then
    v_nuevo_estado := 'aprobado';
  elsif v_conformes = 0 then
    v_nuevo_estado := 'en_revision';
  else
    v_nuevo_estado := 'parcial';
  end if;

  if p_ambito = 'personal' then
    update eventos_mantencion set personal_estado = v_nuevo_estado where id = p_evento_id;
  else
    update eventos_mantencion set recursos_estado = v_nuevo_estado where id = p_evento_id;
  end if;
end;
$$;

revoke all on function fn_actualizar_estado_revision(uuid, text) from public, authenticated;

-- ── B.1 fn_agregar_equipo_evento() (2D-06) — su paso 8 ahora usa la
--       función reutilizable de arriba en vez de fijar 'en_revision'
--       directamente. Mismo cuerpo que 2D-06 en todo lo demás. ──
create or replace function fn_agregar_equipo_evento(
  p_evento_id          uuid,
  p_area_id            uuid,
  p_equipo_id          uuid,
  p_tipo_mantencion_id uuid,
  p_plantilla_id       uuid,
  p_criticidad         text default null,
  p_fecha_plan_inicio  timestamptz default null,
  p_fecha_plan_termino timestamptz default null,
  p_observaciones      text default null
)
returns table (mantencion_id uuid, numero text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_cliente_id  uuid;
  v_evento_faena_id    uuid;
  v_evento_estado      text;
  v_evento_supervisor  uuid;
  v_tipo_activo        boolean;
  v_plantilla_activa   boolean;
  v_plantilla_tipo_id  uuid;
  v_plantilla_nombre   text;
  v_plantilla_version  int;
  v_numero             text;
  v_mant_id            uuid;
begin
  if not (tiene_rol('supervisor') or es_admin()) then
    raise exception 'Solo supervisores o administradores pueden agregar equipos a un evento.';
  end if;

  select em.cliente_id, em.faena_id, em.estado, em.supervisor_id
    into v_evento_cliente_id, v_evento_faena_id, v_evento_estado, v_evento_supervisor
    from eventos_mantencion em
    where em.id = p_evento_id;

  if v_evento_faena_id is null then
    raise exception 'El evento de mantención indicado (%) no existe.', p_evento_id;
  end if;

  if v_evento_estado in ('cerrada','cancelada') then
    raise exception 'No se pueden agregar equipos a un evento en estado %.', v_evento_estado;
  end if;

  if auth.uid() <> v_evento_supervisor and not es_admin() then
    raise exception 'Solo el supervisor del evento o un administrador puede agregar equipos.';
  end if;

  perform fn_validar_jerarquia_equipo(v_evento_cliente_id, v_evento_faena_id, p_area_id, p_equipo_id);

  if exists (
    select 1 from mantenciones m
    where m.evento_mantencion_id = p_evento_id
      and m.equipo_id = p_equipo_id
      and m.estado <> 'cancelada'
  ) then
    raise exception 'Este equipo ya tiene una mantención activa dentro de este evento. Cancele la mantención existente antes de volver a agregarlo.';
  end if;

  select tm.activo into v_tipo_activo from tipos_mantencion tm where tm.id = p_tipo_mantencion_id;
  if v_tipo_activo is null then
    raise exception 'Tipo de mantención no encontrado.';
  elsif not v_tipo_activo then
    raise exception 'El tipo de mantención está inactivo.';
  end if;

  select pm.activa, pm.tipo_mantencion_id, pm.nombre, pm.version
    into v_plantilla_activa, v_plantilla_tipo_id, v_plantilla_nombre, v_plantilla_version
    from plantillas_mantencion pm
    where pm.id = p_plantilla_id;
  if v_plantilla_tipo_id is null then
    raise exception 'Plantilla no encontrada.';
  elsif not v_plantilla_activa then
    raise exception 'La plantilla seleccionada está inactiva.';
  elsif v_plantilla_tipo_id <> p_tipo_mantencion_id then
    raise exception 'La plantilla no pertenece al tipo de mantención seleccionado.';
  end if;

  v_numero := fn_generar_numero_mantencion();

  insert into mantenciones as m (
    numero, cliente_id, faena_id, area_id, equipo_id,
    tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
    evento_mantencion_id,
    estado, planificacion_estado, recursos_estado, ejecucion_estado, revision_estado,
    criticidad, fecha_plan_inicio, fecha_plan_termino,
    supervisor_id, observaciones, creado_por
  ) values (
    v_numero, v_evento_cliente_id, v_evento_faena_id, p_area_id, p_equipo_id,
    p_tipo_mantencion_id, p_plantilla_id, v_plantilla_nombre, v_plantilla_version,
    p_evento_id,
    'borrador', 'pendiente', 'pendiente', 'no_iniciada', 'pendiente',
    p_criticidad, p_fecha_plan_inicio, p_fecha_plan_termino,
    v_evento_supervisor, p_observaciones, auth.uid()
  )
  returning m.id into v_mant_id;

  insert into mantencion_actividades (
    mantencion_id, plantilla_actividad_id, codigo_actividad, descripcion, orden,
    depende_de, duracion_estimada_horas, obligatoria, origen, estado_fila, creado_por
  )
  select v_mant_id, pa.id, pa.codigo_actividad, pa.descripcion, pa.orden,
         pa.depende_de, pa.duracion_estimada_horas, pa.obligatoria, 'plantilla', 'sugerido', auth.uid()
  from plantilla_actividades pa
  where pa.plantilla_id = p_plantilla_id;

  insert into mantencion_protocolos (
    mantencion_id, plantilla_protocolo_id, tipo_protocolo, obligatorio, origen, estado_fila, creado_por
  )
  select v_mant_id, ppr.id, ppr.tipo_protocolo, ppr.obligatorio, 'plantilla', 'sugerido', auth.uid()
  from plantilla_protocolos ppr
  where ppr.plantilla_id = p_plantilla_id;

  insert into evento_personal_origen (
    evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
  )
  select cp.evento_personal_requerido_id, v_mant_id, cp.plantilla_personal_id, cp.cantidad, auth.uid()
  from fn_consolidar_personal_evento(p_evento_id, p_plantilla_id) cp;

  insert into evento_recursos_origen (
    evento_recursos_id, mantencion_id, plantilla_recurso_id, cantidad_aportada, creado_por
  )
  select cr.evento_recursos_id, v_mant_id, cr.plantilla_recurso_id, cr.cantidad, auth.uid()
  from fn_consolidar_recursos_evento(p_evento_id, p_plantilla_id) cr;

  perform fn_recalcular_personal_evento(p_evento_id);
  perform fn_recalcular_recursos_evento(p_evento_id);

  -- Paso 8, actualizado: usa la función reutilizable en vez de fijar
  -- 'en_revision' directamente (mismo resultado práctico para un evento
  -- recién creado, pero ahora comparte lógica con fn_quitar_equipo_evento).
  perform fn_actualizar_estado_revision(p_evento_id, 'personal');
  perform fn_actualizar_estado_revision(p_evento_id, 'recursos');

  return query select v_mant_id, v_numero;
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN C — Función privada compartida de permisos
-- ═══════════════════════════════════════════════════════════════

-- fn_validar_supervisor_evento() — evita repetir en cada función de
-- ajuste el mismo bloque de "el evento existe, quien llama es su
-- supervisor o admin, y el evento no está cerrado/cancelado".
create or replace function fn_validar_supervisor_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supervisor_id uuid;
  v_estado        text;
begin
  select supervisor_id, estado into v_supervisor_id, v_estado
    from eventos_mantencion where id = p_evento_id;

  if v_supervisor_id is null then
    raise exception 'El evento de mantención indicado (%) no existe.', p_evento_id;
  end if;

  if auth.uid() <> v_supervisor_id and not es_admin() then
    raise exception 'Solo el supervisor del evento o un administrador puede realizar esta acción.';
  end if;

  if v_estado in ('cerrada','cancelada') then
    raise exception 'No se puede modificar un evento en estado %.', v_estado;
  end if;
end;
$$;

revoke all on function fn_validar_supervisor_evento(uuid) from public, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN D — Motor: quitar un equipo del evento
-- ═══════════════════════════════════════════════════════════════

-- fn_quitar_equipo_evento() — cancela la mantención de un equipo dentro
-- de un evento, RETIRA (nunca borra) sus filas de origen activas, y
-- reutiliza EXACTAMENTE fn_recalcular_personal_evento()/
-- fn_recalcular_recursos_evento() (2D-06) para recomputar
-- cantidad_sugerida — la misma función que usa fn_agregar_equipo_evento.
-- cantidad_aprobada nunca se toca aquí.
create or replace function fn_quitar_equipo_evento(
  p_mantencion_id uuid,
  p_motivo        text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id uuid;
  v_estado    text;
begin
  select evento_mantencion_id, estado into v_evento_id, v_estado
    from mantenciones where id = p_mantencion_id;

  if v_estado is null then
    raise exception 'La mantención indicada (%) no existe.', p_mantencion_id;
  end if;

  if v_evento_id is null then
    raise exception 'Esta mantención no pertenece a ningún evento — no corresponde usar esta función (es para el flujo multiequipo).';
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado in ('cancelada','cerrada') then
    raise exception 'Esta mantención ya está % — no se puede quitar del evento.', v_estado;
  end if;

  update mantenciones
  set estado = 'cancelada'
  where id = p_mantencion_id;

  update evento_personal_origen
  set estado = 'retirado',
      retirado_por = auth.uid(),
      retirado_en = now(),
      motivo_retiro = coalesce(p_motivo, 'Equipo retirado del evento')
  where mantencion_id = p_mantencion_id
    and estado = 'activo';

  update evento_recursos_origen
  set estado = 'retirado',
      retirado_por = auth.uid(),
      retirado_en = now(),
      motivo_retiro = coalesce(p_motivo, 'Equipo retirado del evento')
  where mantencion_id = p_mantencion_id
    and estado = 'activo';

  -- Mismas funciones de recálculo que usa fn_agregar_equipo_evento (2D-06) —
  -- reutilizadas sin duplicar su lógica.
  perform fn_recalcular_personal_evento(v_evento_id);
  perform fn_recalcular_recursos_evento(v_evento_id);

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');
end;
$$;

revoke all on function fn_quitar_equipo_evento(uuid, text) from public;
grant execute on function fn_quitar_equipo_evento(uuid, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN E — Ajuste manual: personal
-- ═══════════════════════════════════════════════════════════════

-- fn_agregar_personal_manual_evento() — alta manual, origen='manual'.
create or replace function fn_agregar_personal_manual_evento(
  p_evento_id         uuid,
  p_perfil            text,
  p_cantidad_sugerida numeric,
  p_especialidad      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform fn_validar_supervisor_evento(p_evento_id);

  if trim(coalesce(p_perfil, '')) = '' then
    raise exception 'Debe indicar un perfil.';
  end if;

  if p_cantidad_sugerida <= 0 then
    raise exception 'La cantidad sugerida debe ser mayor a 0.';
  end if;

  insert into evento_personal_requerido (
    evento_mantencion_id, perfil, especialidad, cantidad_sugerida, origen, estado_fila, creado_por
  ) values (
    p_evento_id, p_perfil, p_especialidad, p_cantidad_sugerida, 'manual', 'agregado', auth.uid()
  )
  returning evento_personal_requerido.id into v_id;

  perform fn_actualizar_estado_revision(p_evento_id, 'personal');

  return v_id;
end;
$$;

revoke all on function fn_agregar_personal_manual_evento(uuid, text, numeric, text) from public;
grant execute on function fn_agregar_personal_manual_evento(uuid, text, numeric, text) to authenticated;

-- fn_quitar_personal_evento() — baja (soft delete) de CUALQUIER línea
-- vigente, sea su origen 'plantilla' o 'manual' — el supervisor puede
-- decidir que ya no se necesita, incluso si varios equipos la sugirieron.
create or replace function fn_quitar_personal_evento(
  p_evento_personal_requerido_id uuid,
  p_motivo_modificacion           text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id   uuid;
  v_estado_fila text;
begin
  select evento_mantencion_id, estado_fila into v_evento_id, v_estado_fila
    from evento_personal_requerido where id = p_evento_personal_requerido_id;

  if v_evento_id is null then
    raise exception 'La línea de personal requerido indicada (%) no existe.', p_evento_personal_requerido_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'Esta línea ya fue eliminada.';
  end if;

  if trim(coalesce(p_motivo_modificacion, '')) = '' then
    raise exception 'Debe indicar un motivo para eliminar esta línea.';
  end if;

  update evento_personal_requerido
  set estado_fila = 'eliminado',
      motivo_modificacion = p_motivo_modificacion
  where id = p_evento_personal_requerido_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
end;
$$;

revoke all on function fn_quitar_personal_evento(uuid, text) from public;
grant execute on function fn_quitar_personal_evento(uuid, text) to authenticated;

-- fn_modificar_personal_manual_evento() — SOLO sobre líneas origen =
-- 'manual'. Una línea 'plantilla' se recalcula sola al agregar/quitar
-- equipos — modificarla a mano rompería esa garantía en el siguiente
-- recálculo.
create or replace function fn_modificar_personal_manual_evento(
  p_evento_personal_requerido_id uuid,
  p_cantidad_sugerida             numeric,
  p_motivo_modificacion            text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id   uuid;
  v_origen      text;
  v_estado_fila text;
begin
  select evento_mantencion_id, origen, estado_fila into v_evento_id, v_origen, v_estado_fila
    from evento_personal_requerido where id = p_evento_personal_requerido_id;

  if v_evento_id is null then
    raise exception 'La línea de personal requerido indicada (%) no existe.', p_evento_personal_requerido_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'No se puede modificar una línea ya eliminada.';
  end if;

  if v_origen <> 'manual' then
    raise exception 'Solo se puede modificar directamente la cantidad sugerida de una línea manual. Las líneas derivadas de plantilla se recalculan automáticamente al agregar o quitar equipos.';
  end if;

  if p_cantidad_sugerida < 0 then
    raise exception 'La cantidad sugerida no puede ser negativa.';
  end if;

  if trim(coalesce(p_motivo_modificacion, '')) = '' then
    raise exception 'Debe indicar un motivo para modificar esta línea.';
  end if;

  update evento_personal_requerido
  set cantidad_sugerida = p_cantidad_sugerida,
      estado_fila = 'modificado',
      motivo_modificacion = p_motivo_modificacion
  where id = p_evento_personal_requerido_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
end;
$$;

revoke all on function fn_modificar_personal_manual_evento(uuid, numeric, text) from public;
grant execute on function fn_modificar_personal_manual_evento(uuid, numeric, text) to authenticated;

-- fn_aprobar_personal_evento() — aprobación de UNA línea (cualquier
-- origen). Si no se indica p_cantidad_aprobada, aprueba exactamente lo
-- sugerido.
create or replace function fn_aprobar_personal_evento(
  p_evento_personal_requerido_id uuid,
  p_cantidad_aprobada             numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id         uuid;
  v_estado_fila       text;
  v_cantidad_sugerida numeric;
  v_cantidad_final    numeric;
begin
  select evento_mantencion_id, estado_fila, cantidad_sugerida
    into v_evento_id, v_estado_fila, v_cantidad_sugerida
    from evento_personal_requerido where id = p_evento_personal_requerido_id;

  if v_evento_id is null then
    raise exception 'La línea de personal requerido indicada (%) no existe.', p_evento_personal_requerido_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'No se puede aprobar una línea eliminada.';
  end if;

  v_cantidad_final := coalesce(p_cantidad_aprobada, v_cantidad_sugerida);

  if v_cantidad_final < 0 then
    raise exception 'La cantidad aprobada no puede ser negativa.';
  end if;

  update evento_personal_requerido
  set cantidad_aprobada = v_cantidad_final,
      aprobado_por = auth.uid(),
      aprobado_en = now()
  where id = p_evento_personal_requerido_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
end;
$$;

revoke all on function fn_aprobar_personal_evento(uuid, numeric) from public;
grant execute on function fn_aprobar_personal_evento(uuid, numeric) to authenticated;

-- fn_aprobar_evento_personal() — aprueba de una vez todas las líneas
-- vigentes que todavía no estén conformes (aprobada = sugerida).
create or replace function fn_aprobar_evento_personal(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform fn_validar_supervisor_evento(p_evento_id);

  update evento_personal_requerido
  set cantidad_aprobada = cantidad_sugerida,
      aprobado_por = auth.uid(),
      aprobado_en = now()
  where evento_mantencion_id = p_evento_id
    and estado_fila <> 'eliminado'
    and cantidad_aprobada is distinct from cantidad_sugerida;

  perform fn_actualizar_estado_revision(p_evento_id, 'personal');
end;
$$;

revoke all on function fn_aprobar_evento_personal(uuid) from public;
grant execute on function fn_aprobar_evento_personal(uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN F — Ajuste manual: recursos (mismo criterio que personal)
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_agregar_recurso_manual_evento(
  p_evento_id          uuid,
  p_categoria_recurso  text,
  p_nombre_generico    text,
  p_cantidad_sugerida  numeric,
  p_herramienta_codigo text default null,
  p_insumo_codigo      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform fn_validar_supervisor_evento(p_evento_id);

  if trim(coalesce(p_nombre_generico, '')) = '' then
    raise exception 'Debe indicar un nombre_generico.';
  end if;

  if p_cantidad_sugerida <= 0 then
    raise exception 'La cantidad sugerida debe ser mayor a 0.';
  end if;

  insert into evento_recursos (
    evento_mantencion_id, categoria_recurso, nombre_generico, herramienta_codigo, insumo_codigo,
    cantidad_sugerida, origen, estado_fila, creado_por
  ) values (
    p_evento_id, p_categoria_recurso, p_nombre_generico, p_herramienta_codigo, p_insumo_codigo,
    p_cantidad_sugerida, 'manual', 'agregado', auth.uid()
  )
  returning evento_recursos.id into v_id;

  perform fn_actualizar_estado_revision(p_evento_id, 'recursos');

  return v_id;
end;
$$;

revoke all on function fn_agregar_recurso_manual_evento(uuid, text, text, numeric, text, text) from public;
grant execute on function fn_agregar_recurso_manual_evento(uuid, text, text, numeric, text, text) to authenticated;

create or replace function fn_quitar_recurso_evento(
  p_evento_recurso_id     uuid,
  p_motivo_modificacion   text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id   uuid;
  v_estado_fila text;
begin
  select evento_mantencion_id, estado_fila into v_evento_id, v_estado_fila
    from evento_recursos where id = p_evento_recurso_id;

  if v_evento_id is null then
    raise exception 'La línea de recursos indicada (%) no existe.', p_evento_recurso_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'Esta línea ya fue eliminada.';
  end if;

  if trim(coalesce(p_motivo_modificacion, '')) = '' then
    raise exception 'Debe indicar un motivo para eliminar esta línea.';
  end if;

  update evento_recursos
  set estado_fila = 'eliminado',
      motivo_modificacion = p_motivo_modificacion
  where id = p_evento_recurso_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');
end;
$$;

revoke all on function fn_quitar_recurso_evento(uuid, text) from public;
grant execute on function fn_quitar_recurso_evento(uuid, text) to authenticated;

create or replace function fn_modificar_recurso_manual_evento(
  p_evento_recurso_id    uuid,
  p_cantidad_sugerida    numeric,
  p_motivo_modificacion  text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id   uuid;
  v_origen      text;
  v_estado_fila text;
begin
  select evento_mantencion_id, origen, estado_fila into v_evento_id, v_origen, v_estado_fila
    from evento_recursos where id = p_evento_recurso_id;

  if v_evento_id is null then
    raise exception 'La línea de recursos indicada (%) no existe.', p_evento_recurso_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'No se puede modificar una línea ya eliminada.';
  end if;

  if v_origen <> 'manual' then
    raise exception 'Solo se puede modificar directamente la cantidad sugerida de una línea manual. Las líneas derivadas de plantilla se recalculan automáticamente al agregar o quitar equipos.';
  end if;

  if p_cantidad_sugerida < 0 then
    raise exception 'La cantidad sugerida no puede ser negativa.';
  end if;

  if trim(coalesce(p_motivo_modificacion, '')) = '' then
    raise exception 'Debe indicar un motivo para modificar esta línea.';
  end if;

  update evento_recursos
  set cantidad_sugerida = p_cantidad_sugerida,
      estado_fila = 'modificado',
      motivo_modificacion = p_motivo_modificacion
  where id = p_evento_recurso_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');
end;
$$;

revoke all on function fn_modificar_recurso_manual_evento(uuid, numeric, text) from public;
grant execute on function fn_modificar_recurso_manual_evento(uuid, numeric, text) to authenticated;

create or replace function fn_aprobar_recurso_evento(
  p_evento_recurso_id  uuid,
  p_cantidad_aprobada  numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id         uuid;
  v_estado_fila       text;
  v_cantidad_sugerida numeric;
  v_cantidad_final    numeric;
begin
  select evento_mantencion_id, estado_fila, cantidad_sugerida
    into v_evento_id, v_estado_fila, v_cantidad_sugerida
    from evento_recursos where id = p_evento_recurso_id;

  if v_evento_id is null then
    raise exception 'La línea de recursos indicada (%) no existe.', p_evento_recurso_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado_fila = 'eliminado' then
    raise exception 'No se puede aprobar una línea eliminada.';
  end if;

  v_cantidad_final := coalesce(p_cantidad_aprobada, v_cantidad_sugerida);

  if v_cantidad_final < 0 then
    raise exception 'La cantidad aprobada no puede ser negativa.';
  end if;

  update evento_recursos
  set cantidad_aprobada = v_cantidad_final,
      aprobado_por = auth.uid(),
      aprobado_en = now()
  where id = p_evento_recurso_id;

  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');
end;
$$;

revoke all on function fn_aprobar_recurso_evento(uuid, numeric) from public;
grant execute on function fn_aprobar_recurso_evento(uuid, numeric) to authenticated;

create or replace function fn_aprobar_evento_recursos(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform fn_validar_supervisor_evento(p_evento_id);

  update evento_recursos
  set cantidad_aprobada = cantidad_sugerida,
      aprobado_por = auth.uid(),
      aprobado_en = now()
  where evento_mantencion_id = p_evento_id
    and estado_fila <> 'eliminado'
    and cantidad_aprobada is distinct from cantidad_sugerida;

  perform fn_actualizar_estado_revision(p_evento_id, 'recursos');
end;
$$;

revoke all on function fn_aprobar_evento_recursos(uuid) from public;
grant execute on function fn_aprobar_evento_recursos(uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Todas las funciones de este archivo y sus privilegios:
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace
--     and p.proname in (
--       'fn_recalcular_personal_evento', 'fn_recalcular_recursos_evento',
--       'fn_agregar_equipo_evento', 'fn_actualizar_estado_revision',
--       'fn_validar_supervisor_evento', 'fn_quitar_equipo_evento',
--       'fn_agregar_personal_manual_evento', 'fn_quitar_personal_evento',
--       'fn_modificar_personal_manual_evento', 'fn_aprobar_personal_evento',
--       'fn_aprobar_evento_personal', 'fn_agregar_recurso_manual_evento',
--       'fn_quitar_recurso_evento', 'fn_modificar_recurso_manual_evento',
--       'fn_aprobar_recurso_evento', 'fn_aprobar_evento_recursos'
--     )
--   order by p.proname;
-- -- fn_actualizar_estado_revision y fn_validar_supervisor_evento deben
-- -- mostrar "false" (privadas); el resto, "true".
--
-- 2) Prueba de punta a punta (con datos reales, dentro de una transacción
--    que termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_ajuste_aprobacion_etapa2d07.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop function if exists public.fn_aprobar_evento_recursos(uuid);
-- drop function if exists public.fn_aprobar_recurso_evento(uuid, numeric);
-- drop function if exists public.fn_modificar_recurso_manual_evento(uuid, numeric, text);
-- drop function if exists public.fn_quitar_recurso_evento(uuid, text);
-- drop function if exists public.fn_agregar_recurso_manual_evento(uuid, text, text, numeric, text, text);
-- drop function if exists public.fn_aprobar_evento_personal(uuid);
-- drop function if exists public.fn_aprobar_personal_evento(uuid, numeric);
-- drop function if exists public.fn_modificar_personal_manual_evento(uuid, numeric, text);
-- drop function if exists public.fn_quitar_personal_evento(uuid, text);
-- drop function if exists public.fn_agregar_personal_manual_evento(uuid, text, numeric, text);
-- drop function if exists public.fn_quitar_equipo_evento(uuid, text);
-- drop function if exists public.fn_validar_supervisor_evento(uuid);
-- drop function if exists public.fn_actualizar_estado_revision(uuid, text);
--
-- -- Revertir fn_agregar_equipo_evento() y las funciones de recálculo a su
-- -- versión de 2D-06 requiere volver a ejecutar el CREATE OR REPLACE de
-- -- ese archivo (2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql).

-- ============================================================
-- ETAPA 2D-07.1 — ASIGNACIÓN DE PERSONAL (TÉCNICOS)
-- Archivo original: 2026-07-18_mantenciones_etapa2d_07_1_asignacion_personal.sql
-- ============================================================

-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.07.1
-- Asignación real de personas — evento_personal_asignado
--
-- PROPÓSITO:
-- Completar evento_personal_asignado (tabla creada en 2D-03, hasta ahora
-- sin ninguna vía de escritura) con las tres funciones controladas para
-- asignar/quitar/modificar personas reales a un evento, y con las
-- garantías de inmutabilidad/historial que le faltaban a nivel de tabla.
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-17_perfiles_roles.sql                    (perfiles_ayca, es_admin(), tiene_rol())
--   - 2026-07-18_mantenciones_etapa2d_03_personal.sql   (evento_personal_asignado,
--                                                          evento_personal_requerido)
--   - 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql
--                                                       (fn_validar_supervisor_evento())
--
-- NO modifica RLS (2D-09). NO toca evento_personal_requerido, evento_recursos
-- ni ninguna función de 2D-06/2D-07 — es un frente independiente sobre una
-- tabla que hasta ahora no tenía ninguna función propia.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regclass('public.perfiles_ayca') is null then
    raise exception 'Falta la tabla perfiles_ayca — ejecutar primero 2026-07-17_perfiles_roles.sql';
  end if;

  if to_regclass('public.evento_personal_asignado') is null then
    raise exception 'Falta la tabla evento_personal_asignado — ejecutar primero 2026-07-18_mantenciones_etapa2d_03_personal.sql';
  end if;

  if to_regprocedure('public.fn_validar_supervisor_evento(uuid)') is null then
    raise exception 'Falta fn_validar_supervisor_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN A — Garantías de tabla que faltaban desde 2D-03
-- ═══════════════════════════════════════════════════════════════

-- ── A.1 Inmutabilidad de usuario_id/evento_mantencion_id ──
-- "No permitir cambiar usuario_id de una asignación existente: para
-- reemplazar una persona, retirar la anterior y crear una nueva." Se
-- aplica a nivel de trigger (no solo omitiendo el parámetro en las
-- funciones) para que la regla valga sin excepción, igual criterio que
-- ya se usó para equipo_id/area_id en mantenciones (2D-02) y para las
-- filas de origen (2D-05).
create or replace function fn_bloquear_cambio_usuario_asignacion()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if NEW.usuario_id <> OLD.usuario_id then
    raise exception 'No se puede cambiar el usuario de una asignación ya creada. Libere esta asignación (fn_quitar_persona_evento) y cree una nueva para la persona correcta.';
  end if;

  if NEW.evento_mantencion_id <> OLD.evento_mantencion_id then
    raise exception 'No se puede cambiar el evento de una asignación ya creada.';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_bloquear_cambio_usuario_asignacion on evento_personal_asignado;
create trigger trg_bloquear_cambio_usuario_asignacion
  before update on evento_personal_asignado
  for each row execute function fn_bloquear_cambio_usuario_asignacion();

-- ── A.2 Prohibir DELETE físico — conserva historial para RLS futura ──
create or replace function fn_bloquear_delete_evento_personal_asignado()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'No se puede eliminar físicamente una asignación — libérela (fn_quitar_persona_evento) para conservar el historial.';
end;
$$;

drop trigger if exists trg_bloquear_delete_evento_personal_asignado on evento_personal_asignado;
create trigger trg_bloquear_delete_evento_personal_asignado
  before delete on evento_personal_asignado
  for each row execute function fn_bloquear_delete_evento_personal_asignado();

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN B — fn_asignar_persona_evento()
-- ═══════════════════════════════════════════════════════════════

-- "Habilitado" se define como: existe en auth.users Y tiene una fila en
-- perfiles_ayca con activo = true. Un usuario sin fila en perfiles_ayca
-- se trata como NO habilitado (falla cerrado) — perfiles_ayca es la
-- única fuente de "activo/inactivo" que existe hoy en el esquema.
create or replace function fn_asignar_persona_evento(
  p_evento_id                    uuid,
  p_usuario_id                   uuid,
  p_perfil                       text,
  p_especialidad                 text default null,
  p_evento_personal_requerido_id uuid default null,
  p_estado_asignacion            text default 'propuesto',
  p_fecha_desde                  timestamptz default null,
  p_fecha_hasta                  timestamptz default null,
  p_observaciones                text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario_activo  boolean;
  v_req_evento_id   uuid;
  v_req_estado_fila text;
  v_id              uuid;
begin
  -- Evento existe, quien llama es su supervisor/admin, evento no
  -- cerrado/cancelado — reutiliza fn_validar_supervisor_evento (2D-07),
  -- cubre "impedir asignaciones en eventos cancelados o cerrados".
  perform fn_validar_supervisor_evento(p_evento_id);

  if not exists (select 1 from auth.users u where u.id = p_usuario_id) then
    raise exception 'El usuario indicado no existe.';
  end if;

  select pa.activo into v_usuario_activo from perfiles_ayca pa where pa.id = p_usuario_id;
  if v_usuario_activo is null then
    raise exception 'El usuario indicado no tiene un perfil habilitado en el sistema (perfiles_ayca).';
  elsif not v_usuario_activo then
    raise exception 'El usuario indicado está inactivo.';
  end if;

  -- Validado aquí ADEMÁS del trigger de 2D-03 (fn_validar_evento_personal_asignado)
  -- — mismo criterio de no confiar solo en la restricción de base, con
  -- mensaje claro antes de intentar el insert.
  if p_evento_personal_requerido_id is not null then
    select epr.evento_mantencion_id, epr.estado_fila
      into v_req_evento_id, v_req_estado_fila
      from evento_personal_requerido epr
      where epr.id = p_evento_personal_requerido_id;

    if v_req_evento_id is null then
      raise exception 'La línea de personal requerido indicada (%) no existe.', p_evento_personal_requerido_id;
    end if;

    if v_req_evento_id <> p_evento_id then
      raise exception 'La línea de personal requerido indicada pertenece a otro evento.';
    end if;

    if v_req_estado_fila = 'eliminado' then
      raise exception 'No se puede asignar personal a una línea de personal requerido que fue eliminada.';
    end if;
  end if;
  -- Si p_evento_personal_requerido_id es null, no se valida nada más:
  -- es una asignación extraordinaria, permitida a propósito.

  if exists (
    select 1 from evento_personal_asignado epa
    where epa.evento_mantencion_id = p_evento_id
      and epa.usuario_id = p_usuario_id
      and epa.estado_asignacion <> 'liberado'
  ) then
    raise exception 'Este usuario ya tiene una asignación vigente en este evento. Libere la asignación existente antes de crear una nueva.';
  end if;

  if trim(coalesce(p_perfil, '')) = '' then
    raise exception 'Debe indicar un perfil.';
  end if;

  if p_estado_asignacion = 'liberado' then
    raise exception 'No se puede crear una asignación ya liberada — asigne normalmente y libere después si corresponde.';
  end if;

  insert into evento_personal_asignado (
    evento_mantencion_id, evento_personal_requerido_id, usuario_id, perfil, especialidad,
    estado_asignacion, fecha_desde, fecha_hasta, observaciones, creado_por
  ) values (
    p_evento_id, p_evento_personal_requerido_id, p_usuario_id, p_perfil, p_especialidad,
    coalesce(p_estado_asignacion, 'propuesto'), p_fecha_desde, p_fecha_hasta, p_observaciones, auth.uid()
  )
  returning evento_personal_asignado.id into v_id;

  return v_id;
end;
$$;

revoke all on function fn_asignar_persona_evento(uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text) from public;
grant execute on function fn_asignar_persona_evento(uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN C — fn_quitar_persona_evento()
-- ═══════════════════════════════════════════════════════════════

-- No existe una columna "motivo_retiro" en evento_personal_asignado (a
-- diferencia de evento_personal_origen, 2D-05) — el motivo exigido se
-- registra en "observaciones" (se concatena si ya había algo escrito).
-- fecha_hasta se fija a now() si todavía no tenía una, para que el
-- campo refleje cuándo terminó realmente la asignación.
create or replace function fn_quitar_persona_evento(
  p_asignacion_id uuid,
  p_motivo        text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id  uuid;
  v_estado     text;
  v_obs_actual text;
begin
  select evento_mantencion_id, estado_asignacion, observaciones
    into v_evento_id, v_estado, v_obs_actual
    from evento_personal_asignado where id = p_asignacion_id;

  if v_evento_id is null then
    raise exception 'La asignación indicada (%) no existe.', p_asignacion_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado = 'liberado' then
    raise exception 'Esta asignación ya fue liberada.';
  end if;

  if trim(coalesce(p_motivo, '')) = '' then
    raise exception 'Debe indicar un motivo para liberar esta asignación.';
  end if;

  update evento_personal_asignado
  set estado_asignacion = 'liberado',
      fecha_hasta = coalesce(fecha_hasta, now()),
      observaciones = case
        when v_obs_actual is null or trim(v_obs_actual) = '' then 'Retirado: ' || p_motivo
        else v_obs_actual || ' | Retirado: ' || p_motivo
      end
  where id = p_asignacion_id;
end;
$$;

revoke all on function fn_quitar_persona_evento(uuid, text) from public;
grant execute on function fn_quitar_persona_evento(uuid, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN D — fn_modificar_asignacion_evento()
-- ═══════════════════════════════════════════════════════════════

-- Actualiza SOLO estado_asignacion (excepto 'liberado' — eso es
-- responsabilidad exclusiva de fn_quitar_persona_evento, que exige
-- motivo), fecha_desde, fecha_hasta y observaciones. NO acepta
-- usuario_id como parámetro — ni siquiera existe la posibilidad de
-- pasarlo, coherente con el trigger de la Sección A.1.
create or replace function fn_modificar_asignacion_evento(
  p_asignacion_id     uuid,
  p_estado_asignacion text default null,
  p_fecha_desde       timestamptz default null,
  p_fecha_hasta       timestamptz default null,
  p_observaciones     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id uuid;
  v_estado    text;
begin
  select evento_mantencion_id, estado_asignacion into v_evento_id, v_estado
    from evento_personal_asignado where id = p_asignacion_id;

  if v_evento_id is null then
    raise exception 'La asignación indicada (%) no existe.', p_asignacion_id;
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado = 'liberado' then
    raise exception 'No se puede modificar una asignación ya liberada.';
  end if;

  if p_estado_asignacion = 'liberado' then
    raise exception 'Use fn_quitar_persona_evento() para liberar una asignación — exige motivo.';
  end if;

  if p_estado_asignacion is not null and p_estado_asignacion not in ('propuesto','confirmado','en_terreno') then
    raise exception 'estado_asignacion inválido: %.', p_estado_asignacion;
  end if;

  update evento_personal_asignado
  set estado_asignacion = coalesce(p_estado_asignacion, estado_asignacion),
      fecha_desde       = coalesce(p_fecha_desde, fecha_desde),
      fecha_hasta       = coalesce(p_fecha_hasta, fecha_hasta),
      observaciones     = coalesce(p_observaciones, observaciones)
  where id = p_asignacion_id;
end;
$$;

revoke all on function fn_modificar_asignacion_evento(uuid, text, timestamptz, timestamptz, text) from public;
grant execute on function fn_modificar_asignacion_evento(uuid, text, timestamptz, timestamptz, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) Funciones y privilegios:
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace
--     and p.proname in ('fn_asignar_persona_evento', 'fn_quitar_persona_evento', 'fn_modificar_asignacion_evento')
--   order by p.proname;
--
-- 2) Triggers activos sobre evento_personal_asignado (deben ser 4: la
--    auditoría y la validación de 2D-03, más las dos nuevas de aquí):
-- select tgname from pg_trigger
--   where tgrelid = 'public.evento_personal_asignado'::regclass and not tgisinternal
--   order by tgname;
--
-- 3) Prueba de punta a punta (con datos reales, dentro de una transacción
--    que termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_asignacion_personal_etapa2d071.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop function if exists public.fn_modificar_asignacion_evento(uuid, text, timestamptz, timestamptz, text);
-- drop function if exists public.fn_quitar_persona_evento(uuid, text);
-- drop function if exists public.fn_asignar_persona_evento(uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text);
-- drop trigger if exists trg_bloquear_delete_evento_personal_asignado on public.evento_personal_asignado;
-- drop function if exists public.fn_bloquear_delete_evento_personal_asignado();
-- drop trigger if exists trg_bloquear_cambio_usuario_asignacion on public.evento_personal_asignado;
-- drop function if exists public.fn_bloquear_cambio_usuario_asignacion();

-- ============================================================
-- ETAPA 2D-08 — ROLLUP DE ESTADOS
-- Archivo original: 2026-07-18_mantenciones_etapa2d_08_rollup_estados.sql
-- ============================================================

-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.08
-- Rollup automático de estados del evento
--
-- PROPÓSITO:
-- Derivar automáticamente "estado", "ejecucion_estado" y "revision_estado"
-- de eventos_mantencion a partir de sus mantenciones hijas VIGENTES
-- (estado <> 'cancelada'), en vez de dejarlos como campos de escritura
-- libre. "planificacion_estado" NO se toca — sigue siendo de uso manual
-- del planificador.
--
-- ── CAMBIO DE VOCABULARIO (decisión explícita, ver conversación) ──
-- El CHECK de estado/ejecucion_estado/revision_estado en eventos_mantencion
-- (2D-01) usaba un vocabulario que no alcanzaba a cubrir las reglas de
-- rollup pedidas aquí, y que además chocaba con dos CHECK cruzados que
-- asumían un modelo distinto (estado cambiando solo a mano, en conjunto
-- con los demás campos). Se editó 2D-01 directamente (todavía no
-- ejecutado en ningún ambiente) para:
--   - estado:           borrador / planificado / en_ejecucion / finalizado / cancelado
--   - ejecucion_estado:  sin_equipos / pendiente / en_ejecucion / parcial / completado
--   - revision_estado:   pendiente / en_revision / parcial / aprobado / no_aplica
--   - Eliminar los 2 CHECK cruzados que ya no aplican con rollup automático.
-- Como consecuencia, esta migración también actualiza (CREATE OR REPLACE)
-- fn_validar_supervisor_evento(), fn_agregar_equipo_evento() y
-- fn_quitar_equipo_evento() (2D-07), que comparaban el estado del evento
-- contra 'cerrada'/'cancelada' — ahora comparan contra
-- 'finalizado'/'cancelado'. Ningún otro comportamiento de esas funciones
-- cambia.
--
-- ── DISEÑO: 3 funciones puras de cálculo + 1 función que aplica ──
-- fn_calcular_ejecucion_estado_evento(evento_id) → text
-- fn_calcular_estado_evento(evento_id)           → text  (reutiliza la anterior)
-- fn_calcular_revision_estado_evento(evento_id)  → text
-- Ninguna de las tres escribe nada — solo calculan, a partir del estado
-- ACTUAL de las mantenciones hijas y de personal_estado/recursos_estado.
-- Son la lógica "reutilizable" pedida: cualquier función futura puede
-- llamarlas para saber qué debería valer un campo, sin duplicar reglas.
--
-- fn_recalcular_estados_evento(evento_id) → void   (privada)
-- Es la única que ESCRIBE los 3 campos, y la única que aplica la regla
-- "no sobrescribir un evento cancelado": si eventos_mantencion.estado ya
-- es 'cancelado', no hace nada. 'cancelado' es un estado terminal que
-- solo se alcanza por una función explícita de cancelación de evento
-- (todavía no existe esa función — cuando se cree, será la única vía).
--
-- ── DÓNDE SE INTEGRA (sin duplicar la integración en 10+ funciones) ──
-- fn_actualizar_estado_revision() (2D-07) YA es el único punto de
-- escritura de personal_estado/recursos_estado, y YA es llamada al
-- final de las 10 funciones de ajuste/aprobación de personal y recursos
-- (2D-07) más fn_agregar_equipo_evento()/fn_quitar_equipo_evento(). Se
-- extiende aquí (CREATE OR REPLACE, misma firma) para que, además de
-- fijar personal_estado o recursos_estado, recalcule también
-- revision_estado con fn_calcular_revision_estado_evento() — así las
-- "operaciones de aprobación que afecten revisión" (y también agregar/
-- quitar/modificar personal o recursos, que son las mismas que ya
-- llaman a esta función) quedan cubiertas SIN tocar esas 10 funciones
-- una por una.
-- estado/ejecucion_estado NO dependen de personal_estado/recursos_estado
-- (solo de las mantenciones hijas), así que no tiene sentido recalcularlos
-- ahí — se integran explícitamente, como pide el enunciado, al FINAL de
-- fn_agregar_equipo_evento() y fn_quitar_equipo_evento() (las únicas dos
-- funciones que agregan o quitan mantenciones hijas), con una llamada a
-- fn_recalcular_estados_evento().
--
-- DEPENDENCIAS (deben existir ANTES de ejecutar este archivo):
--   - 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql (YA EDITADO
--     con el vocabulario nuevo — re-ejecutar si ya se había corrido antes)
--   - 2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql
--   - 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql
--
-- NO modifica RLS (2D-09). NO crea una función de cancelación explícita
-- de evento (fuera de alcance de esta etapa) — el rollup simplemente
-- respeta 'cancelado' como terminal si algo más lo pone en ese estado.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regprocedure('public.fn_actualizar_estado_revision(uuid,text)') is null then
    raise exception 'Falta fn_actualizar_estado_revision() — ejecutar primero 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql';
  end if;

  if to_regprocedure('public.fn_validar_supervisor_evento(uuid)') is null then
    raise exception 'Falta fn_validar_supervisor_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql';
  end if;

  if to_regprocedure('public.fn_agregar_equipo_evento(uuid,uuid,uuid,uuid,uuid,text,timestamptz,timestamptz,text)') is null then
    raise exception 'Falta fn_agregar_equipo_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_06_funciones_creacion.sql';
  end if;

  if to_regprocedure('public.fn_quitar_equipo_evento(uuid,text)') is null then
    raise exception 'Falta fn_quitar_equipo_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.eventos_mantencion'::regclass
      and conname = 'eventos_mantencion_estado_check'
  ) then
    raise exception 'El CHECK de eventos_mantencion.estado todavía tiene el vocabulario antiguo — volver a ejecutar 2026-07-18_mantenciones_etapa2d_01_eventos_numeracion.sql (ya editado) antes de este archivo.';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN A — Funciones puras de cálculo (no escriben nada)
-- ═══════════════════════════════════════════════════════════════

-- fn_calcular_ejecucion_estado_evento() — a partir del ejecucion_estado
-- de las mantenciones VIGENTES (estado <> 'cancelada') del evento:
--   sin_equipos → no hay mantenciones vigentes.
--   en_ejecucion → al menos una está 'en_curso' ahora mismo (prioridad
--                  máxima: si algo está corriendo, el evento está en
--                  ejecución, sin importar el resto).
--   completado  → TODAS están 'completada'.
--   pendiente   → TODAS están 'no_iniciada'.
--   parcial     → cualquier otra mezcla (ej. completada + no_iniciada,
--                  o alguna 'pausada') — algo avanzó pero nada corre
--                  ahora mismo y no todo terminó.
create or replace function fn_calcular_ejecucion_estado_evento(p_evento_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total        int;
  v_en_curso     int;
  v_completadas  int;
  v_no_iniciadas int;
begin
  select count(*),
         count(*) filter (where m.ejecucion_estado = 'en_curso'),
         count(*) filter (where m.ejecucion_estado = 'completada'),
         count(*) filter (where m.ejecucion_estado = 'no_iniciada')
    into v_total, v_en_curso, v_completadas, v_no_iniciadas
    from mantenciones m
    where m.evento_mantencion_id = p_evento_id
      and m.estado <> 'cancelada';

  if v_total = 0 then
    return 'sin_equipos';
  elsif v_en_curso > 0 then
    return 'en_ejecucion';
  elsif v_completadas = v_total then
    return 'completado';
  elsif v_no_iniciadas = v_total then
    return 'pendiente';
  else
    return 'parcial';
  end if;
end;
$$;

revoke all on function fn_calcular_ejecucion_estado_evento(uuid) from public, authenticated;

-- fn_calcular_estado_evento() — mapeo DIRECTO desde ejecucion_estado
-- (reutiliza fn_calcular_ejecucion_estado_evento en vez de repetir el
-- conteo): 'en_ejecucion' y 'parcial' del ejecucion_estado colapsan en
-- el único estado intermedio 'en_ejecucion' del evento — el enunciado
-- pide solo 4 valores automáticos (borrador/planificado/en_ejecucion/
-- finalizado), no 5, así que cualquier mezcla que no sea "todo pendiente"
-- ni "todo completado" cae en 'en_ejecucion'. 'cancelado' NUNCA se
-- calcula aquí — solo por acción explícita (ver fn_recalcular_estados_evento).
create or replace function fn_calcular_estado_evento(p_evento_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ejecucion text;
begin
  v_ejecucion := fn_calcular_ejecucion_estado_evento(p_evento_id);

  return case v_ejecucion
    when 'sin_equipos' then 'borrador'
    when 'pendiente'   then 'planificado'
    when 'completado'  then 'finalizado'
    else 'en_ejecucion' -- cubre 'en_ejecucion' y 'parcial'
  end;
end;
$$;

revoke all on function fn_calcular_estado_evento(uuid) from public, authenticated;

-- fn_calcular_revision_estado_evento() — combina TRES señales de
-- revisión en una sola: el revision_estado de cada mantención vigente
-- ('aprobada' cuenta como conforme; cualquier otro valor no), y
-- personal_estado/recursos_estado del propio evento ('aprobado' cuenta
-- como conforme). Cada mantención vigente aporta 1 unidad; personal y
-- recursos SIEMPRE aportan 1 unidad cada uno (así haya o no mantenciones).
--
-- Interpretación de "pendiente" vs. "en_revision" (el enunciado no
-- especifica el límite exacto entre ambos, así que se deja documentado
-- el criterio adoptado): "pendiente" es el caso más estricto de
-- "nada conforme" — CUALQUIER señal ya tocada (una mantención en
-- 'en_revision'/'observada', o personal/recursos ya en 'en_revision' o
-- 'parcial') sube a "en_revision" en vez de "pendiente", porque indica
-- que ya empezó actividad de revisión aunque nada esté aprobado todavía.
create or replace function fn_calcular_revision_estado_evento(p_evento_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_personal_estado text;
  v_recursos_estado text;
  v_mant_total       int;
  v_mant_aprobadas   int;
  v_mant_baseline    int; -- vigentes con revision_estado = 'pendiente'
  v_total_unidades   int;
  v_conformes        int;
  v_todo_en_baseline boolean;
begin
  select em.personal_estado, em.recursos_estado
    into v_personal_estado, v_recursos_estado
    from eventos_mantencion em
    where em.id = p_evento_id;

  select count(*),
         count(*) filter (where m.revision_estado = 'aprobada'),
         count(*) filter (where m.revision_estado = 'pendiente')
    into v_mant_total, v_mant_aprobadas, v_mant_baseline
    from mantenciones m
    where m.evento_mantencion_id = p_evento_id
      and m.estado <> 'cancelada';

  -- Evento realmente vacío: sin mantenciones vigentes y sin personal ni
  -- recursos consolidados todavía — no hay nada que revisar.
  if v_mant_total = 0 and v_personal_estado = 'pendiente' and v_recursos_estado = 'pendiente' then
    return 'no_aplica';
  end if;

  v_total_unidades := v_mant_total + 2; -- +1 personal, +1 recursos, siempre
  v_conformes := v_mant_aprobadas
    + (case when v_personal_estado = 'aprobado' then 1 else 0 end)
    + (case when v_recursos_estado = 'aprobado' then 1 else 0 end);

  if v_conformes = v_total_unidades then
    return 'aprobado';
  end if;

  v_todo_en_baseline := (v_mant_baseline = v_mant_total)
    and v_personal_estado = 'pendiente'
    and v_recursos_estado = 'pendiente';

  if v_conformes = 0 and v_todo_en_baseline then
    return 'pendiente';
  elsif v_conformes = 0 then
    return 'en_revision';
  else
    return 'parcial';
  end if;
end;
$$;

revoke all on function fn_calcular_revision_estado_evento(uuid) from public, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN B — Aplicación (única función que escribe estado/ejecucion_estado/revision_estado)
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_recalcular_estados_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado_actual text;
begin
  select em.estado into v_estado_actual from eventos_mantencion em where em.id = p_evento_id;

  if v_estado_actual is null then
    raise exception 'El evento de mantención indicado (%) no existe.', p_evento_id;
  end if;

  -- No sobrescribir un evento cancelado mediante rollup automático.
  if v_estado_actual = 'cancelado' then
    return;
  end if;

  update eventos_mantencion
  set estado           = fn_calcular_estado_evento(p_evento_id),
      ejecucion_estado = fn_calcular_ejecucion_estado_evento(p_evento_id),
      revision_estado  = fn_calcular_revision_estado_evento(p_evento_id)
  where id = p_evento_id;
end;
$$;

revoke all on function fn_recalcular_estados_evento(uuid) from public, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN C — Integración: extender fn_actualizar_estado_revision (2D-07)
-- para que también recalcule revision_estado
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_actualizar_estado_revision(
  p_evento_id uuid,
  p_ambito    text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total      int;
  v_conformes  int;
  v_nuevo_estado text;
begin
  if p_ambito = 'personal' then
    select count(*),
           count(*) filter (where cantidad_aprobada is not null and cantidad_aprobada = cantidad_sugerida)
      into v_total, v_conformes
      from evento_personal_requerido
      where evento_mantencion_id = p_evento_id and estado_fila <> 'eliminado';
  elsif p_ambito = 'recursos' then
    select count(*),
           count(*) filter (where cantidad_aprobada is not null and cantidad_aprobada = cantidad_sugerida)
      into v_total, v_conformes
      from evento_recursos
      where evento_mantencion_id = p_evento_id and estado_fila <> 'eliminado';
  else
    raise exception 'Ámbito no reconocido: % (debe ser ''personal'' o ''recursos'').', p_ambito;
  end if;

  if v_total = 0 then
    v_nuevo_estado := 'pendiente';
  elsif v_conformes = v_total then
    v_nuevo_estado := 'aprobado';
  elsif v_conformes = 0 then
    v_nuevo_estado := 'en_revision';
  else
    v_nuevo_estado := 'parcial';
  end if;

  if p_ambito = 'personal' then
    update eventos_mantencion set personal_estado = v_nuevo_estado where id = p_evento_id;
  else
    update eventos_mantencion set recursos_estado = v_nuevo_estado where id = p_evento_id;
  end if;

  -- 2D-08: revision_estado combina personal_estado + recursos_estado +
  -- revisión de mantenciones — se recalcula aquí, en el único punto de
  -- escritura de personal_estado/recursos_estado, para que las 10
  -- funciones de ajuste/aprobación de 2D-07 (y fn_agregar_equipo_evento/
  -- fn_quitar_equipo_evento, que también llaman a esta función) queden
  -- cubiertas sin duplicar la integración en cada una.
  update eventos_mantencion
  set revision_estado = fn_calcular_revision_estado_evento(p_evento_id)
  where id = p_evento_id;
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN D — Actualizar vocabulario 'cerrada'/'cancelada' → 'finalizado'/'cancelado'
-- en las funciones que comparan contra el estado del EVENTO, e integrar
-- el rollup completo al final de agregar/quitar equipo
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_validar_supervisor_evento(p_evento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supervisor_id uuid;
  v_estado        text;
begin
  select supervisor_id, estado into v_supervisor_id, v_estado
    from eventos_mantencion where id = p_evento_id;

  if v_supervisor_id is null then
    raise exception 'El evento de mantención indicado (%) no existe.', p_evento_id;
  end if;

  if auth.uid() <> v_supervisor_id and not es_admin() then
    raise exception 'Solo el supervisor del evento o un administrador puede realizar esta acción.';
  end if;

  if v_estado in ('finalizado','cancelado') then
    raise exception 'No se puede modificar un evento en estado %.', v_estado;
  end if;
end;
$$;

-- fn_agregar_equipo_evento(): mismo cuerpo que 2D-07, con dos cambios
-- puntuales — (a) 'cerrada'/'cancelada' → 'finalizado'/'cancelado' al
-- validar el estado del evento, (b) llamada a fn_recalcular_estados_evento()
-- al final, para que estado/ejecucion_estado también reflejen la
-- mantención recién agregada.
create or replace function fn_agregar_equipo_evento(
  p_evento_id          uuid,
  p_area_id            uuid,
  p_equipo_id          uuid,
  p_tipo_mantencion_id uuid,
  p_plantilla_id       uuid,
  p_criticidad         text default null,
  p_fecha_plan_inicio  timestamptz default null,
  p_fecha_plan_termino timestamptz default null,
  p_observaciones      text default null
)
returns table (mantencion_id uuid, numero text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_cliente_id  uuid;
  v_evento_faena_id    uuid;
  v_evento_estado      text;
  v_evento_supervisor  uuid;
  v_tipo_activo        boolean;
  v_plantilla_activa   boolean;
  v_plantilla_tipo_id  uuid;
  v_plantilla_nombre   text;
  v_plantilla_version  int;
  v_numero             text;
  v_mant_id            uuid;
begin
  if not (tiene_rol('supervisor') or es_admin()) then
    raise exception 'Solo supervisores o administradores pueden agregar equipos a un evento.';
  end if;

  select em.cliente_id, em.faena_id, em.estado, em.supervisor_id
    into v_evento_cliente_id, v_evento_faena_id, v_evento_estado, v_evento_supervisor
    from eventos_mantencion em
    where em.id = p_evento_id;

  if v_evento_faena_id is null then
    raise exception 'El evento de mantención indicado (%) no existe.', p_evento_id;
  end if;

  if v_evento_estado in ('finalizado','cancelado') then
    raise exception 'No se pueden agregar equipos a un evento en estado %.', v_evento_estado;
  end if;

  if auth.uid() <> v_evento_supervisor and not es_admin() then
    raise exception 'Solo el supervisor del evento o un administrador puede agregar equipos.';
  end if;

  perform fn_validar_jerarquia_equipo(v_evento_cliente_id, v_evento_faena_id, p_area_id, p_equipo_id);

  if exists (
    select 1 from mantenciones m
    where m.evento_mantencion_id = p_evento_id
      and m.equipo_id = p_equipo_id
      and m.estado <> 'cancelada'
  ) then
    raise exception 'Este equipo ya tiene una mantención activa dentro de este evento. Cancele la mantención existente antes de volver a agregarlo.';
  end if;

  select tm.activo into v_tipo_activo from tipos_mantencion tm where tm.id = p_tipo_mantencion_id;
  if v_tipo_activo is null then
    raise exception 'Tipo de mantención no encontrado.';
  elsif not v_tipo_activo then
    raise exception 'El tipo de mantención está inactivo.';
  end if;

  select pm.activa, pm.tipo_mantencion_id, pm.nombre, pm.version
    into v_plantilla_activa, v_plantilla_tipo_id, v_plantilla_nombre, v_plantilla_version
    from plantillas_mantencion pm
    where pm.id = p_plantilla_id;
  if v_plantilla_tipo_id is null then
    raise exception 'Plantilla no encontrada.';
  elsif not v_plantilla_activa then
    raise exception 'La plantilla seleccionada está inactiva.';
  elsif v_plantilla_tipo_id <> p_tipo_mantencion_id then
    raise exception 'La plantilla no pertenece al tipo de mantención seleccionado.';
  end if;

  v_numero := fn_generar_numero_mantencion();

  insert into mantenciones as m (
    numero, cliente_id, faena_id, area_id, equipo_id,
    tipo_mantencion_id, plantilla_id, nombre_plantilla, version_plantilla,
    evento_mantencion_id,
    estado, planificacion_estado, recursos_estado, ejecucion_estado, revision_estado,
    criticidad, fecha_plan_inicio, fecha_plan_termino,
    supervisor_id, observaciones, creado_por
  ) values (
    v_numero, v_evento_cliente_id, v_evento_faena_id, p_area_id, p_equipo_id,
    p_tipo_mantencion_id, p_plantilla_id, v_plantilla_nombre, v_plantilla_version,
    p_evento_id,
    'borrador', 'pendiente', 'pendiente', 'no_iniciada', 'pendiente',
    p_criticidad, p_fecha_plan_inicio, p_fecha_plan_termino,
    v_evento_supervisor, p_observaciones, auth.uid()
  )
  returning m.id into v_mant_id;

  insert into mantencion_actividades (
    mantencion_id, plantilla_actividad_id, codigo_actividad, descripcion, orden,
    depende_de, duracion_estimada_horas, obligatoria, origen, estado_fila, creado_por
  )
  select v_mant_id, pa.id, pa.codigo_actividad, pa.descripcion, pa.orden,
         pa.depende_de, pa.duracion_estimada_horas, pa.obligatoria, 'plantilla', 'sugerido', auth.uid()
  from plantilla_actividades pa
  where pa.plantilla_id = p_plantilla_id;

  insert into mantencion_protocolos (
    mantencion_id, plantilla_protocolo_id, tipo_protocolo, obligatorio, origen, estado_fila, creado_por
  )
  select v_mant_id, ppr.id, ppr.tipo_protocolo, ppr.obligatorio, 'plantilla', 'sugerido', auth.uid()
  from plantilla_protocolos ppr
  where ppr.plantilla_id = p_plantilla_id;

  insert into evento_personal_origen (
    evento_personal_requerido_id, mantencion_id, plantilla_personal_id, cantidad_aportada, creado_por
  )
  select cp.evento_personal_requerido_id, v_mant_id, cp.plantilla_personal_id, cp.cantidad, auth.uid()
  from fn_consolidar_personal_evento(p_evento_id, p_plantilla_id) cp;

  insert into evento_recursos_origen (
    evento_recursos_id, mantencion_id, plantilla_recurso_id, cantidad_aportada, creado_por
  )
  select cr.evento_recursos_id, v_mant_id, cr.plantilla_recurso_id, cr.cantidad, auth.uid()
  from fn_consolidar_recursos_evento(p_evento_id, p_plantilla_id) cr;

  perform fn_recalcular_personal_evento(p_evento_id);
  perform fn_recalcular_recursos_evento(p_evento_id);

  perform fn_actualizar_estado_revision(p_evento_id, 'personal');
  perform fn_actualizar_estado_revision(p_evento_id, 'recursos');

  -- 2D-08: recalcula estado/ejecucion_estado/revision_estado a partir de
  -- TODAS las mantenciones hijas vigentes, incluida la recién creada.
  perform fn_recalcular_estados_evento(p_evento_id);

  return query select v_mant_id, v_numero;
end;
$$;

-- fn_quitar_equipo_evento(): mismo cuerpo que 2D-07, agregando la
-- llamada a fn_recalcular_estados_evento() al final (la comparación
-- v_estado in ('cancelada','cerrada') de aquí es sobre el estado de la
-- MANTENCIÓN, no del evento — ese vocabulario no cambió, sigue siendo
-- el de 2B/2C).
create or replace function fn_quitar_equipo_evento(
  p_mantencion_id uuid,
  p_motivo        text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento_id uuid;
  v_estado    text;
begin
  select evento_mantencion_id, estado into v_evento_id, v_estado
    from mantenciones where id = p_mantencion_id;

  if v_estado is null then
    raise exception 'La mantención indicada (%) no existe.', p_mantencion_id;
  end if;

  if v_evento_id is null then
    raise exception 'Esta mantención no pertenece a ningún evento — no corresponde usar esta función (es para el flujo multiequipo).';
  end if;

  perform fn_validar_supervisor_evento(v_evento_id);

  if v_estado in ('cancelada','cerrada') then
    raise exception 'Esta mantención ya está % — no se puede quitar del evento.', v_estado;
  end if;

  update mantenciones
  set estado = 'cancelada'
  where id = p_mantencion_id;

  update evento_personal_origen
  set estado = 'retirado',
      retirado_por = auth.uid(),
      retirado_en = now(),
      motivo_retiro = coalesce(p_motivo, 'Equipo retirado del evento')
  where mantencion_id = p_mantencion_id
    and estado = 'activo';

  update evento_recursos_origen
  set estado = 'retirado',
      retirado_por = auth.uid(),
      retirado_en = now(),
      motivo_retiro = coalesce(p_motivo, 'Equipo retirado del evento')
  where mantencion_id = p_mantencion_id
    and estado = 'activo';

  perform fn_recalcular_personal_evento(v_evento_id);
  perform fn_recalcular_recursos_evento(v_evento_id);

  perform fn_actualizar_estado_revision(v_evento_id, 'personal');
  perform fn_actualizar_estado_revision(v_evento_id, 'recursos');

  -- 2D-08: recalcula estado/ejecucion_estado/revision_estado — el equipo
  -- retirado ya no cuenta como vigente para ninguno de los 3.
  perform fn_recalcular_estados_evento(v_evento_id);
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) CHECK de eventos_mantencion con el vocabulario nuevo:
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conrelid = 'public.eventos_mantencion'::regclass
--     and conname in ('eventos_mantencion_estado_check','eventos_mantencion_ejecucion_estado_check','eventos_mantencion_revision_estado_check');
--
-- 2) Funciones de este archivo y sus privilegios:
-- select p.proname, has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace
--     and p.proname in (
--       'fn_calcular_estado_evento','fn_calcular_ejecucion_estado_evento',
--       'fn_calcular_revision_estado_evento','fn_recalcular_estados_evento'
--     )
--   order by p.proname;
-- -- Las 4 deben mostrar "false" (privadas).
--
-- 3) Prueba de punta a punta (con datos reales, dentro de una transacción
--    que termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_rollup_estados_etapa2d08.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- -- Revertir fn_agregar_equipo_evento()/fn_quitar_equipo_evento()/
-- -- fn_validar_supervisor_evento()/fn_actualizar_estado_revision() a su
-- -- versión de 2D-07 requiere volver a ejecutar el CREATE OR REPLACE de
-- -- 2026-07-18_mantenciones_etapa2d_07_funciones_ajuste_aprobacion.sql.
-- drop function if exists public.fn_recalcular_estados_evento(uuid);
-- drop function if exists public.fn_calcular_revision_estado_evento(uuid);
-- drop function if exists public.fn_calcular_estado_evento(uuid);
-- drop function if exists public.fn_calcular_ejecucion_estado_evento(uuid);
-- -- Revertir el vocabulario de eventos_mantencion requiere además
-- -- deshacer manualmente la edición de 2D-01 (restaurar el CHECK y los
-- -- 2 CHECK cruzados originales) y actualizar cualquier fila existente
-- -- que ya tenga los valores nuevos.

-- ============================================================
-- ETAPA 2D-09 — RLS Y VISIBILIDAD POR ROL
-- Archivo original: 2026-07-18_mantenciones_etapa2d_09_rls_visibilidad.sql
-- ============================================================

-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2D.09
-- RLS y visibilidad por rol — cierre de seguridad de la Fase 2D
--
-- PROPÓSITO:
-- Reemplazar el "deny-all" temporal (RLS habilitado sin políticas) de
-- eventos_mantencion (2D-01), evento_personal_requerido/evento_recursos
-- (2D-03/2D-04) y evento_personal_origen/evento_recursos_origen (2D-05)
-- por políticas reales, y EXTENDER (no reemplazar) las políticas ya
-- existentes de mantenciones/mantencion_actividades/mantencion_protocolos
-- (2B/2C) para sumar la visibilidad de técnico y de supervisor-por-evento.
--
-- ── MATRIZ DE PERMISOS ──
--   Administrador : acceso total (ya cubierto por es_admin() en todas
--                   las políticas existentes; no requiere cambios).
--   Supervisor    : gestiona los eventos donde es supervisor_id, y por
--                   extensión TODAS las tablas hijas de esos eventos —
--                   verificado contra el supervisor ACTUAL del evento
--                   (fn_es_supervisor_evento), no contra una copia
--                   posiblemente desactualizada en la fila hija.
--   Técnico       : solo lectura, y solo si tiene una fila VIGENTE
--                   (estado_asignacion <> 'liberado') en
--                   evento_personal_asignado para ese evento — nunca
--                   escritura administrativa.
--   Planificador  : lectura amplia de eventos y mantenciones (ya lo
--                   tenía mantenciones desde 2B); sin escritura nueva.
--   Bodega        : lectura de evento_recursos y datos del evento/equipo
--                   (equipos ya es de lectura pública para todo
--                   autenticado desde 2A.5) — nada del "motor"
--                   (evento_personal_*, evento_recursos_origen).
--   Gerencia      : lectura global (ya lo tenía mantenciones); sin
--                   escritura.
--
-- ── FUNCIONES HELPER (para no repetir subconsultas en cada política) ──
--   fn_es_supervisor_evento(evento_id)      → auth.uid() = supervisor
--                                              ACTUAL del evento.
--   fn_es_tecnico_vigente_evento(evento_id) → auth.uid() tiene una fila
--                                              vigente en
--                                              evento_personal_asignado
--                                              para ese evento.
--   fn_puede_ver_evento(evento_id)          → admin OR supervisor OR
--                                              planificador OR gerencia
--                                              OR técnico vigente. Cubre
--                                              7 de las 9 tablas; bodega
--                                              se agrega aparte solo en
--                                              eventos_mantencion y
--                                              evento_recursos (no en
--                                              el resto, según la matriz).
-- Las 3 son SECURITY DEFINER: se llaman desde políticas de las MISMAS
-- tablas que consultan (evento_personal_asignado, eventos_mantencion),
-- así que sin SECURITY DEFINER causarían recursión de RLS — mismo
-- motivo por el que tiene_rol()/es_admin() (perfiles_roles.sql) ya son
-- SECURITY DEFINER.
--
-- ── ESCRITURA ──
-- Ninguna tabla nueva de 2D (eventos_mantencion aparte, que sí tiene
-- UPDATE/DELETE con columnas acotadas, igual criterio que mantenciones)
-- recibe policies de INSERT/UPDATE/DELETE para "authenticated": toda
-- escritura de evento_personal_requerido/asignado/origen,
-- evento_recursos(_origen) ya pasa exclusivamente por las funciones
-- SECURITY DEFINER de 2D-06/2D-07/2D-07.1 — igual criterio que
-- mantencion_personal/actividades/protocolos/recursos desde 2C.
--
-- ── AUDITORÍA DE FUNCIONES SECURITY DEFINER ──
-- En vez de reconstruir a mano la lista de todas las funciones creadas
-- en 2D-01 a 2D-08 (con riesgo real de omitir alguna), esta migración
-- recorre pg_proc dinámicamente y corrige lo que encuentre:
--   - revoca EXECUTE de "public" en cualquier función SECURITY DEFINER
--     del esquema que todavía lo tenga (el default de PostgreSQL es
--     otorgar EXECUTE a PUBLIC al crear una función, así que cualquier
--     CREATE FUNCTION sin REVOKE explícito queda expuesto).
--   - fija search_path = public en cualquier función SECURITY DEFINER
--     que no lo tenga configurado.
-- El resto de la auditoría ("grant únicamente a authenticated cuando
-- corresponda", "validación interna de rol y pertenencia al evento") no
-- es mecánicamente corregible sin conocer la intención de cada función
-- (pública vs. privada) — se deja como consulta de verificación manual
-- al final de este archivo, más la revisión ya hecha función por función
-- a lo largo de 2D-01 a 2D-08.
--
-- DEPENDENCIAS: todas las migraciones de 2A a 2D.08.
-- ═══════════════════════════════════════════════════════════════

-- ── 0. Validaciones previas ──
do $$
begin
  if to_regclass('public.eventos_mantencion') is null
     or to_regclass('public.evento_personal_requerido') is null
     or to_regclass('public.evento_personal_asignado') is null
     or to_regclass('public.evento_personal_origen') is null
     or to_regclass('public.evento_recursos') is null
     or to_regclass('public.evento_recursos_origen') is null then
    raise exception 'Faltan tablas de 2D-01/03/04/05 — ejecutar esas migraciones antes que esta.';
  end if;

  if to_regprocedure('public.fn_recalcular_estados_evento(uuid)') is null then
    raise exception 'Falta fn_recalcular_estados_evento() — ejecutar primero 2026-07-18_mantenciones_etapa2d_08_rollup_estados.sql';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN A — Funciones helper de visibilidad
-- ═══════════════════════════════════════════════════════════════

create or replace function fn_es_supervisor_evento(p_evento_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from eventos_mantencion em
    where em.id = p_evento_id and em.supervisor_id = auth.uid()
  );
$$;

revoke all on function fn_es_supervisor_evento(uuid) from public;
grant execute on function fn_es_supervisor_evento(uuid) to authenticated;

-- "liberada" (estado_asignacion) cubre el único estado terminal que
-- existe hoy en evento_personal_asignado. No existe un concepto de fila
-- "eliminada" en esta tabla (no tiene estado_fila, a diferencia de las
-- tablas Snapshot) — se documenta para que quede claro que no se omitió
-- por descuido.
create or replace function fn_es_tecnico_vigente_evento(p_evento_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from evento_personal_asignado epa
    where epa.evento_mantencion_id = p_evento_id
      and epa.usuario_id = auth.uid()
      and epa.estado_asignacion <> 'liberado'
  );
$$;

revoke all on function fn_es_tecnico_vigente_evento(uuid) from public;
grant execute on function fn_es_tecnico_vigente_evento(uuid) to authenticated;

-- Cubre admin/supervisor-del-evento/planificador/gerencia/técnico-vigente
-- — la combinación que se repite en 7 de las 9 tablas de esta etapa.
-- bodega NO está incluida aquí a propósito (solo ve eventos_mantencion y
-- evento_recursos, agregado aparte en esas 2 políticas).
create or replace function fn_puede_ver_evento(p_evento_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select es_admin()
    or fn_es_supervisor_evento(p_evento_id)
    or tiene_rol('planificador')
    or tiene_rol('gerencia')
    or fn_es_tecnico_vigente_evento(p_evento_id);
$$;

revoke all on function fn_puede_ver_evento(uuid) from public;
grant execute on function fn_puede_ver_evento(uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN B — eventos_mantencion
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "eventos_mantencion_select" on eventos_mantencion;
create policy "eventos_mantencion_select" on eventos_mantencion
  for select using (
    fn_puede_ver_evento(id) or tiene_rol('bodega')
  );

-- Sin policy de INSERT a propósito: toda creación pasa por
-- fn_crear_evento_mantencion (SECURITY DEFINER) — mismo criterio que
-- mantenciones desde 2B.
drop policy if exists "eventos_mantencion_update" on eventos_mantencion;
create policy "eventos_mantencion_update" on eventos_mantencion
  for update using (
    (fn_es_supervisor_evento(id) and estado not in ('finalizado','cancelado'))
    or es_admin()
  );

drop policy if exists "eventos_mantencion_delete" on eventos_mantencion;
create policy "eventos_mantencion_delete" on eventos_mantencion
  for delete using (
    (es_admin() and estado in ('borrador','cancelado'))
    or (fn_es_supervisor_evento(id) and estado in ('borrador','cancelado'))
  );

-- Igual criterio que mantenciones (2B): columnas de identidad/rollup
-- INMUTABLES vía UPDATE directo (fuera del GRANT). estado/ejecucion_estado/
-- revision_estado/personal_estado/recursos_estado son EXCLUSIVAMENTE
-- escritos por las funciones SECURITY DEFINER de 2D-06/07/08 — un
-- supervisor no puede "aprobarse a sí mismo" el evento saltándose esas
-- funciones.
revoke all on eventos_mantencion from authenticated;
grant select on eventos_mantencion to authenticated;
grant update (
  nombre, descripcion, codigo, criticidad,
  fecha_plan_inicio, fecha_plan_termino, fecha_real_inicio, fecha_real_termino,
  planificacion_estado, planificador_id, observaciones
) on eventos_mantencion to authenticated;
grant delete on eventos_mantencion to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN C — mantenciones (EXTIENDE, no reemplaza, 2B)
-- ═══════════════════════════════════════════════════════════════

-- select: se agregan 2 cláusulas nuevas — supervisor-por-evento (usa el
-- supervisor ACTUAL del evento, no la copia en mantenciones.supervisor_id,
-- que puede quedar desactualizada si el evento cambia de supervisor) y
-- técnico (vigente en el evento, si es mantención de evento; asignado
-- directo en mantencion_personal, si es mantención suelta — así queda
-- resuelto el "técnico queda para 2D" que 2C había dejado pendiente).
drop policy if exists "mantenciones_select" on mantenciones;
create policy "mantenciones_select" on mantenciones
  for select using (
    es_admin()
    or auth.uid() = supervisor_id
    or auth.uid() = planificador_id
    or tiene_rol('bodega')
    or tiene_rol('gerencia')
    or (evento_mantencion_id is not null and fn_puede_ver_evento(evento_mantencion_id))
    or (evento_mantencion_id is null and exists (
          select 1 from mantencion_personal mp
          where mp.mantencion_id = mantenciones.id
            and mp.usuario_id = auth.uid()
            and mp.estado_fila <> 'eliminado'
        ))
  );

-- update/delete: sin cambios de fondo — se agrega la variante
-- "supervisor actual del evento" junto a la ya existente
-- "supervisor_id propio", por si llegaran a divergir.
drop policy if exists "mantenciones_update" on mantenciones;
create policy "mantenciones_update" on mantenciones
  for update using (
    (auth.uid() = supervisor_id and estado <> 'cerrada')
    or (evento_mantencion_id is not null and fn_es_supervisor_evento(evento_mantencion_id) and estado <> 'cerrada')
    or es_admin()
  );

drop policy if exists "mantenciones_delete" on mantenciones;
create policy "mantenciones_delete" on mantenciones
  for delete using (
    (es_admin() and estado in ('borrador','cancelada'))
    or (auth.uid() = supervisor_id and estado in ('borrador','cancelada'))
    or (evento_mantencion_id is not null and fn_es_supervisor_evento(evento_mantencion_id) and estado in ('borrador','cancelada'))
  );

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN D — mantencion_actividades / mantencion_protocolos
-- (EXTIENDEN, no reemplazan, 2C — mismo criterio que mantenciones_select)
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "mantencion_actividades_select" on mantencion_actividades;
create policy "mantencion_actividades_select" on mantencion_actividades
  for select using (
    exists (
      select 1 from mantenciones m
      where m.id = mantencion_actividades.mantencion_id
        and (
          es_admin() or auth.uid() = m.supervisor_id or auth.uid() = m.planificador_id
          or tiene_rol('bodega') or tiene_rol('gerencia')
          or (m.evento_mantencion_id is not null and fn_puede_ver_evento(m.evento_mantencion_id))
          or (m.evento_mantencion_id is null and exists (
                select 1 from mantencion_personal mp
                where mp.mantencion_id = m.id and mp.usuario_id = auth.uid() and mp.estado_fila <> 'eliminado'
              ))
        )
    )
  );

drop policy if exists "mantencion_protocolos_select" on mantencion_protocolos;
create policy "mantencion_protocolos_select" on mantencion_protocolos
  for select using (
    exists (
      select 1 from mantenciones m
      where m.id = mantencion_protocolos.mantencion_id
        and (
          es_admin() or auth.uid() = m.supervisor_id or auth.uid() = m.planificador_id
          or tiene_rol('bodega') or tiene_rol('gerencia')
          or (m.evento_mantencion_id is not null and fn_puede_ver_evento(m.evento_mantencion_id))
          or (m.evento_mantencion_id is null and exists (
                select 1 from mantencion_personal mp
                where mp.mantencion_id = m.id and mp.usuario_id = auth.uid() and mp.estado_fila <> 'eliminado'
              ))
        )
    )
  );

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN E — evento_personal_requerido / evento_personal_asignado /
-- evento_personal_origen (RLS estaba habilitado sin políticas desde
-- 2D-03/2D-05 — se agregan aquí las políticas reales)
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "evento_personal_requerido_select" on evento_personal_requerido;
create policy "evento_personal_requerido_select" on evento_personal_requerido
  for select using (fn_puede_ver_evento(evento_mantencion_id));

drop policy if exists "evento_personal_asignado_select" on evento_personal_asignado;
create policy "evento_personal_asignado_select" on evento_personal_asignado
  for select using (fn_puede_ver_evento(evento_mantencion_id));

drop policy if exists "evento_personal_origen_select" on evento_personal_origen;
create policy "evento_personal_origen_select" on evento_personal_origen
  for select using (
    exists (
      select 1 from evento_personal_requerido epr
      where epr.id = evento_personal_origen.evento_personal_requerido_id
        and fn_puede_ver_evento(epr.evento_mantencion_id)
    )
  );

-- Sin policy de INSERT/UPDATE/DELETE en las 3: toda escritura pasa por
-- las funciones SECURITY DEFINER de 2D-06/2D-07/2D-07.1. Nunca se otorga
-- GRANT de escritura a "authenticated" sobre estas tablas.
revoke all on evento_personal_requerido, evento_personal_asignado, evento_personal_origen from authenticated;
grant select on evento_personal_requerido, evento_personal_asignado, evento_personal_origen to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN F — evento_recursos / evento_recursos_origen
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "evento_recursos_select" on evento_recursos;
create policy "evento_recursos_select" on evento_recursos
  for select using (fn_puede_ver_evento(evento_mantencion_id) or tiene_rol('bodega'));

drop policy if exists "evento_recursos_origen_select" on evento_recursos_origen;
create policy "evento_recursos_origen_select" on evento_recursos_origen
  for select using (
    exists (
      select 1 from evento_recursos er
      where er.id = evento_recursos_origen.evento_recursos_id
        and (fn_puede_ver_evento(er.evento_mantencion_id) or tiene_rol('bodega'))
    )
  );
-- Nota: evento_recursos_origen SÍ hereda la visibilidad de bodega desde
-- evento_recursos (ver la línea con tiene_rol('bodega') arriba) — bodega
-- puede ver de dónde salió cada cantidad de un recurso que ya puede ver
-- de todas formas. Esto es distinto de evento_personal_origen, donde
-- bodega NO tiene acceso a personal en ningún nivel (matriz de permisos).

revoke all on evento_recursos, evento_recursos_origen from authenticated;
grant select on evento_recursos, evento_recursos_origen to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- SECCIÓN G — Auditoría automática de funciones SECURITY DEFINER
-- ═══════════════════════════════════════════════════════════════

do $$
declare
  v_rec record;
  v_total_revocados int := 0;
  v_total_search_path int := 0;
begin
  -- (a) Ninguna función SECURITY DEFINER del esquema debe conservar
  -- EXECUTE para "public" (el default de PostgreSQL al crear una función
  -- es otorgárselo a PUBLIC; cualquier CREATE FUNCTION sin REVOKE
  -- explícito queda expuesto sin que se note a simple vista).
  for v_rec in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prosecdef = true
      and has_function_privilege('public', p.oid, 'EXECUTE')
  loop
    execute format('revoke execute on function public.%I(%s) from public', v_rec.proname, v_rec.args);
    v_total_revocados := v_total_revocados + 1;
    raise notice 'Revocado EXECUTE de "public" sobre %(%) (SECURITY DEFINER).', v_rec.proname, v_rec.args;
  end loop;

  -- (b) Toda función SECURITY DEFINER debe fijar search_path
  -- explícitamente (evita que una función con privilegios elevados
  -- resuelva nombres de objetos según el search_path de quien la llama).
  for v_rec in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prosecdef = true
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, array[]::text[])) cfg
        where cfg like 'search_path=%'
      )
  loop
    execute format('alter function public.%I(%s) set search_path = public', v_rec.proname, v_rec.args);
    v_total_search_path := v_total_search_path + 1;
    raise notice 'search_path fijado a "public" en %(%) (no lo tenía configurado).', v_rec.proname, v_rec.args;
  end loop;

  raise notice 'Auditoría SECURITY DEFINER completa: % función(es) con EXECUTE de public revocado, % función(es) con search_path corregido.',
    v_total_revocados, v_total_search_path;
end $$;

-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN MANUAL — ejecutar por separado después de la migración
-- ═══════════════════════════════════════════════════════════════
-- 1) RLS activo y con políticas en las 9 tablas de esta etapa:
-- select relname, relrowsecurity from pg_class
--   where relname in ('eventos_mantencion','mantenciones','mantencion_actividades',
--     'mantencion_protocolos','evento_personal_requerido','evento_personal_asignado',
--     'evento_personal_origen','evento_recursos','evento_recursos_origen');
-- select tablename, policyname, cmd from pg_policies
--   where tablename in ('eventos_mantencion','mantenciones','mantencion_actividades',
--     'mantencion_protocolos','evento_personal_requerido','evento_personal_asignado',
--     'evento_personal_origen','evento_recursos','evento_recursos_origen')
--   order by tablename, policyname;
--
-- 2) Todas las funciones SECURITY DEFINER del esquema, con su estado de
--    privilegios (para revisar "grant únicamente a authenticated cuando
--    corresponda" — las que deben ser privadas deben mostrar "false" en
--    ambas columnas; las públicas, "false" en public y "true" en
--    authenticated):
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args,
--        has_function_privilege('public', p.oid, 'EXECUTE') as public_puede_ejecutar,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace and p.prosecdef = true
--   order by p.proname;
-- -- NINGUNA fila debe mostrar "true" en public_puede_ejecutar.
--
-- 3) Todas las funciones SECURITY DEFINER tienen search_path fijado:
-- select p.proname
--   from pg_proc p
--   where p.pronamespace = 'public'::regnamespace and p.prosecdef = true
--     and not exists (select 1 from unnest(coalesce(p.proconfig, array[]::text[])) cfg where cfg like 'search_path=%');
-- -- Debe devolver 0 filas.
--
-- 4) Pruebas RLS con roles simulados (dentro de una transacción que
--    termina en ROLLBACK): ver
--    supabase/tests/2026-07-18_test_rls_visibilidad_etapa2d09.sql

-- ═══════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutar manualmente y por separado si hace falta revertir
-- ═══════════════════════════════════════════════════════════════
-- drop policy if exists "evento_recursos_origen_select" on public.evento_recursos_origen;
-- drop policy if exists "evento_recursos_select" on public.evento_recursos;
-- drop policy if exists "evento_personal_origen_select" on public.evento_personal_origen;
-- drop policy if exists "evento_personal_asignado_select" on public.evento_personal_asignado;
-- drop policy if exists "evento_personal_requerido_select" on public.evento_personal_requerido;
--
-- -- mantencion_actividades/mantencion_protocolos/mantenciones: volver a
-- -- ejecutar los CREATE POLICY originales de 2026-07-17_mantenciones_etapa2c.sql
-- -- y 2026-07-17_mantenciones_etapa2b.sql para restaurar la versión sin
-- -- técnico/supervisor-por-evento.
--
-- drop policy if exists "eventos_mantencion_delete" on public.eventos_mantencion;
-- drop policy if exists "eventos_mantencion_update" on public.eventos_mantencion;
-- drop policy if exists "eventos_mantencion_select" on public.eventos_mantencion;
--
-- drop function if exists public.fn_puede_ver_evento(uuid);
-- drop function if exists public.fn_es_tecnico_vigente_evento(uuid);
-- drop function if exists public.fn_es_supervisor_evento(uuid);
--
-- -- La auditoría de la SECCIÓN G no es reversible ni debería serlo
-- -- (revertirla significaría volver a exponer funciones SECURITY DEFINER
-- -- a "public", lo cual nunca es correcto).

COMMIT;
