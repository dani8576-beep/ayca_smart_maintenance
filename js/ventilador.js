// ===============================
// PROTOCOLO VENTILADOR - AYCA
// ===============================

let ventiladorData = {};

const _VKEYS_PRE_PRUEBAS = [
  'vent_pre_ohm12','vent_pre_ohm23','vent_pre_ohm13',
  'vent_pre_ais1','vent_pre_ais2','vent_pre_ais3','vent_pre_ip'
];

// Claves que usan el componente medicion-control (valor + unidad separados en el DOM)
const _MEDICION_KEYS = new Set([
  'vent_pre_ohm12','vent_pre_ohm23','vent_pre_ohm13',
  'vent_pre_ais1','vent_pre_ais2','vent_pre_ais3'
]);
const _VKEYS_PRE_INSP = [
  'vent_pre_aspas','vent_pre_cubre','vent_pre_pern',
  'vent_pre_cables','vent_pre_term','vent_pre_tierra','vent_pre_otro'
];
const _VKEYS_POST_INSP = [
  'vent_post_aspas','vent_post_cubre','vent_post_pern',
  'vent_post_cables','vent_post_term','vent_post_tierra','vent_post_giro'
];

// ---- Init ----

function nuevoVentilador() {
  const confirmar = confirm("¿Iniciar nuevo protocolo de ventilador?");
  if (!confirmar) return;
  _resetVent();
  _vSet('vent_numProtocolo', _generarNumVent());
  document.getElementById('vent_fecha').valueAsDate = new Date();
  document.getElementById('vent_cliente').value = 'CODELCO';
  const vFaena = document.getElementById('vent_faena'); if (vFaena) vFaena.selectedIndex = 0;
  const vArea  = document.getElementById('vent_area');  if (vArea)  vArea.selectedIndex  = 0;
  ['vent_evento','vent_tecnico','vent_equipo','vent_ventNum','vent_trabajo',
   'vent_marca','vent_numSerie','vent_numFases','vent_frame',
   'vent_grado','vent_claseAis','vent_frecuencia','vent_tension',
   'vent_potencia','vent_velocidad','vent_corriente','vent_conexion'
  ].forEach(id => _vSet(id, ''));
  mostrar('ventiladorDatos');
}

function _resetVent() {
  ventiladorData = {
    numProtocolo:'', gerencia:'Mantenimiento', cliente:'CODELCO',
    faena:'Andina', area:'Molienda', evento:'', tecnico:'',
    fecha:'', lugar:'', equipo:'', ventiladorNum:'', trabajo:'',
    marca:'', numSerie:'', numFases:'', frame:'', grado:'', claseAis:'',
    frecuencia:'', tension:'', potencia:'', velocidad:'', corriente:'', conexion:'',
    sino:{}, obs:{},
    postCorrL1:'', postCorrL2:'', postCorrL3:'', postCorrObs:'',
    trabajador:'', supervisor:''
  };
}

function _generarNumVent() {
  const d = new Date();
  const dd = String(d.getDate()).padStart(2,'0');
  const mm = String(d.getMonth()+1).padStart(2,'0');
  const yy = String(d.getFullYear()).slice(2);
  const hh = String(d.getHours()).padStart(2,'0');
  const mn = String(d.getMinutes()).padStart(2,'0');
  return `MV-${dd}${mm}${yy}-${hh}${mn}`;
}

function generarNumProtocoloVent() {
  _vSet('vent_numProtocolo', _generarNumVent());
}

// ---- SÍ / NO / N-A ----

function setSinoVent(base, val) {
  ['si','no','na'].forEach(opt => {
    const btn = document.getElementById(`${base}_${opt}`);
    if (!btn) return;
    btn.classList.remove('sino-si','sino-no','sino-na');
    if (opt === val) btn.classList.add(`sino-${opt}`);
    btn.dataset.selected = String(opt === val);
  });
}

function _getSino(base) {
  for (const opt of ['si','no','na']) {
    const btn = document.getElementById(`${base}_${opt}`);
    if (btn && btn.dataset.selected === 'true') return opt;
  }
  return '';
}

// ---- Recoger datos del DOM ----

