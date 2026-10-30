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
