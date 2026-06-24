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

// ── Medición Dieléctrica Estator 1 ──

let modoEst1 = "pre";
let datosDielEst1 = JSON.parse(localStorage.getItem("datosDielEst1") || '{"pre":null,"post":null}');

function cambiarModoEst1(modo) {
  guardarEst1();
  modoEst1 = modo;
  document.getElementById("btnPreEst1")?.classList.toggle("seleccionado", modo === "pre");
  document.getElementById("btnPostEst1")?.classList.toggle("seleccionado", modo === "post");
  cargarEst1(modo);
}

function actualizarKtEst1() {
  const T = parseFloat(document.getElementById("est1_temp")?.value);
  const ktEl = document.getElementById("est1_kt");
  if (!ktEl) return;
  if (isNaN(T)) {
    ktEl.textContent = "—";
  } else {
    ktEl.textContent = Math.pow(0.5, (40 - T) / 10).toFixed(4);
  }
  for (let i = 0; i <= 10; i++) calcularCorrEst1(i);
}

function calcularCorrEst1(idx) {
  const T = parseFloat(document.getElementById("est1_temp")?.value);
  const kt = isNaN(T) ? null : Math.pow(0.5, (40 - T) / 10);
  const r = parseFloat(document.getElementById("est1_r_" + idx)?.value);
  const rcEl = document.getElementById("est1_rc_" + idx);
  if (!rcEl) return;
  if (!isNaN(r) && r >= 0 && kt !== null) {
    rcEl.textContent = (r * kt).toFixed(4);
  } else {
    rcEl.textContent = "—";
  }
  calcularIPEst1();
}

function calcularIPEst1() {
  const r1  = parseFloat(document.getElementById("est1_r_1")?.value);
  const r10 = parseFloat(document.getElementById("est1_r_10")?.value);
  const ipEl     = document.getElementById("est1_ip");
  const estadoEl = document.getElementById("est1_ip_estado");
  if (!ipEl) return;
  if (!isNaN(r1) && r1 > 0 && !isNaN(r10) && r10 > 0) {
    const ip = r10 / r1;
    ipEl.textContent = ip.toFixed(2);
    if (ip >= 4)      { estadoEl.textContent = "✔ BUENO";     estadoEl.style.color = "#4ade80"; }
    else if (ip >= 2) { estadoEl.textContent = "⚠ ACEPTABLE"; estadoEl.style.color = "#fde047"; }
    else              { estadoEl.textContent = "✖ REVISAR";   estadoEl.style.color = "#f87171"; }
  } else {
    ipEl.textContent = "—";
    if (estadoEl) estadoEl.textContent = "";
  }
}

function guardarEst1() {
  const mediciones = [];
  for (let i = 0; i <= 10; i++) {
    mediciones.push({
      r:  document.getElementById("est1_r_" + i)?.value || "",
      rc: document.getElementById("est1_rc_" + i)?.textContent || ""
    });
  }
  datosDielEst1[modoEst1] = {
    fecha:     document.getElementById("est1_fecha")?.value     || "",
    vprueba:   document.getElementById("est1_vprueba")?.value   || "",
    temp:      document.getElementById("est1_temp")?.value      || "",
    kt:        document.getElementById("est1_kt")?.textContent  || "",
    if_nA:     document.getElementById("est1_if")?.value        || "",
    cap:       document.getElementById("est1_cap")?.value       || "",
    ip:        document.getElementById("est1_ip")?.textContent  || "",
    obs:       document.getElementById("est1_obs")?.value       || "",
    rohm_temp: document.getElementById("est1_rohm_temp")?.value || "",
    l12:       document.getElementById("est1_l12")?.value       || "",
    l13:       document.getElementById("est1_l13")?.value       || "",
    l21:       document.getElementById("est1_l21")?.value       || "",
    mediciones
  };
  localStorage.setItem("datosDielEst1", JSON.stringify(datosDielEst1));
}