function _recogerDatos() {
  const v = id => document.getElementById(id)?.value || '';
  ventiladorData.numProtocolo = v('vent_numProtocolo');
  ventiladorData.gerencia     = v('vent_gerencia');
  ventiladorData.cliente      = v('vent_cliente');
  ventiladorData.faena        = v('vent_faena');
  ventiladorData.area         = v('vent_area');
  ventiladorData.evento       = v('vent_evento');
  ventiladorData.tecnico      = v('vent_tecnico');
  ventiladorData.fecha        = v('vent_fecha');
  ventiladorData.lugar        = v('vent_lugar');
  ventiladorData.equipo       = v('vent_equipo');
  ventiladorData.ventiladorNum= v('vent_ventNum');
  ventiladorData.trabajo      = v('vent_trabajo');
  ventiladorData.marca        = v('vent_marca');
  ventiladorData.numSerie     = v('vent_numSerie');
  ventiladorData.numFases     = v('vent_numFases');
  ventiladorData.frame        = v('vent_frame');
  ventiladorData.grado        = v('vent_grado');
  ventiladorData.claseAis     = v('vent_claseAis');
  ventiladorData.frecuencia   = v('vent_frecuencia');
  ventiladorData.tension      = v('vent_tension');
  ventiladorData.potencia     = v('vent_potencia');
  ventiladorData.velocidad    = v('vent_velocidad');
  ventiladorData.corriente    = v('vent_corriente');
  ventiladorData.conexion     = v('vent_conexion');
}

function _recogerSino() {
  const all = [..._VKEYS_PRE_PRUEBAS, ..._VKEYS_PRE_INSP, ..._VKEYS_POST_INSP];
  all.forEach(k => {
    ventiladorData.sino[k] = _getSino(k);
    if (_MEDICION_KEYS.has(k)) {
      const val  = document.getElementById(`${k}_val`)?.value  || '';
      const unit = document.getElementById(`${k}_unit`)?.value || '';
      ventiladorData.obs[k] = val ? `${val} ${unit}` : '';
    } else {
      const obsEl = document.getElementById(`${k}_obs`);
      if (obsEl) ventiladorData.obs[k] = obsEl.value;
    }
  });
  ventiladorData.postCorrL1  = document.getElementById('vent_post_l1')?.value  || '';
  ventiladorData.postCorrL2  = document.getElementById('vent_post_l2')?.value  || '';
  ventiladorData.postCorrL3  = document.getElementById('vent_post_l3')?.value  || '';
  ventiladorData.postCorrObs = document.getElementById('vent_post_corr_obs')?.value || '';
  ventiladorData.trabajador  = document.getElementById('vent_trabajador')?.value || '';
  ventiladorData.supervisor  = document.getElementById('vent_supervisor')?.value || '';
}

// ---- Poblar DOM desde datos ----

function _poblarDatos() {
  _vSet('vent_numProtocolo', ventiladorData.numProtocolo);
  _vSet('vent_gerencia',     ventiladorData.gerencia || 'Mantenimiento');
  _vSet('vent_fecha',        ventiladorData.fecha);
  _vSet('vent_equipo',       ventiladorData.equipo);
  _vSet('vent_evento',       ventiladorData.evento);
  _vSet('vent_tecnico',      ventiladorData.tecnico);
  _vSet('vent_ventNum',      ventiladorData.ventiladorNum);
  _vSet('vent_trabajo',      ventiladorData.trabajo);
  _vSet('vent_marca',        ventiladorData.marca);
  _vSet('vent_numSerie',     ventiladorData.numSerie);
  _vSet('vent_numFases',     ventiladorData.numFases);
  _vSet('vent_frame',        ventiladorData.frame);
  _vSet('vent_grado',        ventiladorData.grado);
  _vSet('vent_claseAis',     ventiladorData.claseAis);
  _vSet('vent_frecuencia',   ventiladorData.frecuencia);
  _vSet('vent_tension',      ventiladorData.tension);
  _vSet('vent_potencia',     ventiladorData.potencia);
  _vSet('vent_velocidad',    ventiladorData.velocidad);
  _vSet('vent_corriente',    ventiladorData.corriente);
  _vSet('vent_conexion',     ventiladorData.conexion);
  const cl = document.getElementById('vent_cliente');
  if (cl) cl.value = ventiladorData.cliente || 'CODELCO';
  const vf = document.getElementById('vent_faena');
  if (vf) vf.value = ventiladorData.faena || 'Andina';
  const va = document.getElementById('vent_area');
  if (va) va.value = ventiladorData.area || 'Molienda';
}

