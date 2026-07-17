// ===============================
// PROTOCOLO CARBONES - AYCA
// ===============================

let carbonesData = {};

const AREA_CONTACTO_RESORTE_CM2 = 4;

// ---- Init ----

function nuevoCarbones() {
  const confirmar = confirm("¿Iniciar nuevo protocolo de carbones?");
  if (!confirmar) return;
  _resetCarbones();
  document.getElementById('carb_numProtocolo').value = _generarNumCarb();
  document.getElementById('carb_fecha').valueAsDate = new Date();
  document.getElementById('carb_cliente').value = 'CODELCO';
  const carFaena = document.getElementById('carb_faena'); if (carFaena) carFaena.selectedIndex = 0;
  const carArea  = document.getElementById('carb_area');  if (carArea)  carArea.selectedIndex  = 0;
  document.getElementById('carb_equipo').value = '';
  const carEvento = document.getElementById('carb_evento'); if (carEvento) carEvento.value = '';
  document.getElementById('carb_tecnico').value = '';
  _seleccionarNumCarbones(6);
  mostrar('carbonesDatos');
}

function _resetCarbones() {
  carbonesData = {
    numProtocolo: '',
    cliente: 'CODELCO',
    faena: 'Andina',
    area: 'Molienda',
    equipo: '',
    evento: '',
    fecha: '',
    tecnico: '',
    observaciones: '',
    numCarbones: 6,
    largo: {
      ladoTapa:   Array.from({length:8}, () => ({l1:'', alt:8, l2:'', c1:'OK', c2:'OK'})),
      tierra:     [{l1:'', alt:8, l2:'', c1:'OK', c2:'OK'}, {l1:'', alt:8, l2:'', c1:'OK', c2:'OK'}],
      ladoBobina: Array.from({length:8}, () => ({l1:'', alt:8, l2:'', c1:'OK', c2:'OK'}))
    },
    tension: {
      ladoTapa:   Array.from({length:8}, () => ({t1:'', t2:''})),
      tierra:     [{t1:'', t2:''}, {t1:'', t2:''}],
      ladoBobina: Array.from({length:8}, () => ({t1:'', t2:''}))
    }
  };
}

function _generarNumCarb() {
  const d = new Date();
  const dd = String(d.getDate()).padStart(2,'0');
  const mm = String(d.getMonth()+1).padStart(2,'0');
  const yy = String(d.getFullYear()).slice(2);
  const hh = String(d.getHours()).padStart(2,'0');
  const mn = String(d.getMinutes()).padStart(2,'0');
  return `CB-${dd}${mm}${yy}-${hh}${mn}`;
}

function generarNumProtocoloCarb() {
  document.getElementById('carb_numProtocolo').value = _generarNumCarb();
}

// ---- Número de carbones ----

function _seleccionarNumCarbones(n) {
  document.querySelectorAll('.btn-numCarb').forEach(b => {
    b.classList.toggle('seleccionado', parseInt(b.dataset.n) === n);
  });
  carbonesData.numCarbones = n;
}

function seleccionarNumCarbones(n) {
  _seleccionarNumCarbones(n);
}

// ---- Visibilidad de filas ----

function _actualizarFilas() {
  const n = carbonesData.numCarbones;
  for (let i = 1; i <= 8; i++) {
    const vis = i <= n ? '' : 'none';
    ['fila-lt-','fila-lb-','fila-tt-','fila-tb-'].forEach(cls => {
      const el = document.querySelector(`.${cls}${i}`);
      if (el) el.style.display = vis;
    });
  }
  _calcularTotales();
}

// ---- Altura: actualiza totales al cambiar ----

document.addEventListener('DOMContentLoaded', () => {
  document.addEventListener('input', e => {
    if (e.target.classList.contains('inp-alt')) _calcularTotales();
  });
});

// ---- Auto-criterio por largo ----

function autoCriterioCarb(input, critId) {
  const v = parseFloat(input.value);
  const sel = document.getElementById(critId);
  if (!sel) return;
  if (!isNaN(v)) {
    if (v < 40)      sel.value = 'BM';
    else if (v < 43) sel.value = 'P';
    else             sel.value = 'OK';
  }
  colorCriterio(sel);
  _calcularTotales();
}

function colorCriterio(sel) {
  const mapa = { OK:'#dcfce7', BM:'#fecaca', P:'#fef9c3', D:'#fecaca' };
  sel.style.background = mapa[sel.value] || '';
}

// ---- Totales ----

function calcularTotalesCarbones() { _calcularTotales(); }

function _calcularTotales() {
  const n = carbonesData.numCarbones;
  let remp = 0, ajus = 0;

  // LT y LB: n carbones activos
  for (let i = 1; i <= n; i++) {
    ['lt_c1','lt_c2','lb_c1','lb_c2'].forEach(k => {
      const v = document.getElementById(`carb_${k}_${i}`)?.value;
      if (v === 'BM' || v === 'D') remp++;
    });
    ['lt','lb'].forEach(side => {
      const alt = parseFloat(document.getElementById(`carb_${side}_alt_${i}`)?.value);
      if (!isNaN(alt) && alt < 8) ajus++;
    });
  }

  // Tierra: siempre 2 filas
  for (let i = 1; i <= 2; i++) {
    const vc1 = document.getElementById(`carb_tier_c1_${i}`)?.value;
    const vc2 = document.getElementById(`carb_tier_c2_${i}`)?.value;
    if (vc1 === 'BM' || vc1 === 'D') remp++;
    if (vc2 === 'BM' || vc2 === 'D') remp++;
    const alt = parseFloat(document.getElementById(`carb_tier_alt_${i}`)?.value);
    if (!isNaN(alt) && alt < 8) ajus++;
  }

  const er = document.getElementById('carb_totalRemp');
  const ea = document.getElementById('carb_totalAjus');
  if (er) er.textContent = remp;
  if (ea) ea.textContent = ajus;
}