function cargarEst1(modo) {
  const d = datosDielEst1[modo];
  const set = (id, val) => { const el = document.getElementById(id); if (el) el.value = val || ""; };

  if (!d) {
    set("est1_fecha", ""); set("est1_vprueba", "1000"); set("est1_temp", "");
    set("est1_if", ""); set("est1_cap", ""); set("est1_obs", "");
    set("est1_rohm_temp", ""); set("est1_l12", ""); set("est1_l13", ""); set("est1_l21", "");
    const ktEl = document.getElementById("est1_kt"); if (ktEl) ktEl.textContent = "—";
    const ipEl = document.getElementById("est1_ip"); if (ipEl) ipEl.textContent = "—";
    const stEl = document.getElementById("est1_ip_estado"); if (stEl) stEl.textContent = "";
    for (let i = 0; i <= 10; i++) {
      set("est1_r_" + i, "");
      const rc = document.getElementById("est1_rc_" + i); if (rc) rc.textContent = "—";
    }
    return;
  }

  set("est1_fecha",     d.fecha);
  set("est1_vprueba",   d.vprueba || "1000");
  set("est1_temp",      d.temp);
  set("est1_if",        d.if_nA);
  set("est1_cap",       d.cap);
  set("est1_obs",       d.obs);
  set("est1_rohm_temp", d.rohm_temp);
  set("est1_l12",       d.l12);
  set("est1_l13",       d.l13);
  set("est1_l21",       d.l21);

  const ktEl = document.getElementById("est1_kt");
  if (ktEl) ktEl.textContent = d.kt || "—";

  (d.mediciones || []).forEach((m, i) => {
    set("est1_r_" + i, m.r);
    const rc = document.getElementById("est1_rc_" + i);
    if (rc) rc.textContent = m.rc || "—";
  });

  calcularIPEst1();
}

