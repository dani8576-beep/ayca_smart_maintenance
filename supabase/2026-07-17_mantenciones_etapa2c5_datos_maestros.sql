-- ═══════════════════════════════════════════════════════════════
-- AYCA Smart Maintenance — Fase 2, ETAPA 2C.5
-- Carga inicial de datos maestros (clientes, faenas, áreas,
-- tipos de mantención, tipos de protocolo)
-- Ejecutar DESPUÉS de mantenciones_etapa2a.sql,
-- mantenciones_etapa2a5.sql y
-- mantenciones_etapa2c4_codigo_tipos_mantencion.sql (agrega la
-- columna "codigo" que usa este archivo). Totalmente idempotente:
-- cada INSERT usa ON CONFLICT DO NOTHING sobre la restricción única
-- real de cada tabla — se puede correr tantas veces como se quiera.
--
-- NO crea ni altera tablas, funciones, policies ni índices.
-- NO elimina ni actualiza ningún dato existente — solo agrega lo
-- que todavía no exista.
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- ⚠ LEER ANTES DE EJECUTAR — origen de los datos y supuestos:
--
-- • Clientes y Faenas: nombres tomados TAL CUAL de los <select>
--   ya en uso hoy en index.html (clienteDiel / faenaDiel) — son
--   datos "reales" en el sentido de que ya se usan en los
--   protocolos actuales, no inventados para esta carga.
--
-- • Faena → Cliente: ✔ APROBADO (CODELCO: Andina, El Teniente, El
--   Salvador, Chuquicamata, Ministro Hales · SIERRA GORDA: Sierra
--   Gorda · MLCC: Caserones · ANGLO AMERICAN: Los Bronces).
--   CANDELARIA, KINROSS y LUMBRERA quedan deliberadamente sin
--   faena precargada — no se inventan relaciones.
--
-- • Áreas: tomadas de las opciones ya usadas en areaDiel (Molienda,
--   Chancado, Concentradora, Salas Eléctricas), replicadas igual
--   bajo cada una de las 8 faenas como punto de partida razonable
--   — no está confirmado que las 8 faenas tengan exactamente estas
--   4 áreas. Ajusta/elimina las que no correspondan.
--
-- • Tipos de mantención: ✔ APROBADO — 5 tipos reales (mensual,
--   semestral, anual, correctiva, inspección y diagnóstico). Los
--   4 protocolos (Control Dimensional, Mediciones Dieléctricas,
--   Carbones, Ventilador) NO son tipos de mantención: son
--   componentes que podrán combinarse dentro de una misma
--   plantilla (plantilla_protocolos, ETAPA 2A), independientes del
--   tipo de mantención elegido.
--
--   ✔ Resuelto: tipos_mantencion ahora tiene columna "codigo" real
--   (migración aparte: mantenciones_etapa2c4_codigo_tipos_mantencion.sql),
--   con el mismo principio que tipos_protocolo. Este archivo ya
--   inserta usando codigo, nombre, activo y ON CONFLICT (codigo).
--
-- • Tipos de protocolo: los mismos 4 ya sembrados por la ETAPA 2A;
--   se repiten aquí solo por idempotencia/robustez (no cambia nada
--   si ya existen).
--
-- • Equipos: NO se cargan en esta etapa — se agregarán cuando haya
--   nombre, TAG y ubicación reales de cada motor/activo.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Clientes ──
insert into public.clientes (codigo, nombre)
values
  ('CODELCO',       'CODELCO'),
  ('MLCC',           'MLCC'),
  ('SIERRA GORDA',   'SIERRA GORDA'),
  ('CANDELARIA',     'CANDELARIA'),
  ('ANGLO AMERICAN', 'ANGLO AMERICAN'),
  ('KINROSS',        'KINROSS'),
  ('LUMBRERA',       'LUMBRERA')
on conflict (codigo) do nothing;

-- ── 2. Faenas (relacionadas a su cliente_id real vía JOIN) ──
insert into public.faenas (cliente_id, codigo, nombre)
select c.id, v.faena_codigo, v.faena_nombre
from (values
  ('CODELCO',       'ANDINA',       'Andina'),
  ('CODELCO',       'TENIENTE',     'El Teniente'),
  ('CODELCO',       'SALVADOR',     'El Salvador'),
  ('CODELCO',       'CHUQUICAMATA', 'Chuquicamata'),
  ('CODELCO',       'MHALES',       'Ministro Hales'),
  ('SIERRA GORDA',  'SGORDA',       'Sierra Gorda'),
  ('MLCC',          'CASERONES',    'Caserones'),
  ('ANGLO AMERICAN','LOSBRONCES',   'Los Bronces')
) as v(cliente_codigo, faena_codigo, faena_nombre)
join public.clientes c on c.codigo = v.cliente_codigo
on conflict (cliente_id, codigo) do nothing;

