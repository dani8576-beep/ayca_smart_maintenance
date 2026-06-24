function clonar(objeto) {
  return JSON.parse(JSON.stringify(objeto));
}

function limpiarEstadoPDF(valor) {
  if (!valor) return "Sin registro";
  if (valor.includes("OK")) return "OK";
  if (valor.includes("FALLA")) return "FALLA";
  if (valor.includes("N/A")) return "N/A";
  return valor;
}
