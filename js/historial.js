// ── Actualizar lista combinada de todos los protocolos ──────────────────────
async function actualizarListaProtocolos() {
  const contenedor = document.getElementById("listaProtocolos");
  if (!contenedor) return;
  contenedor.innerHTML = '<p style="color:#6b7280">Cargando protocolos…</p>';

  // 1. Nube (Supabase)
  let nube = [];
  let sinConexion = false;
  try {
    if (typeof obtenerProtocolosNube === "function") {
      nube = await obtenerProtocolosNube();
    }
  } catch (e) {
    sinConexion = true;
  }

  // Detectar tipo de protocolo en Supabase por contenido de posiciones
  function tipoNube(p) {
    try {
      const pos = typeof p.posiciones === "string" ? p.posiciones : JSON.stringify(p.posiciones || "");
      return pos.includes('"est1"') ? "MD" : "CD";
    } catch (e) { return "CD"; }
  }

  // 2. Locales
  const listaCd   = JSON.parse(localStorage.getItem("cdAYCA_lista")         || "[]");
  const listaCarb = JSON.parse(localStorage.getItem("carbonesAYCA_lista")   || "[]");
  const listaVent = JSON.parse(localStorage.getItem("ventiladorAYCA_lista") || "[]");

  // 3. Normalizar a formato común
  const todos = [
    ...nube.map(p => ({
      tipo:    tipoNube(p),
      num:     p.numero,
      fecha:   p.fecha,
      cliente: p.cliente,
      faena:   p.faena,
      extra:   [p.area, p.tecnico].filter(Boolean).join(" · "),
      fuente:  "nube"
    })),
    ...listaCd.map(p => ({
      tipo:    "CD",
      num:     p.protocolo,
      fecha:   p.fecha,
      cliente: p.cliente,
      faena:   p.faena,
      extra:   p.equipo || "",
      fuente:  "local"
    })),
    ...listaCarb.map(p => ({
      tipo:    "CB",
      num:     p.numProtocolo,
      fecha:   p.fecha,
      cliente: p.cliente,
      faena:   p.faena,
      extra:   p.equipo || "",
      fuente:  "local"
    })),
    ...listaVent.map(p => ({
      tipo:    "VT",
      num:     p.numProtocolo,
      fecha:   p.fecha,
      cliente: p.cliente,
      faena:   p.faena,
      extra:   p.equipo || "",
      fuente:  "local"
    }))
  ].filter(p => p.num);

  // 4. Deduplicar (nube tiene prioridad al ir primero)
  const vistos = new Set();
  const unicos = todos.filter(p => {
    if (vistos.has(p.num)) return false;
    vistos.add(p.num);
    return true;
  });
  unicos.sort((a, b) => (b.fecha || "").localeCompare(a.fecha || ""));

  // 5. Filtrar por buscador
  const filtro = (document.getElementById("buscarProtocolo")?.value || "").toLowerCase();
  const filtrados = filtro
    ? unicos.filter(p =>
        `${p.num} ${p.fecha} ${p.cliente} ${p.faena} ${p.extra}`.toLowerCase().includes(filtro))
    : unicos;

  // 6. Renderizar
  contenedor.innerHTML = "";

  if (sinConexion) {
    contenedor.innerHTML += `
      <div style="background:#fff7ed;border:1px solid #fed7aa;border-radius:8px;
                  padding:8px 12px;margin-bottom:10px;font-size:12px;color:#c2410c">
        Sin conexión a la nube — mostrando protocolos guardados en este dispositivo.
      </div>`;
  }

  if (!filtrados.length) {
    contenedor.innerHTML += '<p style="color:#6b7280;padding:8px 0">No hay protocolos guardados.</p>';
    return;
  }

  const COLOR = { MD: "#7c3aed", CD: "#0b5cc7", CB: "#b45309", VT: "#047857" };
  const LABEL = { MD: "Medición Dieléctrica", CD: "Control Dimensional", CB: "Carbones", VT: "Ventilador" };

  filtrados.forEach(p => {
    const clr = COLOR[p.tipo] || "#6b7280";
    const lbl = LABEL[p.tipo] || p.tipo;
    const numEnc = encodeURIComponent(p.num);

    contenedor.innerHTML += `
      <div class="card" style="border-left:4px solid ${clr};padding:12px 14px;margin:6px 0">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:6px;margin-bottom:6px">
          <b style="color:#0b3158;font-size:14px">${p.num}</b>
          <span style="flex-shrink:0;font-size:10px;background:${clr};color:white;
                       padding:2px 8px;border-radius:99px">${lbl}</span>
        </div>
        <div style="font-size:12px;color:#6b7280">
          ${p.fecha || "—"} &nbsp;·&nbsp; ${p.cliente || "—"} &nbsp;·&nbsp; ${p.faena || "—"}
          ${p.extra ? `<br><span style="font-size:11px">${p.extra}</span>` : ""}
        </div>
        <div style="margin-top:10px;display:flex;gap:6px;flex-wrap:wrap">
          <button onclick="abrirProtocoloUnificado('${p.tipo}','${numEnc}')"
                  style="flex:1;min-width:100px">Abrir</button>
          ${p.tipo === "MD"
            ? `<button onclick="reimprimirDielectricoPDF('${numEnc}')"
                       class="btn-rojo" style="flex:1;min-width:100px">PDF Entrega</button>`
            : ""}
        </div>
      </div>`;
  });
}