function _dibujarGrafico(datos, canvasId) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return;
  canvas.style.display = "block";

  const ctx = canvas.getContext("2d");
  const W = canvas.width, H = canvas.height;
  const pad = { left: 46, right: 14, top: 22, bottom: 38 };
  const pw = W - pad.left - pad.right;
  const ph = H - pad.top - pad.bottom;

  ctx.fillStyle = "#fff";
  ctx.fillRect(0, 0, W, H);

  const tiempos = [0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  function getRCorr(modo) {
    const d = datos[modo];
    if (!d || !d.mediciones) return Array(11).fill(null);
    const kt = parseFloat(d.kt) || 1;
    return d.mediciones.map(m => {
      const v = parseFloat(m.r);
      return (!isNaN(v) && v > 0) ? v * kt : null;
    });
  }

  const preR  = getRCorr("pre");
  const postR = getRCorr("post");
  const todos = [...preR, ...postR].filter(v => v !== null);
  const yMax  = todos.length > 0 ? Math.max(Math.ceil(Math.max(...todos)), 2) : 10;

  const xPx = t => pad.left + (t / 10) * pw;
  const yPx = r => pad.top + ph * (1 - r / yMax);

  ctx.lineWidth = 0.7;
  for (let r = 0; r <= yMax; r++) {
    const y = yPx(r);
    ctx.strokeStyle = r === 0 ? "#9ca3af" : "#e5e7eb";
    ctx.beginPath(); ctx.moveTo(pad.left, y); ctx.lineTo(pad.left + pw, y); ctx.stroke();
    ctx.fillStyle = "#6b7280"; ctx.font = "9px Arial"; ctx.textAlign = "right";
    ctx.fillText(r, pad.left - 4, y + 3);
  }
  for (let t = 0; t <= 10; t += 2) {
    const x = xPx(t);
    ctx.strokeStyle = t === 0 ? "#9ca3af" : "#e5e7eb";
    ctx.beginPath(); ctx.moveTo(x, pad.top); ctx.lineTo(x, pad.top + ph); ctx.stroke();
    ctx.fillStyle = "#6b7280"; ctx.font = "9px Arial"; ctx.textAlign = "center";
    ctx.fillText(t, x, pad.top + ph + 13);
  }

  ctx.strokeStyle = "#374151"; ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(pad.left, pad.top);
  ctx.lineTo(pad.left, pad.top + ph);
  ctx.lineTo(pad.left + pw, pad.top + ph);
  ctx.stroke();

  ctx.fillStyle = "#374151"; ctx.font = "bold 9px Arial"; ctx.textAlign = "center";
  ctx.fillText("Tiempo [min]", pad.left + pw / 2, H - 6);
  ctx.save();
  ctx.translate(10, pad.top + ph / 2);
  ctx.rotate(-Math.PI / 2);
  ctx.fillText("R Aisl. [GΩ]", 0, 0);
  ctx.restore();

  function trazar(valores, color) {
    const puntos = tiempos.map((t, i) => valores[i] !== null ? { x: xPx(t), y: yPx(valores[i]) } : null);
    if (puntos.every(p => p === null)) return;
    ctx.strokeStyle = color; ctx.lineWidth = 2;
    ctx.beginPath();
    let primero = true;
    puntos.forEach(p => {
      if (!p) return;
      if (primero) { ctx.moveTo(p.x, p.y); primero = false; }
      else ctx.lineTo(p.x, p.y);
    });
    ctx.stroke();
    puntos.forEach(p => {
      if (!p) return;
      ctx.beginPath(); ctx.arc(p.x, p.y, 3, 0, Math.PI * 2);
      ctx.fillStyle = color; ctx.fill();
    });
  }

  trazar(preR,  "#2563eb");
  trazar(postR, "#dc2626");

  ctx.font = "9px Arial"; ctx.textAlign = "left";
  const ly = 13;
  ctx.strokeStyle = "#2563eb"; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(pad.left + 2, ly); ctx.lineTo(pad.left + 16, ly); ctx.stroke();
  ctx.beginPath(); ctx.arc(pad.left + 9, ly, 3, 0, Math.PI * 2); ctx.fillStyle = "#2563eb"; ctx.fill();
  ctx.fillStyle = "#111"; ctx.fillText("PRE", pad.left + 20, ly + 3);
  ctx.strokeStyle = "#dc2626"; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(pad.left + 56, ly); ctx.lineTo(pad.left + 70, ly); ctx.stroke();
  ctx.beginPath(); ctx.arc(pad.left + 63, ly, 3, 0, Math.PI * 2); ctx.fillStyle = "#dc2626"; ctx.fill();
  ctx.fillStyle = "#111"; ctx.fillText("POST", pad.left + 74, ly + 3);

  if (todos.length === 0) {
    ctx.fillStyle = "#9ca3af"; ctx.font = "11px Arial"; ctx.textAlign = "center";
    ctx.fillText("Sin datos aún", pad.left + pw / 2, pad.top + ph / 2);
  }
}

function dibujarGraficoIP()      { guardarEst1();  _dibujarGrafico(datosDielEst1,  "graficoIP"); }
function dibujarGraficoIP2()     { guardarEst2();  _dibujarGrafico(datosDielEst2,  "graficoIP2"); }
function dibujarGraficoIPRotor() { guardarRotor(); _dibujarGrafico(datosDielRotor, "graficoIPRotor"); }

// ── Estator 2 ──
let modoEst2 = "pre";
let datosDielEst2 = JSON.parse(localStorage.getItem("datosDielEst2") || '{"pre":null,"post":null}');

function cambiarModoEst2(modo) {
  guardarEst2(); modoEst2 = modo;
  const btnPre  = document.getElementById("btnPreEst2");
  const btnPost = document.getElementById("btnPostEst2");
  if (btnPre)  btnPre.classList.toggle("seleccionado", modo === "pre");
  if (btnPost) btnPost.classList.toggle("seleccionado", modo === "post");
  cargarEst2(modo);
}

