// ===============================
// Conexión con Supabase
// ===============================

const SUPABASE_URL = "https://agharkotweuqryygepwf.supabase.co";

const SUPABASE_KEY = "sb_publishable_1DjM9HWZbXM5q4lQcxTceA_EQ6U5Z-Q";

const supabaseAYCA = supabase.createClient(
    SUPABASE_URL,
    SUPABASE_KEY
);
console.log("Supabase conectado correctamente");
console.log(supabaseAYCA);
async function guardarProtocoloNube(protocoloCompleto) {
  const { error } = await supabaseAYCA
    .from("protocolos_ayca")
    .upsert([protocoloCompleto], {
      onConflict: "numero"
    });

  if (error) {
    console.error("Error guardando en base de datos:", error);
    return false;
  }

  console.log("Protocolo guardado correctamente");
  return true;
}
async function obtenerProtocolosNube() {
  const { data, error } = await supabaseAYCA
    .from("protocolos_ayca")
    .select("*")
    .order("creado_en", { ascending: false });

  if (error) {
    console.warn("Sin acceso a protocolos en la nube:", error.message);
    throw new Error(error.message); // historial.js captura esto y muestra banner offline
  }

  return data || [];
}

// ── Guardar protocolo dieléctrico en la nube ──
async function guardarDielectricoNube() {
  if (typeof guardarEst1  === "function") guardarEst1();
  if (typeof guardarEst2  === "function") guardarEst2();
  if (typeof guardarRotor === "function") guardarRotor();

  const numProt = document.getElementById("numProtocoloDiel")?.value?.trim();
  if (!numProt) {
    alert("Asigna un N° de Protocolo antes de guardar.\n(Usa el botón 🔢 Generar si aún no tienes uno.)");
    return false;
  }

  const est1  = (typeof datosDielEst1  !== "undefined") ? datosDielEst1  : { pre: null, post: null };
  const est2  = (typeof datosDielEst2  !== "undefined") ? datosDielEst2  : { pre: null, post: null };
  const rotor = (typeof datosDielRotor !== "undefined") ? datosDielRotor : { pre: null, post: null };
  const cliente = document.getElementById("clienteDiel")?.value  || "";
  const equipo  = document.getElementById("equipoDiel")?.value   || "";
  const faena   = document.getElementById("faenaDiel")?.value    || "";
  const area    = document.getElementById("areaDiel")?.value     || "Dieléctrico";
  const evento  = document.getElementById("eventoDiel")?.value   || "";
  const tecnico = document.getElementById("tecnicoDiel")?.value  || "";
  const fechaDiel = document.getElementById("fechaDiel")?.value  || "";
  const kvNominal = document.getElementById("kvNominalDiel")?.value || "";

  const fechaRef = fechaDiel || est1.pre?.fecha || est1.post?.fecha || new Date().toISOString().slice(0, 10);

  const registro = {
    numero:    numProt,
    fecha:     fechaRef,
    cliente:   cliente,
    faena:     faena || equipo,
    area:      area,
    tecnico:   tecnico,
    posiciones: JSON.stringify({ est1, est2, rotor, equipo, evento, faena, area, tecnico, fechaDiel, kvNominal })
  };

  const { error } = await supabaseAYCA
    .from("protocolos_ayca")
    .upsert([registro], { onConflict: "numero" });

  if (error) {
    console.error("Error guardando dieléctrico:", error);
    alert("Error al guardar el protocolo:\n" + error.message);
    return false;
  }

  alert("✅ Protocolo guardado correctamente.\nN°: " + numProt + "\n\nAnota este número para completar el POST más adelante.");
  return true;
}