// ---- Navegación ----

function _recogerDatosCarb() {
  const g = id => document.getElementById(id)?.value || '';
  carbonesData.numProtocolo = g('carb_numProtocolo');
  carbonesData.cliente      = g('carb_cliente');
  carbonesData.faena        = g('carb_faena');
  carbonesData.area         = g('carb_area');
  carbonesData.equipo       = g('carb_equipo');
  carbonesData.evento       = g('carb_evento');
  carbonesData.fecha        = g('carb_fecha');
  carbonesData.tecnico      = g('carb_tecnico');
}

function irCarbonLargo() {
  _recogerDatosCarb();
  mostrar('carbonesLargo');
  _actualizarFilas();
  _poblarLargo();
}

function irCarbonTension() {
  _recogerLargo();
  mostrar('carbonesTension');
  _actualizarFilas();
  _poblarTension();
}

// ---- Recoger datos del DOM ----

function _recogerLargo() {
  for (let i = 1; i <= 8; i++) {
    carbonesData.largo.ladoTapa[i-1] = {
      l1:  document.getElementById(`carb_lt_l1_${i}`)?.value  || '',
      alt: document.getElementById(`carb_lt_alt_${i}`)?.value || 10,
      l2:  document.getElementById(`carb_lt_l2_${i}`)?.value  || '',
      c1:  document.getElementById(`carb_lt_c1_${i}`)?.value  || 'OK',
      c2:  document.getElementById(`carb_lt_c2_${i}`)?.value  || 'OK'
    };
    carbonesData.largo.ladoBobina[i-1] = {
      l1:  document.getElementById(`carb_lb_l1_${i}`)?.value  || '',
      alt: document.getElementById(`carb_lb_alt_${i}`)?.value || 10,
      l2:  document.getElementById(`carb_lb_l2_${i}`)?.value  || '',
      c1:  document.getElementById(`carb_lb_c1_${i}`)?.value  || 'OK',
      c2:  document.getElementById(`carb_lb_c2_${i}`)?.value  || 'OK'
    };
  }
  for (let i = 1; i <= 2; i++) {
    carbonesData.largo.tierra[i-1] = {
      l1:  document.getElementById(`carb_tier_l1_${i}`)?.value  || '',
      alt: document.getElementById(`carb_tier_alt_${i}`)?.value || 10,
      l2:  document.getElementById(`carb_tier_l2_${i}`)?.value  || '',
      c1:  document.getElementById(`carb_tier_c1_${i}`)?.value  || 'OK',
      c2:  document.getElementById(`carb_tier_c2_${i}`)?.value  || 'OK'
    };
  }
}

function _recogerTension() {
  for (let i = 1; i <= 8; i++) {
    carbonesData.tension.ladoTapa[i-1]   = { t1: document.getElementById(`carb_tt_t1_${i}`)?.value||'', t2: document.getElementById(`carb_tt_t2_${i}`)?.value||'' };
    carbonesData.tension.ladoBobina[i-1] = { t1: document.getElementById(`carb_tb_t1_${i}`)?.value||'', t2: document.getElementById(`carb_tb_t2_${i}`)?.value||'' };
  }
  for (let i = 1; i <= 2; i++) {
    carbonesData.tension.tierra[i-1] = { t1: document.getElementById(`carb_ttier_t1_${i}`)?.value||'', t2: document.getElementById(`carb_ttier_t2_${i}`)?.value||'' };
  }
  carbonesData.observaciones = document.getElementById('carb_observaciones')?.value || '';
}

// ---- Poblar DOM desde datos ----

function _poblarLargo() {
  for (let i = 1; i <= 8; i++) {
    const lt = carbonesData.largo.ladoTapa[i-1]   || {};
    const lb = carbonesData.largo.ladoBobina[i-1] || {};
    _set(`carb_lt_alt_${i}`, lt.alt ?? 8);
    _set(`carb_lt_l1_${i}`,  lt.l1 || '');
    _setSelect(`carb_lt_c1_${i}`, lt.c1 || 'OK');
    _set(`carb_lt_l2_${i}`,  lt.l2 || '');
    _setSelect(`carb_lt_c2_${i}`, lt.c2 || 'OK');
    _set(`carb_lb_alt_${i}`, lb.alt ?? 8);
    _set(`carb_lb_l1_${i}`,  lb.l1 || '');
    _setSelect(`carb_lb_c1_${i}`, lb.c1 || 'OK');
    _set(`carb_lb_l2_${i}`,  lb.l2 || '');
    _setSelect(`carb_lb_c2_${i}`, lb.c2 || 'OK');
  }
  for (let i = 1; i <= 2; i++) {
    const t = carbonesData.largo.tierra[i-1] || {};
    _set(`carb_tier_l1_${i}`,  t.l1 || '');
    _set(`carb_tier_alt_${i}`, t.alt ?? 8);
    _set(`carb_tier_l2_${i}`,  t.l2 || '');
    _setSelect(`carb_tier_c1_${i}`, t.c1 || 'OK');
    _setSelect(`carb_tier_c2_${i}`, t.c2 || 'OK');
  }
  // Aplicar colores a todos los selects
  document.querySelectorAll('[id^="carb_lt_c"],[id^="carb_lb_c"],[id^="carb_tier_c"]').forEach(colorCriterio);
  _calcularTotales();
}

