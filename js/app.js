// ===============================
// AYCA SMART MAINTENANCE - APP.JS
// Funciones generales de navegación
// ===============================

let posicionActual = "0°";

let datosPosiciones = {
  "0°": null,
  "90°": null,
  "180°": null,
  "270°": null
};

// Cargar datos temporales guardados
const datosGuardados = localStorage.getItem("datosPosicionesAYCA");

if (datosGuardados) {
  datosPosiciones = JSON.parse(datosGuardados);
}

// Mostrar pantallas
function mostrar(id) {

  // Si estamos en pantalla de medición, guardar antes de cambiar
  if (
    document.getElementById("medicion") &&
    document.getElementById("medicion").classList.contains("activa")
  ) {
    if (typeof guardarDatosPosicion === "function") {
      guardarDatosPosicion();
      localStorage.setItem(
        "datosPosicionesAYCA",
        JSON.stringify(datosPosiciones)
      );
    }
  }

  document.querySelectorAll(".pantalla").forEach(pantalla => {
    pantalla.classList.remove("activa");
    pantalla.style.display = "none";
  });

  const pantallaMostrar = document.getElementById(id);

  if (pantallaMostrar) {
    pantallaMostrar.classList.add("activa");
    pantallaMostrar.style.display = "block";
  }

  if (id === "resumen" && typeof actualizarResumen === "function") {
    actualizarResumen();
  }

  if (id === "protocolos" && typeof actualizarListaProtocolos === "function") {
    actualizarListaProtocolos();
  }
}

// Crear nuevo protocolo
function nuevoProtocolo() {

  const confirmar = confirm("¿Desea iniciar un nuevo protocolo?");

  if (!confirmar) return;

  datosPosiciones = {
    "0°": null,
    "90°": null,
    "180°": null,
    "270°": null
  };

  posicionActual = "0°";

  localStorage.removeItem("datosPosicionesAYCA");

  generarProtocolo();

  document.getElementById("fecha").valueAsDate = new Date();

  if (typeof limpiarTabla === "function") {
    limpiarTabla("tablaEntrehierro");
    limpiarTabla("tablaCentroMagnetico");
  }

  if (typeof limpiarEstado === "function") {
    limpiarEstado("estadoSensor");
    limpiarEstado("estadoCableado");
  }

  const observaciones = document.getElementById("observacionesSensor");
  if (observaciones) {
    observaciones.value = "";
  }

  // Limpiar herramientas seleccionadas
  document.querySelectorAll("#herramientas input[type='checkbox']").forEach(check => {
    check.checked = false;
  });

  // Limpiar textos de herramientas
  document.querySelectorAll("#herramientas input").forEach(input => {
    if (input.type !== "checkbox") {
      input.value = "";
    }
  });

  // Limpiar textareas de herramientas
  document.querySelectorAll("#herramientas textarea").forEach(textarea => {
    textarea.value = "";
  });

  // Limpiar archivos de herramientas
  document.querySelectorAll("#herramientas input[type='file']").forEach(file => {
    file.value = "";
  });

  // Limpiar archivos de medición
  document.querySelectorAll("#medicion input[type='file']").forEach(file => {
    file.value = "";
  });

  // Limpiar nombres de fotos
  document.querySelectorAll(".nombre-foto").forEach(p => {
    p.innerText = "Ninguna foto seleccionada";
  });

  const posicionTexto = document.getElementById("posicionActual");
  if (posicionTexto) {
    posicionTexto.innerText = "0°";
  }

  document.querySelectorAll(".pos").forEach(btn => {
    btn.classList.remove("activa-pos");
  });

  const primerBoton = document.querySelector(".pos");
  if (primerBoton) {
    primerBoton.classList.add("activa-pos");
  }

  mostrar("datos");
}

// Generar número de protocolo automático
function generarProtocolo() {

  const anio = new Date().getFullYear();
  const ultimo = localStorage.getItem("ultimoAYCA") || 0;
  const nuevo = parseInt(ultimo) + 1;

  localStorage.setItem("ultimoAYCA", nuevo);

  const inputProtocolo = document.getElementById("protocolo");

  if (inputProtocolo) {
    inputProtocolo.value =
      "AYCA-" + anio + "-" + String(nuevo).padStart(4, "0");
  }
}

// Guardar avance general
function guardarAvance() {

  if (typeof guardarDatosPosicion === "function") {
    guardarDatosPosicion();
  }

  localStorage.setItem(
    "datosPosicionesAYCA",
    JSON.stringify(datosPosiciones)
  );

  const salirMotor = confirm("¿Estás saliendo del motor?");

  if (salirMotor) {
    alert("Debe tomar o adjuntar foto de las herramientas salientes.");
    mostrar("salida");
    return;
  }

  alert("Avance guardado correctamente.");
}
function confirmarSalidaMotor() {
  const fotoSalida = document.getElementById("fotoHerramientasSalida");

  if (!fotoSalida || fotoSalida.files.length === 0) {
    alert("Debe tomar o adjuntar la foto de herramientas salientes antes de confirmar.");
    return;
  }

  alert("Salida del motor confirmada correctamente.");
  mostrar("resumen");
}
// Actualizar resumen
function actualizarResumen() {

  document.getElementById("resProtocolo").innerText =
    document.getElementById("protocolo").value;

  document.getElementById("resCliente").innerText =
    document.getElementById("cliente").value;

  document.getElementById("resFaena").innerText =
    document.getElementById("faena").value;

  document.getElementById("resArea").innerText =
    document.getElementById("area").value;
}

// Inicializar aplicación
document.addEventListener("DOMContentLoaded", () => {

  if (!document.getElementById("protocolo").value) {
    generarProtocolo();
  }

  const fecha = document.getElementById("fecha");

  if (fecha && !fecha.value) {
    fecha.valueAsDate = new Date();
  }

  if (datosPosiciones[posicionActual] !== null) {
    if (typeof cargarTabla === "function") {
      cargarTabla(
        "tablaEntrehierro",
        datosPosiciones[posicionActual].entrehierro
      );

      cargarTabla(
        "tablaCentroMagnetico",
        datosPosiciones[posicionActual].centroMagnetico
      );
    }
  }
});