// ── Abrir protocolo según tipo ────────────────────────────────────────────────
async function abrirProtocoloUnificado(tipo, numEncoded) {
  const num = decodeURIComponent(numEncoded);

  if (tipo === "MD") {
    const el = document.getElementById("numProtocoloDiel");
    if (el) el.value = num;
    if (typeof cargarDielectricoNube === "function") await cargarDielectricoNube();
    return;
  }

  if (tipo === "CD") {
    const enLocal = !!localStorage.getItem(`cd_${num}`);
    if (enLocal) {
      const el = document.getElementById("protocolo");
      if (el) el.value = num;
      if (typeof cargarProtocoloCD === "function") cargarProtocoloCD();
    } else {
      await _abrirCDNube(num);
    }
    return;
  }

  if (tipo === "CB") {
    if (typeof retomarCarbones === "function") retomarCarbones(num);
    return;
  }

  if (tipo === "VT") {
    if (typeof retomarVentilador === "function") retomarVentilador(num);
    return;
  }
}

// ── Abrir protocolo CD desde Supabase (fallback cuando no está en local) ─────
async function _abrirCDNube(numero) {
  let historial = [];
  try {
    if (typeof obtenerProtocolosNube === "function") historial = await obtenerProtocolosNube();
  } catch (e) {}

  const protocolo = historial.find(p => p.numero === numero);
  if (!protocolo) {
    alert("Protocolo " + numero + " no encontrado.\nIntenta en línea o verifica el número.");
    return;
  }

  const s = (id, val) => { const el = document.getElementById(id); if (el) el.value = val || ""; };
  s("protocolo", protocolo.numero);
  s("fecha",     protocolo.fecha);
  s("cliente",   protocolo.cliente);
  s("faena",     protocolo.faena);
  s("area",      protocolo.area);

  // posiciones viene como string JSON desde Supabase
  const raw = protocolo.posiciones;
  try {
    datosPosiciones = typeof raw === "string" ? JSON.parse(raw)
                    : (raw && typeof raw === "object") ? raw
                    : { "0°": null, "90°": null, "180°": null, "270°": null };
  } catch (e) {
    datosPosiciones = { "0°": null, "90°": null, "180°": null, "270°": null };
  }
  posicionActual = "0°";

  const elPos = document.getElementById("posicionActual");
  if (elPos) elPos.innerText = "0°";
  document.querySelectorAll(".pos").forEach(btn => btn.classList.remove("activa-pos"));
  const btn0 = document.querySelector(".pos");
  if (btn0) btn0.classList.add("activa-pos");

  const d0 = datosPosiciones["0°"];
  if (d0) {
    if (typeof cargarTabla === "function") {
      cargarTabla("tablaEntrehierro",    d0.entrehierro    || []);
      cargarTabla("tablaCentroMagnetico",d0.centroMagnetico|| []);
    }
    if (typeof cargarEstado === "function") {
      cargarEstado("estadoSensor",   d0.estadoSensor   || "");
      cargarEstado("estadoCableado", d0.estadoCableado || "");
    }
    const obs = document.getElementById("observacionesSensor");
    if (obs) obs.value = d0.observacionesSensor || "";
  }

  localStorage.setItem("datosPosicionesAYCA", JSON.stringify(datosPosiciones));
  if (typeof mostrar === "function") mostrar("medicion");
}

// ── Reimprimir PDF dieléctrico desde historial ────────────────────────────────
async function reimprimirDielectricoPDF(numEncoded) {
  const num = decodeURIComponent(numEncoded);
  const el = document.getElementById("numProtocoloDiel");
  if (el) el.value = num;
  if (typeof cargarDielectricoNube === "function") await cargarDielectricoNube();
  setTimeout(() => {
    if (typeof generarEntregaDielectrico === "function") generarEntregaDielectrico();
  }, 600);
}

// ── Compatibilidad: mantener firma antigua por si hay llamadas hardcoded ──────
async function abrirProtocolo(numero) {
  await _abrirCDNube(numero);
}

async function reimprimirPDF(numero) {
  await _abrirCDNube(numero);
  setTimeout(() => { if (typeof generarPDF === "function") generarPDF(); }, 500);
}