// ── Cargar protocolo dieléctrico desde la nube ──
async function cargarDielectricoNube() {
  const numProt = document.getElementById("numProtocoloDiel")?.value?.trim();
  if (!numProt) {
    alert("Ingresa el N° de Protocolo a cargar en el campo N° Protocolo.");
    return;
  }

  const { data, error } = await supabaseAYCA
    .from("protocolos_ayca")
    .select("*")
    .eq("numero", numProt)
    .single();

  if (error || !data) {
    alert("No se encontró el protocolo: " + numProt + "\nVerifica el número e intenta de nuevo.");
    return;
  }

  let parsed;
  try {
    parsed = JSON.parse(data.posiciones);
    if (parsed === null || typeof parsed !== "object" ||
        (!("est1" in parsed) && !("pre" in parsed) && !("post" in parsed))) {
      alert("El protocolo \"" + numProt + "\" es de control dimensional, no de medición dieléctrica.\nVerifica el número e intenta de nuevo.");
      return;
    }
  } catch (e) {
    alert("Error al leer los datos del protocolo: " + e.message);
    console.error(e);
    return;
  }

  // Compatibilidad: formato antiguo (pre/post directo) vs nuevo (est1/est2/rotor)
  const nuevoFormato = "est1" in parsed;
  const est1Data  = nuevoFormato ? (parsed.est1  || { pre: null, post: null }) : parsed;
  const est2Data  = nuevoFormato ? (parsed.est2  || { pre: null, post: null }) : { pre: null, post: null };
  const rotorData = nuevoFormato ? (parsed.rotor || { pre: null, post: null }) : { pre: null, post: null };

  if (typeof datosDielEst1  !== "undefined") datosDielEst1  = est1Data;
  if (typeof datosDielEst2  !== "undefined") datosDielEst2  = est2Data;
  if (typeof datosDielRotor !== "undefined") datosDielRotor = rotorData;
  localStorage.setItem("datosDielEst1",  JSON.stringify(est1Data));
  localStorage.setItem("datosDielEst2",  JSON.stringify(est2Data));
  localStorage.setItem("datosDielRotor", JSON.stringify(rotorData));

  const clienteEl = document.getElementById("clienteDiel");
  const equipoEl  = document.getElementById("equipoDiel");
  const faenaEl   = document.getElementById("faenaDiel");
  const areaEl    = document.getElementById("areaDiel");
  const eventoEl  = document.getElementById("eventoDiel");
  const tecnicoEl = document.getElementById("tecnicoDiel");
  const fechaEl   = document.getElementById("fechaDiel");
  const kvEl      = document.getElementById("kvNominalDiel");
  if (clienteEl && data.cliente) clienteEl.value = data.cliente;
  // equipo was stored in faena column (legacy) or in posiciones.equipo (new)
  const pos = (() => { try { return JSON.parse(data.posiciones); } catch(e) { return {}; } })();
  if (equipoEl)  equipoEl.value  = pos.equipo   || data.faena || "";
  if (faenaEl)   faenaEl.value   = pos.faena    || data.faena || "";
  if (areaEl)    areaEl.value    = pos.area     || data.area  || "Molienda";
  if (eventoEl)  eventoEl.value  = pos.evento   || "";
  if (tecnicoEl) tecnicoEl.value = pos.tecnico  || data.tecnico || "";
  if (fechaEl)   fechaEl.value   = pos.fechaDiel || data.fecha || "";
  if (kvEl)      kvEl.value      = pos.kvNominal || "";

  const tienePre  = !!(est1Data.pre?.mediciones?.some(m => m.r));
  const tienePost = !!(est1Data.post?.mediciones?.some(m => m.r));
  const resumen   = (tienePre  ? "✅ Estator 1 PRE" : "⬜ Estator 1 PRE vacío") + "\n" +
                    (tienePost ? "✅ Estator 1 POST" : "⬜ Estator 1 POST pendiente");

  alert("✅ Protocolo cargado correctamente.\n\n" + resumen);

  if (typeof mostrar   === "function") mostrar("estator1");
  if (typeof cargarEst1 === "function") cargarEst1(typeof modoEst1 !== "undefined" ? modoEst1 : "pre");
}

// ── Cargar protocolo de Carbones desde la nube ──
async function cargarCarbonesNube() {
  const numProt = document.getElementById("carb_numProtocolo")?.value?.trim();
  if (!numProt) {
    alert("Ingresa el N° de protocolo en el campo superior antes de presionar Cargar.");
    return;
  }

  const { data, error } = await supabaseAYCA
    .from("protocolos_ayca")
    .select("*")
    .eq("numero", numProt)
    .single();

  if (error || !data) {
    alert("No se encontró el protocolo: " + numProt + "\nVerifica el número e intenta de nuevo.");
    return;
  }

  let parsed;
  try {
    parsed = JSON.parse(data.posiciones);
    if (!parsed || typeof parsed !== "object") throw new Error("Formato inválido");
  } catch (e) {
    alert("Error al leer los datos del protocolo: " + e.message);
    return;
  }

  // Guardar en localStorage para que retomarCarbones() pueda cargarlo
  localStorage.setItem(`carbones_${numProt}`, data.posiciones);

  alert("✅ Protocolo " + numProt + " cargado correctamente.");

  if (typeof retomarCarbones === "function") retomarCarbones(numProt);
}

// ── Cargar protocolo de Ventilador desde la nube ──
async function cargarVentiladorNube() {
  const numProt = document.getElementById("vent_numProtocolo")?.value?.trim();
  if (!numProt) {
    alert("Ingresa el N° de protocolo en el campo superior antes de presionar Cargar.");
    return;
  }

  const { data, error } = await supabaseAYCA
    .from("protocolos_ayca")
    .select("*")
    .eq("numero", numProt)
    .single();

  if (error || !data) {
    alert("No se encontró el protocolo: " + numProt + "\nVerifica el número e intenta de nuevo.");
    return;
  }

  let parsed;
  try {
    parsed = JSON.parse(data.posiciones);
    if (!parsed || typeof parsed !== "object") throw new Error("Formato inválido");
  } catch (e) {
    alert("Error al leer los datos del protocolo: " + e.message);
    return;
  }

  // Guardar en localStorage para que retomarVentilador() pueda cargarlo
  localStorage.setItem(`ventilador_${numProt}`, data.posiciones);

  alert("✅ Protocolo " + numProt + " cargado correctamente.");

  if (typeof retomarVentilador === "function") retomarVentilador(numProt);
}