function actualizarKtEst2() {
  const temp = parseFloat(document.getElementById("est2_temp")?.value);
  const ktEl = document.getElementById("est2_kt");
  if (isNaN(temp) || !ktEl) { if (ktEl) ktEl.textContent = "—"; return; }
  ktEl.textContent = Math.pow(0.5, (40 - temp) / 10).toFixed(4);
  for (let i = 0; i <= 10; i++) calcularCorrEst2(i);
}

function calcularCorrEst2(idx) {
  const r  = parseFloat(document.getElementById("est2_r_" + idx)?.value);
  const kt = parseFloat(document.getElementById("est2_kt")?.textContent);
  const rcEl = document.getElementById("est2_rc_" + idx);
  if (!rcEl) return;
  if (isNaN(r) || isNaN(kt) || kt === 0) { rcEl.textContent = "—"; calcularIPEst2(); return; }
  rcEl.textContent = (r * kt).toFixed(3);
  calcularIPEst2();
}

function calcularIPEst2() {
  const r1  = parseFloat(document.getElementById("est2_rc_1")?.textContent);
  const r10 = parseFloat(document.getElementById("est2_rc_10")?.textContent);
  const ipEl = document.getElementById("est2_ip");
  const stEl = document.getElementById("est2_ip_estado");
  if (!ipEl) return;
  if (isNaN(r1) || isNaN(r10) || r1 === 0) { ipEl.textContent = "—"; if (stEl) stEl.textContent = ""; return; }
  const ip = r10 / r1;
  ipEl.textContent = ip.toFixed(2);
  if (stEl) {
    if (ip >= 4)      { stEl.textContent = "✅ BUENO";     stEl.style.color = "#4ade80"; }
    else if (ip >= 2) { stEl.textContent = "⚠️ ACEPTABLE"; stEl.style.color = "#fbbf24"; }
    else               { stEl.textContent = "❌ REVISAR";   stEl.style.color = "#f87171"; }
  }
}

function guardarEst2() {
  const mediciones = [];
  for (let i = 0; i <= 10; i++) {
    mediciones.push({ r: document.getElementById("est2_r_" + i)?.value || "", rc: document.getElementById("est2_rc_" + i)?.textContent || "" });
  }
  datosDielEst2[modoEst2] = {
    fecha: document.getElementById("est2_fecha")?.value || "", vprueba: document.getElementById("est2_vprueba")?.value || "",
    temp:  document.getElementById("est2_temp")?.value  || "", kt:      document.getElementById("est2_kt")?.textContent || "",
    if_nA: document.getElementById("est2_if")?.value    || "", cap:     document.getElementById("est2_cap")?.value || "",
    ip:    document.getElementById("est2_ip")?.textContent || "", obs: document.getElementById("est2_obs")?.value || "",
    rohm_temp: document.getElementById("est2_rohm_temp")?.value || "",
    l12: document.getElementById("est2_l12")?.value || "", l13: document.getElementById("est2_l13")?.value || "",
    l21: document.getElementById("est2_l21")?.value || "", mediciones
  };
  localStorage.setItem("datosDielEst2", JSON.stringify(datosDielEst2));
}

