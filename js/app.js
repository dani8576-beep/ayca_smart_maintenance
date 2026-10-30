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

// Objeto de datos generales del protocolo CD (espejo de carbonesData)
let cdData = {
  numProtocolo: '',
  cliente:  '',
  faena:    '',
  area:     '',
  equipo:   '',
  evento:   '',
  fecha:    '',
  tecnico:  ''
};

// Restaurar posiciones y generales al cargar la página
const _savedPos = localStorage.getItem("datosPosicionesAYCA");
if (_savedPos) datosPosiciones = JSON.parse(_savedPos);

const _savedGen = JSON.parse(localStorage.getItem("datosGeneralesAYCA") || "null");
if (_savedGen) {
  cdData.numProtocolo = _savedGen.protocolo || '';
  cdData.cliente  = _savedGen.cliente  || '';
  cdData.faena    = _savedGen.faena    || '';
  cdData.area     = _savedGen.area     || '';
  cdData.equipo   = _savedGen.equipo   || '';
  cdData.evento   = _savedGen.evento   || '';
  cdData.fecha    = _savedGen.fecha    || '';
  cdData.tecnico  = _savedGen.tecnico  || '';
}

// Recoger datos generales del DOM → cdData (igual que _recogerDatosCarb en carbones)
function _recogerGeneralesCD() {
  const g = id => document.getElementById(id)?.value || '';
  cdData.numProtocolo = g('protocolo');
  cdData.cliente  = g('cliente');
  cdData.faena    = g('faena');
  cdData.area     = g('area');
  cdData.equipo   = g('equipo');
  cdData.evento   = g('evento');
  cdData.fecha    = g('fecha');
  cdData.tecnico  = g('tecnico');
}