function _poblarTension() {
  for (let i = 1; i <= 8; i++) {
    const tt = carbonesData.tension.ladoTapa[i-1]   || {};
    const tb = carbonesData.tension.ladoBobina[i-1] || {};
    _set(`carb_tt_t1_${i}`, tt.t1||''); _set(`carb_tt_t2_${i}`, tt.t2||'');
    _set(`carb_tb_t1_${i}`, tb.t1||''); _set(`carb_tb_t2_${i}`, tb.t2||'');
  }
  for (let i = 1; i <= 2; i++) {
    const tt = carbonesData.tension.tierra[i-1] || {};
    _set(`carb_ttier_t1_${i}`, tt.t1||''); _set(`carb_ttier_t2_${i}`, tt.t2||'');
  }
}

function _set(id, val) {
  const el = document.getElementById(id);
  if (el) el.value = val;
}
function _setSelect(id, val) {
  const el = document.getElementById(id);
  if (el) { el.value = val; colorCriterio(el); }
}

// ---- Guardar / Cargar ----

function guardarCarbones() {
  _recogerLargo();
  _recogerTension();

  if (!carbonesData.numProtocolo) {
    alert('Ingresa el N° de protocolo antes de guardar');
    mostrar('carbonesDatos');
    return;
  }

  // Actualizar lista de protocolos guardados
  let lista = JSON.parse(localStorage.getItem('carbonesAYCA_lista') || '[]');
  const idx = lista.findIndex(p => p.numProtocolo === carbonesData.numProtocolo);
  const resumen = {
    numProtocolo: carbonesData.numProtocolo,
    cliente:      carbonesData.cliente,
    faena:        carbonesData.faena,
    area:         carbonesData.area,
    equipo:       carbonesData.equipo,
    evento:       carbonesData.evento,
    fecha:        carbonesData.fecha,
    tecnico:      carbonesData.tecnico
  };
  if (idx >= 0) lista[idx] = resumen;
  else lista.unshift(resumen);
  localStorage.setItem('carbonesAYCA_lista', JSON.stringify(lista));

  // Guardar datos completos
  localStorage.setItem(`carbones_${carbonesData.numProtocolo}`, JSON.stringify(carbonesData));

  // Encolar para sincronización con nube
  if (typeof encolarSync === 'function') {
    encolarSync('carbones', carbonesData.numProtocolo);
    if (navigator.onLine && typeof sincronizarTodo === 'function') sincronizarTodo();
  }

  alert(`✅ Protocolo ${carbonesData.numProtocolo} guardado${navigator.onLine ? ' y enviado a la nube' : ' en el dispositivo (se sincronizará al recuperar conexión)'}`);
  mostrar('panel');
}

function retomarCarbones(numProtocolo) {
  const raw = localStorage.getItem(`carbones_${numProtocolo}`);
  if (!raw) { alert('Protocolo no encontrado'); return; }
  carbonesData = JSON.parse(raw);

  _set('carb_numProtocolo', carbonesData.numProtocolo);
  document.getElementById('carb_cliente').value = carbonesData.cliente || 'CODELCO';
  const cfaena = document.getElementById('carb_faena'); if (cfaena) cfaena.value = carbonesData.faena || 'Andina';
  const carea  = document.getElementById('carb_area');  if (carea)  carea.value  = carbonesData.area  || 'Molienda';
  _set('carb_equipo',        carbonesData.equipo        || '');
  _set('carb_evento',        carbonesData.evento        || '');
  _set('carb_fecha',         carbonesData.fecha         || '');
  _set('carb_tecnico',       carbonesData.tecnico       || '');
  _set('carb_observaciones', carbonesData.observaciones || '');
  _seleccionarNumCarbones(carbonesData.numCarbones || 6);

  mostrar('carbonesLargo');
  _actualizarFilas();
  _poblarLargo();
}

function guardarAvanceCarbones() {
  _recogerDatosCarb();
  _recogerLargo();
  _recogerTension();
  const num = carbonesData.numProtocolo;
  if (!num) { alert('Ingresa el N° de protocolo antes de guardar'); return; }
  let lista = JSON.parse(localStorage.getItem('carbonesAYCA_lista') || '[]');
  const resumen = { numProtocolo: num, cliente: carbonesData.cliente, faena: carbonesData.faena,
                    equipo: carbonesData.equipo, fecha: carbonesData.fecha, tecnico: carbonesData.tecnico };
  const idx = lista.findIndex(p => p.numProtocolo === num);
  if (idx >= 0) lista[idx] = resumen; else lista.unshift(resumen);
  localStorage.setItem('carbonesAYCA_lista', JSON.stringify(lista));
  localStorage.setItem(`carbones_${num}`, JSON.stringify(carbonesData));
  if (typeof encolarSync === 'function') encolarSync('carbones', num);
  alert('✅ Avance guardado');
}