function cargarEst2(modo) {
  const d = datosDielEst2[modo];
  const set = (id, val) => { const el = document.getElementById(id); if (el) el.value = val || ""; };
  if (!d) {
    ["est2_fecha","est2_if","est2_cap","est2_obs","est2_rohm_temp","est2_l12","est2_l13","est2_l21"].forEach(id => set(id, ""));
    set("est2_vprueba", "1000"); set("est2_temp", "");
    const ktEl = document.getElementById("est2_kt"); if (ktEl) ktEl.textContent = "—";
    const ipEl = document.getElementById("est2_ip"); if (ipEl) ipEl.textContent = "—";
    const stEl = document.getElementById("est2_ip_estado"); if (stEl) stEl.textContent = "";
    for (let i = 0; i <= 10; i++) { set("est2_r_" + i, ""); const rc = document.getElementById("est2_rc_" + i); if (rc) rc.textContent = "—"; }
    return;
  }
  set("est2_fecha", d.fecha); set("est2_vprueba", d.vprueba || "1000"); set("est2_temp", d.temp);
  set("est2_if", d.if_nA); set("est2_cap", d.cap); set("est2_obs", d.obs);
  set("est2_rohm_temp", d.rohm_temp); set("est2_l12", d.l12); set("est2_l13", d.l13); set("est2_l21", d.l21);
  const ktEl = document.getElementById("est2_kt"); if (ktEl) ktEl.textContent = d.kt || "—";
  const ipEl = document.getElementById("est2_ip"); if (ipEl) ipEl.textContent = d.ip || "—";
  (d.mediciones || []).forEach((m, i) => {
    set("est2_r_" + i, m.r);
    const rc = document.getElementById("est2_rc_" + i); if (rc) rc.textContent = m.rc || "—";
  });
  calcularIPEst2();
}

// ── Rotor ──
let modoRotor = "pre";
let datosDielRotor = JSON.parse(localStorage.getItem("datosDielRotor") || '{"pre":null,"post":null}');

function cambiarModoRotor(modo) {
  guardarRotor(); modoRotor = modo;
  const btnPre  = document.getElementById("btnPreRotor");
  const btnPost = document.getElementById("btnPostRotor");
  if (btnPre)  btnPre.classList.toggle("seleccionado", modo === "pre");
  if (btnPost) btnPost.classList.toggle("seleccionado", modo === "post");
  cargarRotor(modo);
}

function actualizarKtRotor() {
  const temp = parseFloat(document.getElementById("rotor_temp")?.value);
  const ktEl = document.getElementById("rotor_kt");
  if (isNaN(temp) || !ktEl) { if (ktEl) ktEl.textContent = "—"; return; }
  ktEl.textContent = Math.pow(0.5, (40 - temp) / 10).toFixed(4);
  for (let i = 0; i <= 10; i++) calcularCorrRotor(i);
}

function calcularCorrRotor(idx) {
  const r  = parseFloat(document.getElementById("rotor_r_" + idx)?.value);
  const kt = parseFloat(document.getElementById("rotor_kt")?.textContent);
  const rcEl = document.getElementById("rotor_rc_" + idx);
  if (!rcEl) return;
  if (isNaN(r) || isNaN(kt) || kt === 0) { rcEl.textContent = "—"; calcularIPRotor(); return; }
  rcEl.textContent = (r * kt).toFixed(3);
  calcularIPRotor();
}

function calcularIPRotor() {
  const r1  = parseFloat(document.getElementById("rotor_rc_1")?.textContent);
  const r10 = parseFloat(document.getElementById("rotor_rc_10")?.textContent);
  const ipEl = document.getElementById("rotor_ip");
  const stEl = document.getElementById("rotor_ip_estado");
  if (!ipEl) return;
  if (isNaN(r1) || isNaN(r10) || r1 === 0) { ipEl.textContent = "—"; if (stEl) stEl.textContent = ""; return; }
  const ip = r10 / r1;
  ipEl.textContent = ip.toFixed(2);
  if (stEl) {
    if (ip >= 4)      { stEl.textContent = "✅ BUENO";     stEl.style.color = "#4ade80"; }
    else if (ip >= 2) { stEl.textContent = "⚠️ ACEPTABLE"; stEl.style.color = "#fbbf24"; }
    else               { stEl.textContent = "❌ REVISAR";   stEl.style.color = "#f87171"; }
  }
}

