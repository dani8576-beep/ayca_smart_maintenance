function promedio(input) {
  let fila = input.parentElement.parentElement;
  let ali = parseFloat(fila.children[1].children[0].value) || 0;
  let des = parseFloat(fila.children[2].children[0].value) || 0;
  fila.children[3].innerText = ((ali + des) / 2).toFixed(2);
}

function cambiarPosicion(pos, boton) {
  guardarDatosPosicion();
  localStorage.setItem("datosPosicionesAYCA", JSON.stringify(datosPosiciones));

  posicionActual = pos;
  document.getElementById("posicionActual").innerText = pos;
  document.querySelectorAll(".pos").forEach(btn => btn.classList.remove("activa-pos"));
  boton.classList.add("activa-pos");

  if (datosPosiciones[pos] === null) {
    limpiarTabla("tablaEntrehierro");
    limpiarTabla("tablaCentroMagnetico");
    limpiarEstado("estadoSensor");
    limpiarEstado("estadoCableado");
    document.getElementById("observacionesSensor").value = "";
  } else {
    cargarTabla("tablaEntrehierro", datosPosiciones[pos].entrehierro);
    cargarTabla("tablaCentroMagnetico", datosPosiciones[pos].centroMagnetico);
    cargarEstado("estadoSensor", datosPosiciones[pos].estadoSensor);
    cargarEstado("estadoCableado", datosPosiciones[pos].estadoCableado);
    document.getElementById("observacionesSensor").value = datosPosiciones[pos].observacionesSensor || "";
  }
}

function guardarDatosPosicion() {
  datosPosiciones[posicionActual] = {
    estadoSensor: obtenerEstado("estadoSensor"),
    estadoCableado: obtenerEstado("estadoCableado"),
    observacionesSensor: document.getElementById("observacionesSensor").value,
    entrehierro: leerTabla("tablaEntrehierro"),
    centroMagnetico: leerTabla("tablaCentroMagnetico")
  };
}

function obtenerEstado(idGrupo) {
  const seleccionado = document.getElementById(idGrupo).querySelector(".seleccionado");
  if (seleccionado) {
    if (seleccionado.innerText.includes("OK")) return "OK";
    if (seleccionado.innerText.includes("FALLA")) return "FALLA";
    if (seleccionado.innerText.includes("N/A")) return "N/A";
  }
  return "";
}

function cargarEstado(idGrupo, valor) {
  document.getElementById(idGrupo).querySelectorAll(".btn-estado").forEach(btn => {
    btn.classList.remove("seleccionado");
    if (valor !== "" && btn.innerText.includes(valor)) btn.classList.add("seleccionado");
  });
}

function limpiarEstado(idGrupo) {
  document.getElementById(idGrupo).querySelectorAll(".btn-estado").forEach(btn => btn.classList.remove("seleccionado"));
}

function seleccionarEstado(boton) {
  const grupo = boton.parentElement;
  grupo.querySelectorAll(".btn-estado").forEach(btn => btn.classList.remove("seleccionado"));
  boton.classList.add("seleccionado");
}

function leerTabla(idTabla) {
  const filas = document.getElementById(idTabla).querySelectorAll("tr");
  const datos = [];
  filas.forEach((fila, index) => {
    if (index === 0) return;
    const inputs = fila.querySelectorAll("input");
    datos.push({
      polo: inputs[0].value,
      alimentacion: inputs[1].value,
      descarga: inputs[2].value,
      promedio: fila.querySelector(".resultado").innerText
    });
  });
  return datos;
}

function cargarTabla(idTabla, datos) {
  const filas = document.getElementById(idTabla).querySelectorAll("tr");
  filas.forEach((fila, index) => {
    if (index === 0) return;
    const inputs = fila.querySelectorAll("input");
    const dato = datos[index - 1] || {};
    inputs[0].value = dato.polo || "";
    inputs[1].value = dato.alimentacion || "";
    inputs[2].value = dato.descarga || "";
    fila.querySelector(".resultado").innerText = dato.promedio || "0.00";
  });
}

function limpiarTabla(idTabla) {
  const filas = document.getElementById(idTabla).querySelectorAll("tr");
  filas.forEach((fila, index) => {
    if (index === 0) return;
    fila.querySelectorAll("input").forEach(input => input.value = "");
    fila.querySelector(".resultado").innerText = "0.00";
  });
}