function mostrarListaCarbones() {
  const cont = document.getElementById('carb_listaGuardados');
  if (!cont) return;
  const lista = JSON.parse(localStorage.getItem('carbonesAYCA_lista') || '[]');
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
      <button onclick="retomarCarbones('${p.numProtocolo}')" style="margin:0;padding:8px 10px;font-size:12px;white-space:nowrap">📂 Retomar</button>
    </div>
  `).join('');
}

// ---- PDF ----

function generarPDFCarbones() {
  _recogerLargo();
  _recogerTension();
  if (!window.jspdf) { alert("jsPDF no está cargado."); return; }

  const { jsPDF } = window.jspdf;
  const doc = new jsPDF("p","mm","a4");

  const BK  = [0,0,0];
  const BL  = [255,255,255];
  const gH  = [180,180,180];
  const gSH = [220,220,220];
  const n   = carbonesData.numCarbones;

  const fmt = v => { const x=parseFloat(v); return isNaN(x)?'':x.toFixed(1).replace('.',','); };
  const cvT = v => { const x=parseFloat(v); return isNaN(x)?'':(x/AREA_CONTACTO_RESORTE_CM2).toFixed(2).replace('.',','); };

  const tblBase = {
    theme:"grid",
    styles:{fillColor:BL,textColor:BK,lineColor:BK,lineWidth:0.3,cellPadding:2,fontSize:8,halign:'center'}
  };

  // ── Encabezado de página ──
  const addHeader = () => {
    doc.setFont("helvetica","bold"); doc.setFontSize(20); doc.setTextColor(0,0,0);
    doc.text("AyCA", 14, 14);
    doc.setFont("helvetica","normal"); doc.setFontSize(8.5);
    doc.text("Accionamiento y Control Automático", 14, 20);
    doc.setLineWidth(0.3); doc.setDrawColor(0,0,0);
    doc.rect(130, 8, 66, 7.5);
    doc.rect(130,15.5,66, 7.5);
    doc.rect(130, 23, 66, 7.5);
    doc.setFontSize(7.5); doc.setFont("helvetica","normal");
    doc.text("Código: PT-1002",            163, 13,   {align:"center"});
    doc.text("Revisión: 1",                163, 20.5, {align:"center"});
    doc.text("Anexo B: Protocolo de carbones", 163, 28, {align:"center"});
    doc.setLineWidth(0.5); doc.line(14, 32, 196, 32);
  };

  // ── Pie de página ──
  const addFooter = () => {
    const total = doc.getNumberOfPages();
    const pie = "Servicios en Accionamiento y Control Automático SpA. RUT 76.845.043-9  Av. Pdte. Kennedy Lateral 7900, Oficina 502, Vitacura, Santiago, Chile. Teléfono +569 23266267";
    for(let p=1;p<=total;p++){
      doc.setPage(p);
      doc.setFont("helvetica","normal"); doc.setFontSize(6.5); doc.setTextColor(100,100,100);
      doc.text(pie, 105, 290, {align:"center", maxWidth:182});
    }
  };

  // ── Cálculo de totales ──
  let remp=0, ajus=0;
  for(let i=1;i<=n;i++){
    ['lt_c1','lt_c2','lb_c1','lb_c2'].forEach(k=>{
      const v=document.getElementById(`carb_${k}_${i}`)?.value;
      if(v==='BM'||v==='D') remp++;
    });
    ['lt','lb'].forEach(side=>{
      const alt=parseFloat(document.getElementById(`carb_${side}_alt_${i}`)?.value);
      if(!isNaN(alt)&&alt<8) ajus++;
    });
  }
  for(let i=1;i<=2;i++){
    const vc1=document.getElementById(`carb_tier_c1_${i}`)?.value;
    const vc2=document.getElementById(`carb_tier_c2_${i}`)?.value;
    if(vc1==='BM'||vc1==='D') remp++;
    if(vc2==='BM'||vc2==='D') remp++;
    const alt=parseFloat(document.getElementById(`carb_tier_alt_${i}`)?.value);
    if(!isNaN(alt)&&alt<8) ajus++;
  }

  // ═══════════════ PÁGINA 1 ═══════════════
  addHeader();
  let y = 36;

  // Título
  doc.setFont("helvetica","bold"); doc.setFontSize(14); doc.setTextColor(0,0,0);
  doc.text("1.   Protocolo de carbones", 14, y); y+=7;
  doc.setFontSize(11);
  doc.text("1.1.   Medición de largo de carbones", 14, y); y+=5;

  // Tabla resumen (cols suman 182mm: 64+16+74+28=182)
  doc.autoTable({...tblBase, startY:y,
    body:[
      [{content:"Total carbones remplazados",    styles:{fontStyle:"bold",halign:'left'}},
       {content:String(remp)},
       {content:"Medida cambio de carbón [mm]",  styles:{fontStyle:"bold",halign:'left'}},
       {content:"40"}],
      [{content:"Total porta carbones ajustados", styles:{fontStyle:"bold",halign:'left'}},
       {content:String(ajus)},
       {content:"Altura nominal [mm]",           styles:{fontStyle:"bold",halign:'left'}},
       {content:"8"}]
    ],
    columnStyles:{0:{cellWidth:64,halign:'left'},1:{cellWidth:16},2:{cellWidth:74,halign:'left'},3:{cellWidth:28}},
    margin:{left:14,right:14}
  });
  y = doc.lastAutoTable.finalY + 2;

  // Tabla criterios — dos tablas lado a lado (cada una 86mm: margin left:14/right:110 y left:110/right:14)
  const critY = y;
  doc.autoTable({...tblBase, startY:critY,
    head:[[{content:"Criterios de cambio",colSpan:2,styles:{fontStyle:"bold",halign:'center',fillColor:gSH,textColor:BK}}]],
    body:[["Bajo Medida","BM"],["Preventivo","P"]],
    columnStyles:{0:{cellWidth:66,halign:'left'},1:{cellWidth:20}},
    margin:{left:14,right:110}
  });
  const yCrit1 = doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase, startY:critY,
    head:[[{content:"Criterios de cambio",colSpan:2,styles:{fontStyle:"bold",halign:'center',fillColor:gSH,textColor:BK}}]],
    body:[["Defectuoso","D"],["En buen estado","OK"]],
    columnStyles:{0:{cellWidth:66,halign:'left'},1:{cellWidth:20}},
    margin:{left:110,right:14}
  });
  y = Math.max(yCrit1, doc.lastAutoTable.finalY) + 3;

  // Tablas de largo — tres lado a lado (cada una 58mm: N°8+L1 17+Alt 16+L2 17=58)
  const lHead = title => [
    [{content:title,colSpan:4,styles:{fillColor:gH,halign:'center',fontStyle:'bold',fontSize:8,textColor:BK}}],
    ['N°','Largo\n[mm]','Altura\n[mm]','Largo\n[mm]'].map(t=>
      ({content:t,styles:{fillColor:gSH,halign:'center',fontStyle:'bold',fontSize:7,textColor:BK}}))
  ];

  const lBody = (arr) => {
    const rows=[];
    for(let i=0;i<8;i++){
      const o=arr[i]||{};
      const vis=i<n;
      const fv1=vis?fmt(o.l1):'';
      const fv2=vis?fmt(o.l2):'';
      const v1=fv1?(fv1+(o.c1?'\n'+o.c1:'')):fv1;
      const v2=fv2?(fv2+(o.c2?'\n'+o.c2:'')):fv2;
      rows.push([String(i+1), v1, vis?fmt(o.alt):'', v2]);
    }
    return rows;
  };

  const lTierraBody = () => {
    const rows=[];
    for(let i=0;i<2;i++){
      const o=carbonesData.largo.tierra[i]||{};
      const fv1=fmt(o.l1); const fv2=fmt(o.l2);
      const v1=fv1?(fv1+(o.c1?'\n'+o.c1:'')):fv1;
      const v2=fv2?(fv2+(o.c2?'\n'+o.c2:'')):fv2;
      rows.push([String(i+1), v1, fmt(o.alt), v2]);
    }
    return rows;
  };

  const lCols={0:{cellWidth:8},1:{cellWidth:17},2:{cellWidth:16},3:{cellWidth:17}};
  const sYL=y;
  doc.autoTable({...tblBase,startY:sYL,head:lHead('Lado Tapa'),  body:lBody(carbonesData.largo.ladoTapa),  columnStyles:lCols,margin:{left:14, right:138}});
  const yL1=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase,startY:sYL,head:lHead('Tierra'),     body:lTierraBody(),                       columnStyles:lCols,margin:{left:76, right:76}});
  const yL2=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase,startY:sYL,head:lHead('Lado Bobina'),body:lBody(carbonesData.largo.ladoBobina),columnStyles:lCols,margin:{left:138,right:14}});
  y = Math.max(yL1,yL2,doc.lastAutoTable.finalY) + 5;

  // Observaciones (página 1)
  const obs = carbonesData.observaciones || '';
  if(obs.trim()){
    doc.setFont("helvetica","bold"); doc.setFontSize(9); doc.setTextColor(0,0,0);
    doc.text("Observaciones:", 14, y);
    doc.setFont("helvetica","normal"); doc.setFontSize(8);
    const obsLines = doc.splitTextToSize(obs, 182);
    doc.text(obsLines, 14, y+5);
  }

  // ═══════════════ PÁGINA 2 ═══════════════
  doc.addPage();
  addHeader();
  y = 36;

  doc.setFont("helvetica","bold"); doc.setFontSize(11); doc.setTextColor(0,0,0);
  doc.text("1.2.   Medición de tensión de resortes de porta carbones", 14, y); y+=6;

  // Tablas de tensión en N
  const tHeadN = title => [
    [{content:title,colSpan:3,styles:{fillColor:gH,halign:'center',fontStyle:'bold',fontSize:8,textColor:BK}}],
    ['N°','Tensión [N]','Tensión [N]'].map(t=>
      ({content:t,styles:{fillColor:gSH,halign:'center',fontStyle:'bold',fontSize:7,textColor:BK}}))
  ];
  const tBodyN = (arr) => {
    const rows=[];
    for(let i=0;i<8;i++){
      const o=arr[i]||{}; const vis=i<n;
      rows.push([String(i+1), vis?fmt(o.t1):'', vis?fmt(o.t2):'']);
    }
    return rows;
  };
  const tTierraN = () => {
    const rows=[];
    for(let i=0;i<2;i++){
      const o=carbonesData.tension.tierra[i]||{};
      rows.push([String(i+1), fmt(o.t1), fmt(o.t2)]);
    }
    return rows;
  };
  const tCols={0:{cellWidth:8},1:{cellWidth:25},2:{cellWidth:25}};
  const sYN=y;
  doc.autoTable({...tblBase,startY:sYN,head:tHeadN('Lado Tapa'),  body:tBodyN(carbonesData.tension.ladoTapa),  columnStyles:tCols,margin:{left:14, right:138}});
  const yN1=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase,startY:sYN,head:tHeadN('Tierra'),     body:tTierraN(),                             columnStyles:tCols,margin:{left:76, right:76}});
  const yN2=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase,startY:sYN,head:tHeadN('Lado Bobina'),body:tBodyN(carbonesData.tension.ladoBobina),columnStyles:tCols,margin:{left:138,right:14}});
  y = Math.max(yN1,yN2,doc.lastAutoTable.finalY) + 5;

  // Tabla info escobilla (cols suman 182mm: 40+22+40+22+40+18=182)
  doc.autoTable({...tblBase, startY:y,
    body:[[
      {content:"Ancho escobilla",         styles:{fontStyle:"bold",halign:'center',fillColor:gSH,textColor:BK}},
      {content:"16 [mm]"},
      {content:"Largo escobilla",         styles:{fontStyle:"bold",halign:'center',fillColor:gSH,textColor:BK}},
      {content:"25 [mm]"},
      {content:"Área contacto escobilla", styles:{fontStyle:"bold",halign:'center',fillColor:gSH,textColor:BK}},
      {content:"4,00 [cm²]"}
    ]],
    columnStyles:{0:{cellWidth:40},1:{cellWidth:22},2:{cellWidth:40},3:{cellWidth:22},4:{cellWidth:40},5:{cellWidth:18}},
    margin:{left:14,right:14}
  });
  y = doc.lastAutoTable.finalY + 5;

  // Tablas de tensión en N/cm²
  const tHeadC = title => [
    [{content:title,colSpan:3,styles:{fillColor:gH,halign:'center',fontStyle:'bold',fontSize:8,textColor:BK}}],
    ['N°','Tensión [N/cm²]','Tensión [N/cm²]'].map(t=>
      ({content:t,styles:{fillColor:gSH,halign:'center',fontStyle:'bold',fontSize:7,textColor:BK}}))
  ];
  const tBodyC = (arr) => {
    const rows=[];
    for(let i=0;i<8;i++){
      const o=arr[i]||{}; const vis=i<n;
      rows.push([String(i+1), vis?cvT(o.t1):'', vis?cvT(o.t2):'']);
    }
    return rows;
  };
  const tTierraC = () => {
    const rows=[];
    for(let i=0;i<2;i++){
      const o=carbonesData.tension.tierra[i]||{};
      rows.push([String(i+1), cvT(o.t1), cvT(o.t2)]);
    }
    return rows;
  };
  const sYC=y;
  doc.autoTable({...tblBase,startY:sYC,head:tHeadC('Lado Tapa'),  body:tBodyC(carbonesData.tension.ladoTapa),  columnStyles:tCols,margin:{left:14, right:138}});
  const yC1=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase,startY:sYC,head:tHeadC('Tierra'),     body:tTierraC(),                             columnStyles:tCols,margin:{left:76, right:76}});
  const yC2=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase,startY:sYC,head:tHeadC('Lado Bobina'),body:tBodyC(carbonesData.tension.ladoBobina),columnStyles:tCols,margin:{left:138,right:14}});
  y = Math.max(yC1,yC2,doc.lastAutoTable.finalY) + 6;

  // Observación técnica fija
  doc.setFont("helvetica","bold"); doc.setFontSize(9); doc.setTextColor(0,0,0);
  doc.text("Observaciones:", 14, y);
  doc.setFont("helvetica","normal"); doc.setFontSize(8);
  const obsT = "Los valores óptimos de utilización de los resortes con respecto a la tensión de los resortes, tienen un intervalo de tolerancia de [2 N/cm²; 4 N/cm²]. Cuando el valor es inferior al límite izquierdo se recomienda reemplazar por uno nuevo. Cuando el valor es superior al límite derecho representa un mayor desgaste de escobillas. Los valores obtenidos mediante el dinamómetro se encuentran dentro del intervalo de la tolerancia recomendada.";
  const obsTL = doc.splitTextToSize(obsT, 182);
  doc.text(obsTL, 14, y+5);

  addFooter();
  doc.save(`${carbonesData.numProtocolo||'CB'}_InformeFinal.pdf`);
}

// ---- Protocolo de Entrega (formato oficial AyCA) ----

function generarEntregaCarbones() {
  _recogerLargo();
  _recogerTension();
  if (!window.jspdf) { alert("jsPDF no está cargado."); return; }

  const { jsPDF } = window.jspdf;
  const doc = new jsPDF("p","mm","a4");
  const n   = carbonesData.numCarbones;

  const BL  = [255,255,255];
  const BK  = [0,0,0];
  const gH  = [220,220,220]; // gris título de grupo (Lado Tapa / Tierra / Lado Bobina)
  const gSH = [240,240,240]; // gris sub-encabezado (N°, Largo [mm], ...)
  const fmt = v => { const f=parseFloat(v); return isNaN(f)?(v||''):String(f).replace('.',','); };

  const tblBase = {
    theme:'grid',
    styles:{fontSize:7, halign:'center', cellPadding:1.5,
            fillColor:BL, textColor:BK, lineColor:BK, lineWidth:0.3}
  };

  // ══ ENCABEZADO ══
  doc.setFont("helvetica","bold"); doc.setFontSize(22); doc.setTextColor(0,0,0);
  doc.text("AyCA", 14, 14);
  doc.setFont("helvetica","normal"); doc.setFontSize(9); doc.setTextColor(0,0,0);
  doc.text("Accionamiento y Control Automático", 14, 21);
  doc.setDrawColor(0,0,0); doc.setLineWidth(0.5);
  doc.rect(148, 5, 48, 16);
  doc.line(148, 13, 196, 13);
  doc.setFont("helvetica","normal"); doc.setFontSize(9);
  doc.text("Codigo: PT-1002", 172, 10, {align:"center"});
  doc.text("Revisión: 1",     172, 18, {align:"center"});
  doc.setLineWidth(0.8);
  doc.line(14, 25, 196, 25);

  let y = 31;

  // ══ DATOS GENERALES ══
  const d = carbonesData;
  doc.setFontSize(9.5);
  [
    ["N° Protocolo:", d.numProtocolo||"", "Fecha:",   d.fecha||""],
    ["Cliente:",      d.cliente||"",      "Faena:",   d.faena||""],
    ["Equipo:",       d.equipo||"",       "Técnico:", d.tecnico||""],
    ["Área:",         d.area||"",         "Evento:",  d.evento||""]
  ].forEach(([l1,v1,l2,v2]) => {
    doc.setFont("helvetica","bold");   doc.setTextColor(0,0,0); doc.text(l1,  14, y);
    doc.setFont("helvetica","normal"); doc.setTextColor(0,0,0); doc.text(v1,  46, y);
    doc.setFont("helvetica","bold");   doc.setTextColor(0,0,0); doc.text(l2, 114, y);
    doc.setFont("helvetica","normal"); doc.setTextColor(0,0,0); doc.text(v2, 138, y);
    y += 5.5;
  });
  doc.setLineWidth(0.4); doc.line(14, y, 196, y); y += 6;

  // ══ TÍTULO ══
  doc.setFont("helvetica","bold"); doc.setFontSize(15); doc.setTextColor(0,0,0);
  doc.text("1   PROTOCOLO DE CARBONES", 14, y); y += 8;

  // ── 1.1 ──
  doc.setFont("helvetica","bold"); doc.setFontSize(11);
  doc.text("1.1   Medición de largo de carbones", 14, y); y += 5;

  // Resumen — BM o D = reemplazado; Alt < 8 = ajustado
  // Lectura directa del DOM (igual que _calcularTotales)
  let remp=0, ajus=0;
  for(let i=1;i<=n;i++){
    ['lt_c1','lt_c2','lb_c1','lb_c2'].forEach(k=>{
      const v=document.getElementById(`carb_${k}_${i}`)?.value;
      if(v==='BM'||v==='D') remp++;
    });
    ['lt','lb'].forEach(side=>{
      const alt=parseFloat(document.getElementById(`carb_${side}_alt_${i}`)?.value);
      if(!isNaN(alt)&&alt<8) ajus++;
    });
  }
  for(let i=1;i<=2;i++){
    const vc1=document.getElementById(`carb_tier_c1_${i}`)?.value;
    const vc2=document.getElementById(`carb_tier_c2_${i}`)?.value;
    if(vc1==='BM'||vc1==='D') remp++;
    if(vc2==='BM'||vc2==='D') remp++;
    const alt=parseFloat(document.getElementById(`carb_tier_alt_${i}`)?.value);
    if(!isNaN(alt)&&alt<8) ajus++;
  }
  doc.autoTable({
    startY:y,
    body:[
      [{content:"Total carbones reemplazados",  styles:{fontStyle:"bold",halign:'left',fontSize:8}},
       {content:String(remp),styles:{halign:'center',fontSize:8}},
       {content:"Medida para cambio de carbón [mm]",  styles:{fontStyle:"bold",halign:'left',fontSize:8}},
       {content:"40",styles:{halign:'center',fontSize:8}}],
      [{content:"Total porta carbones ajustados",styles:{fontStyle:"bold",halign:'left',fontSize:8}},
       {content:String(ajus),styles:{halign:'center',fontSize:8}},
       {content:"Medida para ajuste de porta carbón [mm]",styles:{fontStyle:"bold",halign:'left',fontSize:8}},
       {content:"8",styles:{halign:'center',fontSize:8}}]
    ],
    theme:"grid",
    styles:{fillColor:BL,textColor:BK,lineColor:BK,lineWidth:0.3,cellPadding:2},
    columnStyles:{0:{cellWidth:60,halign:'left'},1:{cellWidth:18},2:{cellWidth:78,halign:'left'},3:{cellWidth:26}},
    margin:{left:14,right:14}
  });
  y = doc.lastAutoTable.finalY + 3;

  // ── Tres tablas largo lado a lado ──
  // Página A4=210mm, 3 tablas de 58mm c/u + 2 gaps de 4mm = 182mm usable ✓
  // Tabla izq: margin {left:14, right:138}
  // Tabla cen: margin {left:76, right:76}
  // Tabla der: margin {left:138, right:14}
  // Columnas largo: N°(8)+L1(17)+Alt(16)+L2(17)=58mm

  const lHead = title => [
    [{content:title, colSpan:4,
      styles:{fillColor:gH,halign:'center',fontStyle:'bold',fontSize:8,textColor:BK}}],
    ['N°','Largo\n[mm]','Altura\n[mm]','Largo\n[mm]'].map(t=>
      ({content:t, styles:{fillColor:gSH,halign:'center',fontStyle:'bold',fontSize:7,textColor:BK}}))
  ];

  const lBody = (arr) => {
    const rows=[];
    for(let i=0;i<8;i++){
      const o=arr[i]||{};
      const vis=i<n;
      const fv1=vis?fmt(o.l1):'';
      const fv2=vis?fmt(o.l2):'';
      const v1=fv1?(fv1+(o.c1?' '+o.c1:'')):fv1;
      const v2=fv2?(fv2+(o.c2?' '+o.c2:'')):fv2;
      rows.push([String(i+1), v1, vis?fmt(o.alt):'', v2]);
    }
    return rows;
  };

  const lTierraBody = () => {
    const rows=[];
    for(let i=0;i<2;i++){
      const o = carbonesData.largo.tierra[i] || {};
      const fv1=fmt(o.l1);
      const fv2=fmt(o.l2);
      const v1=fv1?(fv1+(o.c1?' '+o.c1:'')):fv1;
      const v2=fv2?(fv2+(o.c2?' '+o.c2:'')):fv2;
      rows.push([String(i+1), v1, fmt(o.alt), v2]);
    }
    return rows;
  };

  const lCols = {0:{cellWidth:8},1:{cellWidth:17},2:{cellWidth:16},3:{cellWidth:17}};
  const sYL = y;

  doc.autoTable({...tblBase, startY:sYL, head:lHead('Lado Tapa'),   body:lBody(carbonesData.largo.ladoTapa),   columnStyles:lCols, margin:{left:14,  right:138}});
  const yL1=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase, startY:sYL, head:lHead('Tierra'),      body:lTierraBody(),                        columnStyles:lCols, margin:{left:76,  right:76}});
  const yL2=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase, startY:sYL, head:lHead('Lado Bobina'), body:lBody(carbonesData.largo.ladoBobina), columnStyles:lCols, margin:{left:138, right:14}});
  const yL3=doc.lastAutoTable.finalY;
  y = Math.max(yL1,yL2,yL3) + 5;
  if(y>232){doc.addPage();y=15;}

  // ── 1.2 ──
  doc.setFont("helvetica","bold"); doc.setFontSize(11); doc.setTextColor(0,0,0);
  doc.text("1.2   Medición de tensión de resortes de porta carbones", 14, y); y += 5;

  // ── Tres tablas tensión lado a lado ──
  // Columnas tensión: N°(8)+T1(25)+T2(25)=58mm

  const tHead = title => [
    [{content:title, colSpan:3,
      styles:{fillColor:gH,halign:'center',fontStyle:'bold',fontSize:8,textColor:BK}}],
    ['N°','Tensión [N/cm²]','Tensión [N/cm²]'].map(t=>
      ({content:t, styles:{fillColor:gSH,halign:'center',fontStyle:'bold',fontSize:7,textColor:BK}}))
  ];

  const cvT = v => { const x=parseFloat(v); return isNaN(x)?'':(x/AREA_CONTACTO_RESORTE_CM2).toFixed(2).replace('.',','); };

  const tBody = (arr) => {
    const rows=[];
    for(let i=0;i<8;i++){
      const o=arr[i]||{};
      const vis=i<n;
      rows.push([String(i+1), vis?cvT(o.t1):'', vis?cvT(o.t2):'']);
    }
    return rows;
  };

  const tTierraBody = () => {
    const ta=carbonesData.tension.tierra;
    const rows=[];
    for(let i=0;i<2;i++){
      const o=ta[i]||{};
      rows.push([String(i+1), cvT(o.t1), cvT(o.t2)]);
    }
    return rows;
  };

  const tCols={0:{cellWidth:8},1:{cellWidth:25},2:{cellWidth:25}};
  const sYT=y;

  doc.autoTable({...tblBase, startY:sYT, head:tHead('Lado Tapa'),   body:tBody(carbonesData.tension.ladoTapa),   columnStyles:tCols, margin:{left:14,  right:138}});
  const yT1=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase, startY:sYT, head:tHead('Tierra'),      body:tTierraBody(),                          columnStyles:tCols, margin:{left:76,  right:76}});
  const yT2=doc.lastAutoTable.finalY;
  doc.autoTable({...tblBase, startY:sYT, head:tHead('Lado Bobina'), body:tBody(carbonesData.tension.ladoBobina), columnStyles:tCols, margin:{left:138, right:14}});
  const yT3=doc.lastAutoTable.finalY;
  y = Math.max(yT1,yT2,yT3) + 5;

  // ══ OBSERVACIONES ══
  // obsH se ajusta dinámicamente para que firmas siempre queden en página 1
  doc.setFont("helvetica","bold"); doc.setFontSize(9.5); doc.setTextColor(0,0,0);
  doc.text("Observaciones:", 14, y); y += 4;
  const obsH = Math.max(3, Math.min(15, 260-y));
  doc.setDrawColor(0,0,0); doc.setLineWidth(0.4);
  doc.rect(14,y,182,obsH);
  const obs=carbonesData.observaciones||"";
  if(obs){
    doc.setFont("helvetica","normal"); doc.setFontSize(8);
    doc.text(doc.splitTextToSize(obs,178), 16, y+4);
  }
  y += obsH + 5;

  // ══ FIRMAS — siempre en página 1 ══
  doc.setDrawColor(0,0,0); doc.setLineWidth(0.4);
  doc.line(14,y,90,y);
  doc.line(118,y,196,y);
  doc.setFont("helvetica","normal"); doc.setFontSize(9); doc.setTextColor(0,0,0);
  doc.text("Técnico Responsable:",  14, y+5);
  doc.text("Nombre y Firma Cliente:", 118, y+5);

  // ══ PIE DE PÁGINA ══
  const total=doc.getNumberOfPages();
  for(let p=1;p<=total;p++){
    doc.setPage(p);
    doc.setDrawColor(0,0,0); doc.setLineWidth(0.5);
    doc.line(14,281,196,281);
    doc.setFont("helvetica","normal"); doc.setFontSize(6.5); doc.setTextColor(80,80,80);
    doc.text(
      "Servicios en Accionamiento y Control Automático SpA.  RUT 76.845.043-9  Av. Pdte. Kennedy Lateral 7900, Oficina 502, Vitacura, Santiago, Chile.  Teléfono +569 23266267",
      14,286,{maxWidth:170}
    );
    doc.text(String(p),196,289,{align:"right"});
    doc.setTextColor(0,0,0);
  }

  doc.save(`${carbonesData.numProtocolo||'CB'}_Protocolo_Entrega.pdf`);
}
