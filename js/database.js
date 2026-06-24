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
    console.error("Error guardando en Supabase:", error);
    alert("PDF generado, pero no se pudo guardar en la nube.");
    return false;
  }

  console.log("Protocolo guardado en la nube");
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