function guardarRotor() {
  const mediciones = [];
  for (let i = 0; i <= 10; i++) {
    mediciones.push({ r: document.getElementById("rotor_r_" + i)?.value || "", rc: document.getElementById("rotor_rc_" + i)?.textContent || "" });
  }
  datosDielRotor[modoRotor] = {
    fecha: document.getElementById("rotor_fecha")?.value || "", vprueba: document.getElementById("rotor_vprueba")?.value || "",
    temp:  document.getElementById("rotor_temp")?.value  || "", kt:      document.getElementById("rotor_kt")?.textContent || "",
    if_nA: document.getElementById("rotor_if")?.value    || "", cap:     document.getElementById("rotor_cap")?.value || "",
    ip:    document.getElementById("rotor_ip")?.textContent || "", obs: document.getElementById("rotor_obs")?.value || "",
    rohm_temp: document.getElementById("rotor_rohm_temp")?.value || "",
    l12: document.getElementById("rotor_l12")?.value || "",
    mediciones
  };
  localStorage.setItem("datosDielRotor", JSON.stringify(datosDielRotor));
}

function cargarRotor(modo) {
  const d = datosDielRotor[modo];
  const set = (id, val) => { const el = document.getElementById(id); if (el) el.value = val || ""; };
  if (!d) {
    ["rotor_fecha","rotor_if","rotor_cap","rotor_obs","rotor_rohm_temp","rotor_l12"].forEach(id => set(id, ""));
    set("rotor_vprueba", "500"); set("rotor_temp", "");
    const ktEl = document.getElementById("rotor_kt"); if (ktEl) ktEl.textContent = "—";
    const ipEl = document.getElementById("rotor_ip"); if (ipEl) ipEl.textContent = "—";
    const stEl = document.getElementById("rotor_ip_estado"); if (stEl) stEl.textContent = "";
    for (let i = 0; i <= 10; i++) { set("rotor_r_" + i, ""); const rc = document.getElementById("rotor_rc_" + i); if (rc) rc.textContent = "—"; }
    return;
  }
  set("rotor_fecha", d.fecha); set("rotor_vprueba", d.vprueba || "500"); set("rotor_temp", d.temp);
  set("rotor_if", d.if_nA); set("rotor_cap", d.cap); set("rotor_obs", d.obs);
  set("rotor_rohm_temp", d.rohm_temp); set("rotor_l12", d.l12);
  const ktEl = document.getElementById("rotor_kt"); if (ktEl) ktEl.textContent = d.kt || "—";
  const ipEl = document.getElementById("rotor_ip"); if (ipEl) ipEl.textContent = d.ip || "—";
  (d.mediciones || []).forEach((m, i) => {
    set("rotor_r_" + i, m.r);
    const rc = document.getElementById("rotor_rc_" + i); if (rc) rc.textContent = m.rc || "—";
  });
  calcularIPRotor();
}

function generarNumProtocoloDiel() {
  const ahora = new Date();
  const yy = String(ahora.getFullYear()).slice(2);
  const mm = String(ahora.getMonth() + 1).padStart(2, "0");
  const dd = String(ahora.getDate()).padStart(2, "0");
  const hh = String(ahora.getHours()).padStart(2, "0");
  const mi = String(ahora.getMinutes()).padStart(2, "0");
  const num = "MD-" + yy + mm + dd + "-" + hh + mi;
  const el = document.getElementById("numProtocoloDiel");
  if (el) el.value = num;
}

function nuevoDielectrico() {
  datosDielEst1  = { pre: null, post: null };
  datosDielEst2  = { pre: null, post: null };
  datosDielRotor = { pre: null, post: null };
  localStorage.setItem("datosDielEst1",  JSON.stringify(datosDielEst1));
  localStorage.setItem("datosDielEst2",  JSON.stringify(datosDielEst2));
  localStorage.setItem("datosDielRotor", JSON.stringify(datosDielRotor));

  ["numProtocoloDiel", "equipoDiel"].forEach(id => { const el = document.getElementById(id); if (el) el.value = ""; });
  const clienteEl = document.getElementById("clienteDiel");
  if (clienteEl) clienteEl.selectedIndex = 0;

  modoEst1  = "pre";
  modoEst2  = "pre";
  modoRotor = "pre";

  mostrar("dielectrico");
}
