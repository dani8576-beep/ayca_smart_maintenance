async function actualizarListaProtocolos() {
  const contenedor = document.getElementById("listaProtocolos");
  if (!contenedor) return;

  contenedor.innerHTML = "<p>Cargando protocolos...</p>";

  let historial = [];

  if (typeof obtenerProtocolosNube === "function") {
    historial = await obtenerProtocolosNube();
  } else {
    historial = JSON.parse(localStorage.getItem("protocolosAYCA")) || [];
  }

  const buscador = document.getElementById("buscarProtocolo");
  const filtro = buscador ? buscador.value.toLowerCase() : "";

  const filtrados = historial.filter(p => {
    const fechaNormal = p.fecha || "";
    const fechaChile = fechaNormal.split("-").reverse().join("-");
    const texto = `${p.numero} ${fechaNormal} ${fechaChile} ${p.cliente} ${p.faena} ${p.area} ${p.tecnico}`.toLowerCase();
    return texto.includes(filtro);
  });

  contenedor.innerHTML = "";

  if (filtrados.length === 0) {
    contenedor.innerHTML = "<p>No hay protocolos guardados.</p>";
    return;
  }

  filtrados.forEach(p => {
    contenedor.innerHTML += `
      <div class="card">
        <b>${p.numero}</b><br>
        Fecha: ${p.fecha}<br>
        Cliente: ${p.cliente}<br>
        Faena: ${p.faena}<br>
        Área: ${p.area}<br>
        Técnico: ${p.tecnico}<br><br>

        <button onclick="abrirProtocolo('${p.numero}')">📂 Abrir</button>
        <button onclick="reimprimirPDF('${p.numero}')">📄 PDF</button>
      </div>
    `;
  });
}

async function abrirProtocolo(numero) {
  let historial = [];

  if (typeof obtenerProtocolosNube === "function") {
    historial = await obtenerProtocolosNube();
  } else {
    historial = JSON.parse(localStorage.getItem("protocolosAYCA")) || [];
  }

  const protocolo = historial.find(p => p.numero === numero);
  if (!protocolo) return alert("Protocolo no encontrado");

  document.getElementById("protocolo").value = protocolo.numero;
  document.getElementById("fecha").value = protocolo.fecha;
  document.getElementById("cliente").value = protocolo.cliente;
  document.getElementById("faena").value = protocolo.faena;
  document.getElementById("area").value = protocolo.area;

  datosPosiciones = clonar(protocolo.posiciones);
  posicionActual = "0°";

  document.getElementById("posicionActual").innerText = "0°";

  document.querySelectorAll(".pos").forEach(btn => {
    btn.classList.remove("activa-pos");
  });

  const boton0 = document.querySelector(".pos");
  if (boton0) boton0.classList.add("activa-pos");

  if (datosPosiciones["0°"]) {
    cargarTabla("tablaEntrehierro", datosPosiciones["0°"].entrehierro || []);
    cargarTabla("tablaCentroMagnetico", datosPosiciones["0°"].centroMagnetico || []);
    cargarEstado("estadoSensor", datosPosiciones["0°"].estadoSensor || "");
    cargarEstado("estadoCableado", datosPosiciones["0°"].estadoCableado || "");
    document.getElementById("observacionesSensor").value =
      datosPosiciones["0°"].observacionesSensor || "";
  }

  localStorage.setItem("datosPosicionesAYCA", JSON.stringify(datosPosiciones));
  mostrar("medicion");
}

async function reimprimirPDF(numero) {
  await abrirProtocolo(numero);
  setTimeout(() => generarPDF(), 500);
}