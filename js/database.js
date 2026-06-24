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
    console.error("Error leyendo Supabase:", error);
    alert("No se pudieron cargar los protocolos de la nube.");
    return [];
  }

  console.log("Protocolos leídos desde la nube:", data);
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
  const cliente = document.getElementById("clienteDiel")?.value || "";
  const equipo  = document.getElementById("equipoDiel")?.value  || "";

  const fechaRef = est1.pre?.fecha || est1.post?.fecha || new Date().toISOString().slice(0, 10);

  const registro = {
    numero:    numProt,
    fecha:     fechaRef,
    cliente:   cliente,
    faena:     equipo,
    area:      "Dieléctrico",
    tecnico:   "",
    posiciones: JSON.stringify({ est1, est2, rotor })
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
  if (clienteEl && data.cliente) clienteEl.value = data.cliente;
  if (equipoEl  && data.faena)   equipoEl.value  = data.faena;

  const tienePre  = !!(est1Data.pre?.mediciones?.some(m => m.r));
  const tienePost = !!(est1Data.post?.mediciones?.some(m => m.r));
  const resumen   = (tienePre  ? "✅ Estator 1 PRE" : "⬜ Estator 1 PRE vacío") + "\n" +
                    (tienePost ? "✅ Estator 1 POST" : "⬜ Estator 1 POST pendiente");

  alert("✅ Protocolo cargado correctamente.\n\n" + resumen);

  if (typeof mostrar   === "function") mostrar("estator1");
  if (typeof cargarEst1 === "function") cargarEst1(typeof modoEst1 !== "undefined" ? modoEst1 : "pre");
}