function _poblarSino() {
  const sino = ventiladorData.sino || {};
  const obs  = ventiladorData.obs  || {};
  Object.keys(sino).forEach(k => {
    if (sino[k]) setSinoVent(k, sino[k]);
    if (_MEDICION_KEYS.has(k)) {
      const saved = obs[k] || '';
      const spIdx = saved.lastIndexOf(' ');
      const val   = spIdx > -1 ? saved.slice(0, spIdx) : saved;
      const unit  = spIdx > -1 ? saved.slice(spIdx + 1) : '';
      const valEl  = document.getElementById(`${k}_val`);
      const unitEl = document.getElementById(`${k}_unit`);
      if (valEl)          valEl.value  = val;
      if (unitEl && unit) unitEl.value = unit;
    } else {
      const el = document.getElementById(`${k}_obs`);
      if (el && obs[k]) el.value = obs[k];
    }
  });
  _vSet('vent_post_l1',       ventiladorData.postCorrL1);
  _vSet('vent_post_l2',       ventiladorData.postCorrL2);
  _vSet('vent_post_l3',       ventiladorData.postCorrL3);
  _vSet('vent_post_corr_obs', ventiladorData.postCorrObs);
  _vSet('vent_trabajador',    ventiladorData.trabajador);
  _vSet('vent_supervisor',    ventiladorData.supervisor);
}

function _vSet(id, val) {
  const el = document.getElementById(id);
  if (el) el.value = val || '';
}

// ---- Navegación ----

function irVentiladorPre() {
  _recogerDatos();
  mostrar('ventiladorPre');
  _poblarSino();
}

function irVentiladorPost() {
  _recogerSino();
  mostrar('ventiladorPost');
  _poblarSino();
}

// ---- Guardar / Retomar ----

function guardarVentilador() {
  _recogerDatos();
  _recogerSino();
  if (!ventiladorData.numProtocolo) {
    alert('Ingresa el N° de protocolo antes de guardar');
    mostrar('ventiladorDatos');
    return;
  }
  let lista = JSON.parse(localStorage.getItem('ventiladorAYCA_lista') || '[]');
  const idx = lista.findIndex(p => p.numProtocolo === ventiladorData.numProtocolo);
  const res = { numProtocolo: ventiladorData.numProtocolo, cliente: ventiladorData.cliente,
                faena: ventiladorData.faena, area: ventiladorData.area,
                equipo: ventiladorData.equipo, fecha: ventiladorData.fecha,
                tecnico: ventiladorData.tecnico };
  if (idx >= 0) lista[idx] = res; else lista.unshift(res);
  localStorage.setItem('ventiladorAYCA_lista', JSON.stringify(lista));
  localStorage.setItem(`ventilador_${ventiladorData.numProtocolo}`, JSON.stringify(ventiladorData));

  // Encolar para sincronización con nube
  if (typeof encolarSync === 'function') {
    encolarSync('ventilador', ventiladorData.numProtocolo);
    if (navigator.onLine && typeof sincronizarTodo === 'function') sincronizarTodo();
  }

  alert(`✅ Protocolo ${ventiladorData.numProtocolo} guardado${navigator.onLine ? ' y enviado a la nube' : ' en el dispositivo (se sincronizará al recuperar conexión)'}`);
  mostrar('panel');
}

function retomarVentilador(numProtocolo) {
  const raw = localStorage.getItem(`ventilador_${numProtocolo}`);
  if (!raw) { alert('Protocolo no encontrado'); return; }
  ventiladorData = JSON.parse(raw);
  _poblarDatos();
  mostrar('ventiladorDatos');
}

function guardarAvanceVentilador() {
  _recogerDatos();
  _recogerSino();
  const num = ventiladorData.numProtocolo;
  if (!num) { alert('Ingresa el N° de protocolo antes de guardar'); return; }
  let lista = JSON.parse(localStorage.getItem('ventiladorAYCA_lista') || '[]');
  const res = { numProtocolo: num, cliente: ventiladorData.cliente, faena: ventiladorData.faena,
                equipo: ventiladorData.equipo, fecha: ventiladorData.fecha, tecnico: ventiladorData.tecnico };
  const idx = lista.findIndex(p => p.numProtocolo === num);
  if (idx >= 0) lista[idx] = res; else lista.unshift(res);
  localStorage.setItem('ventiladorAYCA_lista', JSON.stringify(lista));
  localStorage.setItem(`ventilador_${num}`, JSON.stringify(ventiladorData));
  if (typeof encolarSync === 'function') encolarSync('ventilador', num);
  alert('✅ Avance guardado');
}