-- ── 3. Áreas (relacionadas a su faena_id real vía JOIN, vía cliente+faena) ──
insert into public.areas (faena_id, codigo, nombre)
select f.id, v.area_codigo, v.area_nombre
from (values
  ('CODELCO','ANDINA',       'MOLIENDA','Molienda'), ('CODELCO','ANDINA',       'CHANCADO','Chancado'), ('CODELCO','ANDINA',       'CONCENTRADORA','Concentradora'), ('CODELCO','ANDINA',       'SALASELEC','Salas Eléctricas'),
  ('CODELCO','TENIENTE',     'MOLIENDA','Molienda'), ('CODELCO','TENIENTE',     'CHANCADO','Chancado'), ('CODELCO','TENIENTE',     'CONCENTRADORA','Concentradora'), ('CODELCO','TENIENTE',     'SALASELEC','Salas Eléctricas'),
  ('CODELCO','SALVADOR',     'MOLIENDA','Molienda'), ('CODELCO','SALVADOR',     'CHANCADO','Chancado'), ('CODELCO','SALVADOR',     'CONCENTRADORA','Concentradora'), ('CODELCO','SALVADOR',     'SALASELEC','Salas Eléctricas'),
  ('CODELCO','CHUQUICAMATA', 'MOLIENDA','Molienda'), ('CODELCO','CHUQUICAMATA', 'CHANCADO','Chancado'), ('CODELCO','CHUQUICAMATA', 'CONCENTRADORA','Concentradora'), ('CODELCO','CHUQUICAMATA', 'SALASELEC','Salas Eléctricas'),
  ('CODELCO','MHALES',       'MOLIENDA','Molienda'), ('CODELCO','MHALES',       'CHANCADO','Chancado'), ('CODELCO','MHALES',       'CONCENTRADORA','Concentradora'), ('CODELCO','MHALES',       'SALASELEC','Salas Eléctricas'),
  ('SIERRA GORDA','SGORDA',  'MOLIENDA','Molienda'), ('SIERRA GORDA','SGORDA',  'CHANCADO','Chancado'), ('SIERRA GORDA','SGORDA',  'CONCENTRADORA','Concentradora'), ('SIERRA GORDA','SGORDA',  'SALASELEC','Salas Eléctricas'),
  ('MLCC','CASERONES',       'MOLIENDA','Molienda'), ('MLCC','CASERONES',       'CHANCADO','Chancado'), ('MLCC','CASERONES',       'CONCENTRADORA','Concentradora'), ('MLCC','CASERONES',       'SALASELEC','Salas Eléctricas'),
  ('ANGLO AMERICAN','LOSBRONCES','MOLIENDA','Molienda'), ('ANGLO AMERICAN','LOSBRONCES','CHANCADO','Chancado'), ('ANGLO AMERICAN','LOSBRONCES','CONCENTRADORA','Concentradora'), ('ANGLO AMERICAN','LOSBRONCES','SALASELEC','Salas Eléctricas')
) as v(cliente_codigo, faena_codigo, area_codigo, area_nombre)
join public.clientes c on c.codigo = v.cliente_codigo
join public.faenas   f on f.cliente_id = c.id and f.codigo = v.faena_codigo
on conflict (faena_id, codigo) do nothing;

-- ── 4. Tipos de mantención (reemplaza los protocolos-como-tipo anteriores) ──
insert into public.tipos_mantencion (codigo, nombre, activo)
values
  ('MANTENCION_MENSUAL',     'Mantención mensual',       true),
  ('MANTENCION_SEMESTRAL',   'Mantención semestral',     true),
  ('MANTENCION_ANUAL',       'Mantención anual',         true),
  ('MANTENCION_CORRECTIVA',  'Mantención correctiva',    true),
  ('INSPECCION_DIAGNOSTICO', 'Inspección y diagnóstico', true)
on conflict (codigo) do nothing;

-- ── 5. Tipos de protocolo (idéntico al de la ETAPA 2A; idempotente) ──
insert into public.tipos_protocolo (codigo, nombre, descripcion, orden) values
  ('control_dimensional', 'Control Dimensional',     'Entrehierro y centro magnético',  1),
  ('dielectrico',         'Mediciones Dieléctricas', 'Estator 1, Estator 2 y Rotor',    2),
  ('carbones',            'Carbones',                'Inspección de carbones de motor', 3),
  ('ventilador',          'Ventilador',              'Pruebas PRE/POST de ventilador',  4)
on conflict (codigo) do nothing;
