function clonar(objeto) {
  return JSON.parse(JSON.stringify(objeto));
}

function mostrarNombreFoto(input) {
  const p = input.closest("label").nextElementSibling;
  if (p && p.classList.contains("nombre-foto")) {
    p.innerText = input.files.length > 0 ? input.files[0].name : "Ninguna foto seleccionada";
  }
}