function mostrarListaVentiladores() {
  const cont = document.getElementById('vent_listaGuardados');
  if (!cont) return;
  const lista = JSON.parse(localStorage.getItem('ventiladorAYCA_lista') || '[]');
  if (lista.length === 0) {
    cont.innerHTML = '<p style="font-size:12px;color:#888">No hay protocolos guardados.</p>';
    return;
  }
  cont.innerHTML = lista.map(p => `
    <div style="display:flex;justify-content:space-between;align-items:center;border:1px solid #e2e8f0;border-radius:8px;padding:8px 10px;margin-bottom:6px">
      <div>
        <div style="font-weight:bold;font-size:13px">${p.numProtocolo}</div>
        <div style="font-size:11px;color:#555">${p.cliente} · ${p.equipo} · ${p.fecha}</div>
      </div>
      <button onclick="retomarVentilador('${p.numProtocolo}')" style="margin:0;padding:8px 10px;font-size:12px;white-space:nowrap">📂 Retomar</button>
    </div>
  `).join('');
}

// ---- PDF ----

function generarPDFVentilador() {
  _recogerDatos();
  _recogerSino();
  if (!window.jspdf) { alert("jsPDF no está cargado."); return; }
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF("p","mm","a4");
  const azul = [11,49,88];
  const d = ventiladorData;

  // Encabezado
  doc.setFillColor(...azul);
  doc.rect(0,0,210,28,"F");
  doc.setTextColor(255,255,255);
  doc.setFont("helvetica","bold");
  doc.setFontSize(17);
  doc.text("AYCA SMART MAINTENANCE",105,11,{align:"center"});
  doc.setFontSize(10);
  doc.text("ACCIONAMIENTO Y CONTROL AUTOMÁTICO",105,18,{align:"center"});
  doc.setFontSize(13);
  doc.text("PROTOCOLO DE INSPECCIÓN MOTOR VENTILADOR",105,25,{align:"center"});
  doc.setTextColor(0,0,0);

  // Datos generales
  doc.autoTable({
    startY:32,
    body:[
      ["Gerencia",d.gerencia,"Fecha",d.fecha],
      ["Cliente",d.cliente,"Lugar",d.lugar],
      ["Equipo",d.equipo,"Ventilador N°",d.ventiladorNum],
      ["N° Protocolo",d.numProtocolo,"",""]
    ],
    theme:"grid",styles:{fontSize:9},
    columnStyles:{0:{fontStyle:"bold",fillColor:[235,240,245]},2:{fontStyle:"bold",fillColor:[235,240,245]}}
  });

  let y = doc.lastAutoTable.finalY+2;
  if (d.trabajo) {
    doc.setFontSize(9); doc.setFont("helvetica","normal");
    doc.text(`Trabajo a Ejecutar: ${d.trabajo}`,14,y+4);
    y+=7;
  }

  // Datos técnicos
  doc.setFillColor(...azul);
  doc.rect(14,y,182,6,"F");
  doc.setTextColor(255,255,255); doc.setFont("helvetica","bold"); doc.setFontSize(10);
  doc.text("DATOS TÉCNICOS",16,y+4.5);
  doc.setTextColor(0,0,0); y+=8;

  doc.autoTable({
    startY:y,
    body:[
      ["Marca",d.marca,"N° Serie",d.numSerie],
      ["N° Fases",d.numFases,"Frame (carcaza)",d.frame],
      ["Grado protección",d.grado,"Clase aislamiento",d.claseAis],
      ["Frecuencia",d.frecuencia,"Tensión nominal",d.tension],
      ["Potencia nominal",d.potencia,"Velocidad nominal",d.velocidad],
      ["Corriente nominal",d.corriente,"Conexión en placa",d.conexion]
    ],
    theme:"grid",styles:{fontSize:9},
    columnStyles:{0:{fontStyle:"bold",fillColor:[235,240,245]},2:{fontStyle:"bold",fillColor:[235,240,245]}}
  });

  y = doc.lastAutoTable.finalY+4;

  // Helper sino
  const sx = k => { const v=d.sino[k]; return {si:v==='si'?'x':'',no:v==='no'?'x':'',na:v==='na'?'x':''}; };

  // PRE pruebas
  doc.setFillColor(...azul);
  doc.rect(14,y,182,6,"F");
  doc.setTextColor(255,255,255); doc.setFont("helvetica","bold"); doc.setFontSize(9);
  doc.text("Pruebas generales a ventiladores PRE.",16,y+4.5);
  doc.setTextColor(0,0,0); y+=8;

  doc.autoTable({
    startY:y,
    head:[["Prueba al equipo","SÍ","NO","N/A","Observaciones / valor medido"]],
    body:[
      ["Prueba de resistencia ohmica L1 - L2",...Object.values(sx('vent_pre_ohm12')),d.obs['vent_pre_ohm12']||''],
      ["Prueba de resistencia ohmica L2 - L3",...Object.values(sx('vent_pre_ohm23')),d.obs['vent_pre_ohm23']||''],
      ["Prueba de resistencia ohmica L1 - L3",...Object.values(sx('vent_pre_ohm13')),d.obs['vent_pre_ohm13']||''],
      ["Prueba de resistencia de aislación 1\" L-1",...Object.values(sx('vent_pre_ais1')),d.obs['vent_pre_ais1']||''],
      ["Prueba de resistencia de aislación 1\" L-2",...Object.values(sx('vent_pre_ais2')),d.obs['vent_pre_ais2']||''],
      ["Prueba de resistencia de aislación 1\" L-3",...Object.values(sx('vent_pre_ais3')),d.obs['vent_pre_ais3']||''],
      ["Prueba de aislación IP estator",...Object.values(sx('vent_pre_ip')),d.obs['vent_pre_ip']||'']
    ],
    theme:"grid",styles:{fontSize:8},headStyles:{fillColor:azul},
    columnStyles:{0:{cellWidth:70},1:{halign:'center',cellWidth:10},2:{halign:'center',cellWidth:10},3:{halign:'center',cellWidth:10}}
  });

  y = doc.lastAutoTable.finalY+4;

  // PRE inspecciones
  doc.setFillColor(...azul);
  doc.rect(14,y,182,6,"F");
  doc.setTextColor(255,255,255); doc.setFont("helvetica","bold"); doc.setFontSize(9);
  doc.text("Inspecciones generales a ventiladores PRE.",16,y+4.5);
  doc.setTextColor(0,0,0); y+=8;

  doc.autoTable({
    startY:y,
    head:[["Inspección al equipo","SÍ","NO","N/A","Observaciones"]],
    body:[
      ["Chequeo de aspas de ventilación",...Object.values(sx('vent_pre_aspas')),d.obs['vent_pre_aspas']||''],
      ["Chequeo de cubre aspas de ventilación",...Object.values(sx('vent_pre_cubre')),d.obs['vent_pre_cubre']||''],
      ["Chequeo de pernería en general",...Object.values(sx('vent_pre_pern')),d.obs['vent_pre_pern']||''],
      ["Inspección de cables en caja de conexión",...Object.values(sx('vent_pre_cables')),d.obs['vent_pre_cables']||''],
      ["Inspección de terminales de conexión",...Object.values(sx('vent_pre_term')),d.obs['vent_pre_term']||''],
      ["Verificación de conexión a tierra",...Object.values(sx('vent_pre_tierra')),d.obs['vent_pre_tierra']||''],
      ["Otro",...Object.values(sx('vent_pre_otro')),d.obs['vent_pre_otro']||'']
    ],
    theme:"grid",styles:{fontSize:8},headStyles:{fillColor:azul},
    columnStyles:{0:{cellWidth:70},1:{halign:'center',cellWidth:10},2:{halign:'center',cellWidth:10},3:{halign:'center',cellWidth:10}}
  });

  y = doc.lastAutoTable.finalY+4;
  if (y > 230) { doc.addPage(); y = 20; }

  // POST pruebas corriente
  doc.setFillColor(...azul);
  doc.rect(14,y,182,6,"F");
  doc.setTextColor(255,255,255); doc.setFont("helvetica","bold"); doc.setFontSize(9);
  doc.text("Pruebas a ventiladores POST.",16,y+4.5);
  doc.setTextColor(0,0,0); y+=8;

  doc.autoTable({
    startY:y,
    head:[["Prueba","L1 (A)","L2 (A)","L3 (A)","Observaciones"]],
    body:[["Registro de corriente nominal (A)",d.postCorrL1,d.postCorrL2,d.postCorrL3,d.postCorrObs||'']],
    theme:"grid",styles:{fontSize:8,halign:'center'},headStyles:{fillColor:azul},
    columnStyles:{0:{halign:'left',cellWidth:60}}
  });

  y = doc.lastAutoTable.finalY+4;

  // POST inspecciones
  doc.setFillColor(...azul);
  doc.rect(14,y,182,6,"F");
  doc.setTextColor(255,255,255); doc.setFont("helvetica","bold"); doc.setFontSize(9);
  doc.text("Inspecciones generales a ventiladores POST.",16,y+4.5);
  doc.setTextColor(0,0,0); y+=8;

  doc.autoTable({
    startY:y,
    head:[["Inspección al equipo","SÍ","NO","N/A","Observaciones"]],
    body:[
      ["Chequeo de aspas de ventilación",...Object.values(sx('vent_post_aspas')),d.obs['vent_post_aspas']||''],
      ["Chequeo de cubre aspas de ventilación",...Object.values(sx('vent_post_cubre')),d.obs['vent_post_cubre']||''],
      ["Chequeo de pernería en general",...Object.values(sx('vent_post_pern')),d.obs['vent_post_pern']||''],
      ["Inspección de cables en caja de conexión",...Object.values(sx('vent_post_cables')),d.obs['vent_post_cables']||''],
      ["Inspección de terminales de conexión",...Object.values(sx('vent_post_term')),d.obs['vent_post_term']||''],
      ["Verificación de conexión a tierra",...Object.values(sx('vent_post_tierra')),d.obs['vent_post_tierra']||''],
      ["Verificación de sentido de giro",...Object.values(sx('vent_post_giro')),d.obs['vent_post_giro']||'']
    ],
    theme:"grid",styles:{fontSize:8},headStyles:{fillColor:azul},
    columnStyles:{0:{cellWidth:70},1:{halign:'center',cellWidth:10},2:{halign:'center',cellWidth:10},3:{halign:'center',cellWidth:10}}
  });

  y = doc.lastAutoTable.finalY+6;

  // Firmas
  doc.autoTable({
    startY:y,
    body:[
      ["Nombre Trabajador", d.trabajador||'________________', "Firma", ""],
      ["Nombre Supervisor",  d.supervisor||'________________',  "Firma", ""]
    ],
    theme:"grid",styles:{fontSize:9},
    columnStyles:{0:{fontStyle:"bold",fillColor:[235,240,245],cellWidth:40},2:{fontStyle:"bold",fillColor:[235,240,245],cellWidth:20}}
  });

  // Pie
  const total = doc.getNumberOfPages();
  for (let p=1;p<=total;p++) {
    doc.setPage(p);
    doc.setFont("helvetica","normal"); doc.setFontSize(8); doc.setTextColor(120,120,120);
    doc.text(`Pág. ${p} de ${total}`,105,292,{align:"center"});
    doc.text("AYCA — Accionamiento y Control Automático",14,292);
  }

  doc.save(`${d.numProtocolo||'MV'}_Ventilador.pdf`);
}