// Mostrar pantallas
function mostrar(id) {

  if (typeof tieneAcceso === "function" && !tieneAcceso(id)) {
    alert("No tienes permiso para acceder a esta pantalla.");
    return;
  }

  // Si estamos en pantalla de medición, guardar antes de cambiar
  if (
    document.getElementById("medicion") &&
    document.getElementById("medicion").classList.contains("activa")
  ) {
    try {
      if (typeof guardarDatosPosicion === "function") guardarDatosPosicion();
      localStorage.setItem("datosPosicionesAYCA", JSON.stringify(datosPosiciones));
      if (cdData.numProtocolo) {
        localStorage.setItem(`cd_${cdData.numProtocolo}`, JSON.stringify(
          Object.assign({}, cdData, { posiciones: datosPosiciones })
        ));
      }
    } catch (e) {
      console.warn("Auto-guardado al salir de medicion falló:", e);
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

  if (id === "medicion") {
    const pos = datosPosiciones[posicionActual];
    if (pos !== null && pos !== undefined) {
      if (typeof cargarTabla === "function") {
        cargarTabla("tablaEntrehierro",    pos.entrehierro    || []);
        cargarTabla("tablaCentroMagnetico", pos.centroMagnetico || []);
      }
      if (typeof cargarEstado === "function") {
        cargarEstado("estadoSensor",   pos.estadoSensor   || "");
        cargarEstado("estadoCableado", pos.estadoCableado || "");
      }
      const obsEl = document.getElementById("observacionesSensor");
      if (obsEl) obsEl.value = pos.observacionesSensor || "";
    }
  }

  if (id === "panel" && typeof renderPanelInicio === "function") {
    renderPanelInicio();
  }

  if (id === "eventosLista" && typeof eventosCargarLista === "function") {
    eventosCargarLista();
  }

  if (id === "usuariosLista" && typeof usuariosCargarLista === "function") {
    usuariosCargarLista();
  }

  if (id === "estator1" && typeof cargarEst1 === "function") {
    cargarEst1(typeof modoEst1 !== "undefined" ? modoEst1 : "pre");
  }
  if (id === "estator2" && typeof cargarEst2 === "function") {
    cargarEst2(typeof modoEst2 !== "undefined" ? modoEst2 : "pre");
  }
  if (id === "rotorDiel" && typeof cargarRotor === "function") {
    cargarRotor(typeof modoRotor !== "undefined" ? modoRotor : "pre");
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

  cdData = { numProtocolo:'', cliente:'', faena:'', area:'', equipo:'', evento:'', fecha:'', tecnico:'' };

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
  const ahora = new Date();
  const yy = String(ahora.getFullYear()).slice(2);
  const mm = String(ahora.getMonth() + 1).padStart(2, "0");
  const dd = String(ahora.getDate()).padStart(2, "0");
  const hh = String(ahora.getHours()).padStart(2, "0");
  const mi = String(ahora.getMinutes()).padStart(2, "0");

  const inputProtocolo = document.getElementById("protocolo");
  if (inputProtocolo) {
    inputProtocolo.value = "CD-" + yy + mm + dd + "-" + hh + mi;
  }
}

// Guardar avance — patrón idéntico a guardarAvanceCarbones
function guardarAvance() {
  // 1. Recoger mediciones de la posición actual
  if (typeof guardarDatosPosicion === "function") guardarDatosPosicion();

  // 2. Recoger datos generales del DOM → cdData
  _recogerGeneralesCD();

  const num = cdData.numProtocolo;
  if (!num) {
    alert("⚠️ Ingresa un N° de Protocolo antes de guardar.");
    return;
  }

  // 3. Construir objeto completo y guardar
  const dataToSave = Object.assign({}, cdData, { posiciones: datosPosiciones });

  let lista = JSON.parse(localStorage.getItem('cdAYCA_lista') || '[]');
  const resumen = { protocolo: num, cliente: cdData.cliente, faena: cdData.faena,
                    equipo: cdData.equipo, fecha: cdData.fecha };
  const idx = lista.findIndex(p => p.protocolo === num);
  if (idx >= 0) lista[idx] = resumen; else lista.unshift(resumen);
  localStorage.setItem('cdAYCA_lista', JSON.stringify(lista));
  localStorage.setItem(`cd_${num}`, JSON.stringify(dataToSave));

  // Guardar también en los slots genéricos para compatibilidad con DOMContentLoaded
  localStorage.setItem("datosPosicionesAYCA", JSON.stringify(datosPosiciones));
  localStorage.setItem("datosGeneralesAYCA", JSON.stringify({
    protocolo: cdData.numProtocolo, cliente: cdData.cliente, faena: cdData.faena,
    area: cdData.area, equipo: cdData.equipo, evento: cdData.evento,
    fecha: cdData.fecha, tecnico: cdData.tecnico
  }));

  alert("✅ Avance guardado correctamente.\nProtocolo: " + num);
}

function cargarProtocoloCD() {
  const num = document.getElementById("protocolo")?.value?.trim();
  if (!num) { alert("Ingresa el N° de protocolo a cargar."); return; }

  const raw = localStorage.getItem(`cd_${num}`);
  if (!raw) {
    alert("No se encontró el protocolo " + num + " en este dispositivo.\n\nAsegúrate de haber presionado 💾 GUARDAR antes de intentar cargar.");
    return;
  }

  const saved = JSON.parse(raw);

  // Compatibilidad con formato antiguo {generales: {...}, posiciones: {...}}
  // y formato nuevo {numProtocolo, cliente, ..., posiciones: {...}}
  const gen = saved.numProtocolo ? saved : (saved.generales || {});

  cdData.numProtocolo = gen.numProtocolo || gen.protocolo || num;
  cdData.cliente  = gen.cliente  || '';
  cdData.faena    = gen.faena    || '';
  cdData.area     = gen.area     || '';
  cdData.equipo   = gen.equipo   || '';
  cdData.evento   = gen.evento   || '';
  cdData.fecha    = gen.fecha    || '';
  cdData.tecnico  = gen.tecnico  || '';

  datosPosiciones = saved.posiciones || {"0°":null,"90°":null,"180°":null,"270°":null};
  localStorage.setItem("datosPosicionesAYCA", JSON.stringify(datosPosiciones));

  const s = (id, val) => { const el = document.getElementById(id); if (el && val !== undefined) el.value = val; };
  s("protocolo", cdData.numProtocolo);
  s("cliente",   cdData.cliente);
  s("faena",     cdData.faena);
  s("area",      cdData.area);
  s("equipo",    cdData.equipo);
  s("evento",    cdData.evento);
  s("fecha",     cdData.fecha);
  s("tecnico",   cdData.tecnico);

  alert("✅ Protocolo " + num + " cargado correctamente.");
  mostrar("herramientas");
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

  const datosGen = JSON.parse(localStorage.getItem("datosGeneralesAYCA") || "null");
  const s = (id, val) => { const el = document.getElementById(id); if (el && val) el.value = val; };

  if (datosGen) {
    s("protocolo", datosGen.protocolo);
    s("cliente",   datosGen.cliente);
    s("faena",     datosGen.faena);
    s("area",      datosGen.area);
    s("equipo",    datosGen.equipo);
    s("evento",    datosGen.evento);
    s("fecha",     datosGen.fecha);
    s("tecnico",   datosGen.tecnico);
  }

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

// ===============================
// AUTENTICACIÓN — Supabase Auth
// ===============================

async function iniciarSesion() {
  const email = document.getElementById("authEmail")?.value?.trim();
  const pass  = document.getElementById("authPass")?.value || "";
  const errEl = document.getElementById("authError");
  const btn   = document.getElementById("btnLogin");
  const showErr = (msg) => { if (errEl) { errEl.textContent = msg; errEl.style.display = "block"; } };

  if (errEl) errEl.style.display = "none";
  if (!email || !pass) { showErr("Ingresa correo y contraseña."); return; }
  if (typeof supabaseAYCA === "undefined") { showErr("Sin conexión a la base de datos. Revisa tu red."); return; }

  if (btn) { btn.disabled = true; btn.textContent = "INGRESANDO…"; }
  try {
    const { data, error } = await supabaseAYCA.auth.signInWithPassword({ email, password: pass });
    if (error) {
      if (error.message && error.message.toLowerCase().includes("confirm"))
        showErr("Tu correo aún no está confirmado. Avisa al administrador.");
      else if (error.message && error.message.toLowerCase().includes("invalid"))
        showErr("Correo o contraseña incorrectos.");
      else
        showErr("No se pudo iniciar sesión: " + error.message);
      return;
    }
    _entrarApp(data.user);
  } catch (e) {
    showErr("Error de conexión. Si estás sin señal, conéctate e intenta de nuevo.");
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = "INICIAR SESIÓN"; }
  }
}

async function cerrarSesion() {
  if (!confirm("¿Cerrar sesión?")) return;
  try { if (typeof supabaseAYCA !== "undefined") await supabaseAYCA.auth.signOut(); } catch (e) {}
  const pass = document.getElementById("authPass"); if (pass) pass.value = "";
  mostrar("login");
}

async function _entrarApp(user) {
  const pass = document.getElementById("authPass"); if (pass) pass.value = "";
  const errEl = document.getElementById("authError"); if (errEl) errEl.style.display = "none";
  const saludo = document.getElementById("saludoUsuario");
  if (saludo && user?.email) saludo.textContent = "Bienvenido, " + user.email.split("@")[0];

  if (typeof cargarPerfilActual === "function") await cargarPerfilActual(user?.id);
  if (typeof renderMenus === "function") renderMenus();

  mostrar("panel");
  if (typeof sincronizarTodo === "function") sincronizarTodo();
}

// Al abrir la app: si ya hay sesión guardada, entrar directo; si no, mostrar login.
async function _revisarSesion() {
  if (typeof supabaseAYCA === "undefined") { mostrar("login"); return; }
  try {
    const { data } = await supabaseAYCA.auth.getSession();
    if (data?.session?.user) _entrarApp(data.session.user);
    else mostrar("login");
  } catch (e) {
    mostrar("login");
  }
}

document.addEventListener("DOMContentLoaded", _revisarSesion);