// ══════════════════════════════════════════════════════
// PROTOCOLO DE ENTREGA — VENTILADOR
// ══════════════════════════════════════════════════════
function generarEntregaVentilador() {
  _recogerDatos();
  _recogerSino();
  if (!window.jspdf) { alert("jsPDF no está cargado."); return; }

  const { jsPDF } = window.jspdf;
  const doc = new jsPDF("p","mm","a4");
  const d = ventiladorData;

  const BL=[255,255,255], BK=[0,0,0], gH=[220,220,220], gSH=[240,240,240], azul=[11,49,88];
  const tblBase={theme:'grid',styles:{fontSize:7.5,halign:'center',cellPadding:2,fillColor:BL,textColor:BK,lineColor:BK,lineWidth:0.3}};

  // Encabezado AyCA
  doc.setFont("helvetica","bold"); doc.setFontSize(22); doc.setTextColor(0,0,0);
  doc.text("AyCA",14,14);
  doc.setFont("helvetica","normal"); doc.setFontSize(9);
  doc.text("Accionamiento y Control Automático",14,21);
  doc.setDrawColor(0,0,0); doc.setLineWidth(0.5);
  doc.rect(148,5,48,16); doc.line(148,13,196,13);
  doc.setFont("helvetica","normal"); doc.setFontSize(9);
  doc.text("Codigo: PT-1005",172,10,{align:"center"});
  doc.text("Revisión: 1",    172,18,{align:"center"});
  doc.setLineWidth(0.8); doc.line(14,25,196,25);

  let y=31;

  // Datos generales
  doc.setFontSize(9.5);
  [["N° Protocolo:",d.numProtocolo,"Fecha:",  d.fecha],
   ["Cliente:",     d.cliente,     "Faena:",  d.faena],
   ["Equipo:",      d.equipo,      "Técnico:",d.tecnico],
   ["Área:",        d.area,        "Evento:", d.evento]
  ].forEach(([l1,v1,l2,v2])=>{
    doc.setFont("helvetica","bold");   doc.text(l1, 14,y);
    doc.setFont("helvetica","normal"); doc.text(v1||"", 46,y);
    doc.setFont("helvetica","bold");   doc.text(l2,114,y);
    doc.setFont("helvetica","normal"); doc.text(v2||"",138,y);
    y+=5.5;
  });
  doc.setLineWidth(0.4); doc.line(14,y,196,y); y+=6;

  // Título
  doc.setFont("helvetica","bold"); doc.setFontSize(15); doc.setTextColor(0,0,0);
  doc.text("1   PROTOCOLO DE INSPECCIÓN MOTOR VENTILADOR",14,y); y+=7;

  // Datos técnicos (cols: 42+49+42+49=182mm)
  const lT=txt=>({content:txt,styles:{fontStyle:'bold',halign:'left',fillColor:gSH,textColor:BK}});
  doc.autoTable({...tblBase,startY:y,
    body:[
      [lT("Marca"),d.marca,lT("N° Serie"),d.numSerie],
      [lT("N° Fases"),d.numFases,lT("Frame"),d.frame],
      [lT("Grado protección"),d.grado,lT("Clase aislamiento"),d.claseAis],
      [lT("Frecuencia"),d.frecuencia,lT("Tensión nominal"),d.tension],
      [lT("Potencia nominal"),d.potencia,lT("Velocidad nominal"),d.velocidad],
      [lT("Corriente nominal"),d.corriente,lT("Conexión"),d.conexion]
    ],
    columnStyles:{0:{cellWidth:42,halign:'left'},1:{cellWidth:49},2:{cellWidth:42,halign:'left'},3:{cellWidth:49}},
    margin:{left:14,right:14}
  });
  y=doc.lastAutoTable.finalY+4;

  // Helper sino: returns [SÍ, NO, N/A] marks — X en negrita para la opción marcada
  // Cada celda recibe un objeto nuevo (jsPDF-AutoTable puede mutar los objetos al renderizar)
  const mkX = () => ({content:'X', styles:{fontStyle:'bold', fontSize:10, halign:'center'}});
  const sx = k => { const v=d.sino[k]; return [v==='si'?mkX():'', v==='no'?mkX():'', v==='na'?mkX():'']; };

  // jsPDF usa Latin-1: Ω (U+03A9) no existe → aparece como © y espacía el texto.
  // Sustituir solo al generar PDF; la app sigue mostrando el símbolo correcto.
  const pu = s => (s || '').replace(/Ω/g, 'Ohm');
  const ob = k => pu(d.obs[k] || '');

  // Header for inspection tables (cols: 76+10+10+10+76=182mm)
  const inHead=titulo=>[
    [{content:titulo,colSpan:5,styles:{fillColor:gH,halign:'center',fontStyle:'bold',fontSize:8,textColor:BK}}],
    ['Descripción','SÍ','NO','N/A','Observaciones'].map(t=>
      ({content:t,styles:{fillColor:gSH,halign:'center',fontStyle:'bold',fontSize:7,textColor:BK}}))
  ];
  const iCols={0:{cellWidth:76,halign:'left'},1:{cellWidth:10},2:{cellWidth:10},3:{cellWidth:10},4:{cellWidth:76,halign:'left'}};

  // PRE pruebas
  doc.autoTable({...tblBase,startY:y,
    head:inHead("Pruebas Generales PRE"),
    body:[
      ["Resistencia óhmica L1-L2", ...sx('vent_pre_ohm12'), ob('vent_pre_ohm12')],
      ["Resistencia óhmica L2-L3", ...sx('vent_pre_ohm23'), ob('vent_pre_ohm23')],
      ["Resistencia óhmica L1-L3", ...sx('vent_pre_ohm13'), ob('vent_pre_ohm13')],
      ["Resistencia aislación L-1",...sx('vent_pre_ais1'),  ob('vent_pre_ais1') ],
      ["Resistencia aislación L-2",...sx('vent_pre_ais2'),  ob('vent_pre_ais2') ],
      ["Resistencia aislación L-3",...sx('vent_pre_ais3'),  ob('vent_pre_ais3') ],
      ["Aislación IP estator",     ...sx('vent_pre_ip'),    ob('vent_pre_ip')   ]
    ],
    columnStyles:iCols, margin:{left:14,right:14}
  });
  y=doc.lastAutoTable.finalY+3;

  // PRE inspecciones
  doc.autoTable({...tblBase,startY:y,
    head:inHead("Inspecciones Generales PRE"),
    body:[
      ["Aspas de ventilación",       ...sx('vent_pre_aspas'), d.obs['vent_pre_aspas'] ||''],
      ["Cubre aspas de ventilación", ...sx('vent_pre_cubre'), d.obs['vent_pre_cubre'] ||''],
      ["Pernería en general",        ...sx('vent_pre_pern'),  d.obs['vent_pre_pern']  ||''],
      ["Cables en caja de conexión", ...sx('vent_pre_cables'),d.obs['vent_pre_cables']||''],
      ["Terminales de conexión",     ...sx('vent_pre_term'),  d.obs['vent_pre_term']  ||''],
      ["Conexión a tierra",          ...sx('vent_pre_tierra'),d.obs['vent_pre_tierra']||''],
      ["Otro",                       ...sx('vent_pre_otro'),  d.obs['vent_pre_otro']  ||'']
    ],
    columnStyles:iCols, margin:{left:14,right:14}
  });
  y=doc.lastAutoTable.finalY+3;

  if(y>230){doc.addPage();y=20;}

  // POST corriente (cols: 76+22+22+22+40=182mm)
  doc.autoTable({...tblBase,startY:y,
    head:[
      [{content:"Corriente de Trabajo POST",colSpan:5,styles:{fillColor:gH,halign:'center',fontStyle:'bold',fontSize:8,textColor:BK}}],
      ['Prueba','L1 (A)','L2 (A)','L3 (A)','Observaciones'].map(t=>
        ({content:t,styles:{fillColor:gSH,halign:'center',fontStyle:'bold',fontSize:7,textColor:BK}}))
    ],
    body:[["Corriente nominal (A)",d.postCorrL1||'',d.postCorrL2||'',d.postCorrL3||'',d.postCorrObs||'']],
    columnStyles:{0:{cellWidth:76,halign:'left'},1:{cellWidth:22},2:{cellWidth:22},3:{cellWidth:22},4:{cellWidth:40,halign:'left'}},
    margin:{left:14,right:14}
  });
  y=doc.lastAutoTable.finalY+3;

  // POST inspecciones
  doc.autoTable({...tblBase,startY:y,
    head:inHead("Inspecciones Generales POST"),
    body:[
      ["Aspas de ventilación",       ...sx('vent_post_aspas'), d.obs['vent_post_aspas'] ||''],
      ["Cubre aspas de ventilación", ...sx('vent_post_cubre'), d.obs['vent_post_cubre'] ||''],
      ["Pernería en general",        ...sx('vent_post_pern'),  d.obs['vent_post_pern']  ||''],
      ["Cables en caja de conexión", ...sx('vent_post_cables'),d.obs['vent_post_cables']||''],
      ["Terminales de conexión",     ...sx('vent_post_term'),  d.obs['vent_post_term']  ||''],
      ["Conexión a tierra",          ...sx('vent_post_tierra'),d.obs['vent_post_tierra']||''],
      ["Sentido de giro",            ...sx('vent_post_giro'),  d.obs['vent_post_giro']  ||'']
    ],
    columnStyles:iCols, margin:{left:14,right:14}
  });
  y=doc.lastAutoTable.finalY+6;

  // Firmas
  if(y>250){doc.addPage();y=30;}
  doc.setLineWidth(0.4); doc.line(14,y,196,y); y+=10;
  doc.setFont("helvetica","normal"); doc.setFontSize(9);
  doc.line(14,y+15,88,y+15);   doc.text("Técnico Responsable AyCA",14,y+21);
  doc.line(108,y+15,196,y+15); doc.text("Supervisor / Cliente",108,y+21);

  const total=doc.getNumberOfPages();
  for(let p=1;p<=total;p++){
    doc.setPage(p);
    doc.setFont("helvetica","normal"); doc.setFontSize(6.5); doc.setTextColor(100,100,100);
    doc.text("Servicios en Accionamiento y Control Automático SpA. RUT 76.845.043-9  Av. Pdte. Kennedy Lateral 7900, Oficina 502, Vitacura, Santiago, Chile. Teléfono +569 23266267",105,290,{align:"center",maxWidth:182});
  }
  doc.save(`${d.numProtocolo||'MV'}_Entrega.pdf`);
}
