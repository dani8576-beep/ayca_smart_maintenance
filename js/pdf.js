function generarPDF() {
  try {
    if (!window.jspdf) {
      alert("Error: jsPDF no está cargado.");
      return;
    }

    guardarDatosPosicion();

    const { jsPDF } = window.jspdf;
    const doc = new jsPDF("p", "mm", "a4");

    const protocolo = document.getElementById("protocolo").value || "SIN_PROTOCOLO";
    const fecha = document.getElementById("fecha").value || "";
    const cliente = document.getElementById("cliente").value || "";
    const faena = document.getElementById("faena").value || "";
    const area = document.getElementById("area").value || "";
    const tecnico = document.getElementById("usuario").value || "";
    const azul = [11, 49, 88];

    doc.setFillColor(...azul);
    doc.rect(0, 0, 210, 28, "F");

    doc.setTextColor(255, 255, 255);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(17);
    doc.text("AYCA SMART MAINTENANCE", 105, 11, { align: "center" });

    doc.setFontSize(10);
    doc.text("ACCIONAMIENTO Y CONTROL AUTOMÁTICO", 105, 18, { align: "center" });

    doc.setFontSize(13);
    doc.text("PROTOCOLO DE CONTROL DIMENSIONAL", 105, 25, { align: "center" });

    doc.setTextColor(0, 0, 0);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(12);
    doc.text("Datos Generales", 14, 42);

    doc.autoTable({
      startY: 47,
      body: [
        ["N° Protocolo", protocolo, "Fecha", fecha],
        ["Cliente", cliente, "Faena", faena],
        ["Área", area, "Técnico", tecnico]
      ],
      theme: "grid",
      styles: { fontSize: 9 },
      columnStyles: {
        0: { fontStyle: "bold", fillColor: [235, 240, 245] },
        2: { fontStyle: "bold", fillColor: [235, 240, 245] }
      }
    });

    let y = doc.lastAutoTable.finalY + 10;

    ["0°", "90°", "180°", "270°"].forEach(pos => {
      const datos = datosPosiciones[pos];
      if (!datos) return;

      if (y > 230) {
        doc.addPage();
        y = 20;
      }

      doc.setFillColor(...azul);
      doc.rect(14, y, 182, 8, "F");

      doc.setTextColor(255, 255, 255);
      doc.setFont("helvetica", "bold");
      doc.setFontSize(11);
      doc.text("Posición " + pos, 16, y + 5.5);

      y += 14;
      doc.setTextColor(0, 0, 0);

      doc.autoTable({
        startY: y,
        body: [
          ["Estado sensor", limpiarEstadoPDF(datos.estadoSensor)],
          ["Estado cableado", limpiarEstadoPDF(datos.estadoCableado)],
          ["Observaciones", datos.observacionesSensor || "Sin observaciones"]
        ],
        theme: "grid",
        styles: { fontSize: 9 },
        columnStyles: {
          0: { fontStyle: "bold", fillColor: [235, 240, 245], cellWidth: 45 },
          1: { cellWidth: 137 }
        }
      });

      y = doc.lastAutoTable.finalY + 7;

      y = agregarTablaPDF(doc, "Entrehierro", datos.entrehierro || [], y, azul);
      y += 8;

      y = agregarTablaPDF(doc, "Centro Magnético", datos.centroMagnetico || [], y, azul);
      y += 12;
    });

    const canvasGrafico = document.getElementById("graficoExcentricidad");
    if (canvasGrafico) {
      if (typeof dibujarGraficoExcentricidad === "function") {
        dibujarGraficoExcentricidad();
      }
      const imagenGrafico = canvasGrafico.toDataURL("image/png");
      if (y > 150) {
        doc.addPage();
        y = 20;
      }
      doc.setFont("helvetica", "bold");
      doc.setFontSize(12);
      doc.setTextColor(0, 0, 0);
      doc.text("Gráfico de Excentricidad", 14, y);
      doc.addImage(imagenGrafico, "PNG", 45, y + 8, 120, 120);
      y += 140;
    }

    if (y > 230) {
      doc.addPage();
      y = 30;
    }

    doc.setFont("helvetica", "bold");
    doc.setFontSize(12);
    doc.text("Firmas", 14, y);

    doc.setFont("helvetica", "normal");
    doc.line(14, y + 22, 85, y + 22);
    doc.text("Firma Técnico AYCA", 14, y + 28);

    doc.line(115, y + 22, 190, y + 22);
    doc.text("Firma Supervisor / Cliente", 115, y + 28);

    const totalPaginas = doc.internal.getNumberOfPages();

    for (let i = 1; i <= totalPaginas; i++) {
      doc.setPage(i);
      doc.setFontSize(8);
      doc.setTextColor(120);
      doc.text(`Página ${i} de ${totalPaginas}`, 180, 290);
      doc.text("AYCA Smart Maintenance", 14, 290);
    }

    const protocoloCompleto = {
      numero: protocolo,
      fecha,
      cliente,
      faena,
      area,
      tecnico,
      posiciones: clonar(datosPosiciones)
    };

    guardarProtocoloLocal(protocoloCompleto);

    if (typeof guardarProtocoloNube === "function") {
      guardarProtocoloNube(protocoloCompleto);
    }

    doc.save(protocolo + "_control_dimensional.pdf");

  } catch (error) {
    alert("Error al generar PDF: " + error.message);
    console.error(error);
  }
}

function agregarTablaPDF(doc, titulo, datos, y, azul) {
  const filas = datos.filter(f => f.polo || f.alimentacion || f.descarga);

  doc.setFont("helvetica", "bold");
  doc.setFontSize(10);
  doc.text(titulo, 14, y);

  doc.autoTable({
    startY: y + 3,
    head: [["N° Polo", "Alimentación", "Descarga", "Promedio"]],
    body: filas.length
      ? filas.map(f => [f.polo, f.alimentacion, f.descarga, f.promedio])
      : [["Sin registros", "", "", ""]],
    theme: "grid",
    styles: { fontSize: 8 },
    headStyles: { fillColor: azul }
  });

  return doc.lastAutoTable.finalY;
}

function limpiarEstadoPDF(valor) {
  if (!valor) return "Sin registro";
  if (valor.includes("OK")) return "OK";
  if (valor.includes("FALLA")) return "FALLA";
  if (valor.includes("N/A")) return "N/A";
  return valor;
}

function guardarProtocoloLocal(protocoloCompleto) {
  let historial = JSON.parse(localStorage.getItem("protocolosAYCA")) || [];
  const existe = historial.findIndex(p => p.numero === protocoloCompleto.numero);

  if (existe >= 0) {
    historial[existe] = protocoloCompleto;
  } else {
    historial.push(protocoloCompleto);
  }

  localStorage.setItem("protocolosAYCA", JSON.stringify(historial));
  protocolos = historial;
}

// ── PDF Medición Dieléctrica ──
function generarPDFDielectrico() {
  try {
    if (typeof guardarEst1 === "function") guardarEst1();

    if (!window.jspdf) { alert("Error: jsPDF no está cargado."); return; }
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF("p", "mm", "a4");

    const azul  = [11, 49, 88];
    const azulC = [219, 234, 254];
    const grisC = [235, 240, 245];

    const numProt = document.getElementById("numProtocoloDiel")?.value || "DL-SIN-NUMERO";
    const cliente = document.getElementById("clienteDiel")?.value  || "";
    const equipo  = document.getElementById("equipoDiel")?.value   || "";

    const pre  = (typeof datosDielEst1 !== "undefined") ? datosDielEst1.pre  : null;
    const post = (typeof datosDielEst1 !== "undefined") ? datosDielEst1.post : null;

    // ── Encabezado ──
    doc.setFillColor(...azul);
    doc.rect(0, 0, 210, 28, "F");
    doc.setTextColor(255, 255, 255);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(17);
    doc.text("AYCA SMART MAINTENANCE", 105, 11, { align: "center" });
    doc.setFontSize(10);
    doc.text("ACCIONAMIENTO Y CONTROL AUTOMÁTICO", 105, 18, { align: "center" });
    doc.setFontSize(13);
    doc.text("PROTOCOLO DE MEDICIÓN DIELÉCTRICA — ÍNDICE DE POLARIZACIÓN", 105, 25, { align: "center" });

    doc.setTextColor(0, 0, 0);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(11);
    doc.text("Datos Generales", 14, 38);

    doc.autoTable({
      startY: 42,
      body: [
        ["N° Protocolo", numProt, "Cliente", cliente],
        ["Equipo", equipo, "Estator", "1"]
      ],
      theme: "grid",
      styles: { fontSize: 9 },
      columnStyles: {
        0: { fontStyle: "bold", fillColor: grisC, cellWidth: 35 },
        2: { fontStyle: "bold", fillColor: grisC, cellWidth: 35 }
      }
    });

    let y = doc.lastAutoTable.finalY + 8;

    const TIEMPOS = ["0,50","1,00","2,00","3,00","4,00","5,00","6,00","7,00","8,00","9,00","10,00"];

    function seccionDiel(titulo, datos, colorHeader) {
      if (!datos) return;
      const tieneDatos = datos.mediciones?.some(m => m.r) || datos.if_nA || datos.cap;
      if (!tieneDatos) return;

      if (y > 205) { doc.addPage(); y = 20; }

      // Banner de sección
      doc.setFillColor(...colorHeader);
      doc.rect(14, y, 182, 8, "F");
      doc.setTextColor(255, 255, 255);
      doc.setFont("helvetica", "bold");
      doc.setFontSize(11);
      doc.text(titulo, 16, y + 5.5);
      y += 12;
      doc.setTextColor(0, 0, 0);

      // Resumen: Fecha, IP, V.Prueba, T.Bob, Kt
      doc.autoTable({
        startY: y,
        body: [[
          "Fecha: " + (datos.fecha || "—"),
          "IP: " + (datos.ip || "—"),
          "V.Prueba: " + (datos.vprueba || "—") + " V",
          "T.B.: " + (datos.temp || "—") + "°C",
          "Kt: " + (datos.kt || "—")
        ]],
        theme: "grid",
        styles: { fontSize: 8, cellPadding: 2 },
        columnStyles: {
          0: { fillColor: grisC },
          2: { fillColor: grisC }
        }
      });
      y = doc.lastAutoTable.finalY + 4;

      // Tabla de 11 mediciones
      const filasMed = (datos.mediciones || []).map((m, i) => [
        TIEMPOS[i] || String(i),
        m.r  || "—",
        m.rc || "—"
      ]);

      doc.autoTable({
        startY: y,
        head: [["t [min]", "R medido [GΩ]", "R @ 40°C [GΩ]"]],
        body: filasMed.length > 0 ? filasMed : [["Sin datos", "—", "—"]],
        theme: "grid",
        styles: { fontSize: 8, halign: "center" },
        headStyles: { fillColor: azul },
        didParseCell: function (data) {
          if (data.section === "body" && (data.row.index === 1 || data.row.index === 10)) {
            data.cell.styles.fillColor = azulC;
            data.cell.styles.fontStyle = "bold";
          }
        }
      });
      y = doc.lastAutoTable.finalY + 4;

      // Corriente de fuga y Capacitancia
      doc.autoTable({
        startY: y,
        body: [[
          "Corriente de fuga",
          (datos.if_nA || "—") + " nA",
          "Capacitancia",
          (datos.cap || "—") + " µF"
        ]],
        theme: "grid",
        styles: { fontSize: 9 },
        columnStyles: {
          0: { fontStyle: "bold", fillColor: grisC, cellWidth: 42 },
          2: { fontStyle: "bold", fillColor: grisC, cellWidth: 42 }
        }
      });
      y = doc.lastAutoTable.finalY + 4;

      // Resistencia Óhmica
      if (datos.l12 || datos.l13 || datos.l21) {
        doc.autoTable({
          startY: y,
          head: [["Resistencia Óhmica", "T. Med.: " + (datos.rohm_temp || "—") + "°C", "L1-L2 [mΩ]", "L1-L3 [mΩ]", "L2-L1 [mΩ]"]],
          body: [["", "", datos.l12 || "—", datos.l13 || "—", datos.l21 || "—"]],
          theme: "grid",
          styles: { fontSize: 8, halign: "center" },
          headStyles: { fillColor: grisC, textColor: [0, 0, 0] }
        });
        y = doc.lastAutoTable.finalY + 4;
      }

      // Observaciones
      if (datos.obs) {
        doc.setFont("helvetica", "italic");
        doc.setFontSize(8);
        doc.setTextColor(90, 90, 90);
        doc.text("Obs: " + datos.obs, 14, y);
        y += 7;
        doc.setTextColor(0, 0, 0);
      }
      y += 6;
    }

    seccionDiel("MEDICIÓN PRE MANTENIMIENTO — ESTATOR 1",  pre,  azul);
    seccionDiel("MEDICIÓN POST MANTENIMIENTO — ESTATOR 1", post, [34, 100, 50]);

    // ── Gráfico comparativo ──
    if (typeof dibujarGraficoIP === "function") dibujarGraficoIP();
    const canvasGraf = document.getElementById("graficoIP");
    if (canvasGraf) {
      if (y > 160) { doc.addPage(); y = 20; }
      doc.setFont("helvetica", "bold");
      doc.setFontSize(11);
      doc.setTextColor(0, 0, 0);
      doc.text("Gráfico Comparativo — R Aislación PRE vs POST", 105, y, { align: "center" });
      y += 5;
      doc.addImage(canvasGraf.toDataURL("image/png"), "PNG", 25, y, 160, 118);
      y += 126;
    }

    // ── Firmas ──
    if (y > 240) { doc.addPage(); y = 30; }
    doc.setFont("helvetica", "bold");
    doc.setFontSize(11);
    doc.setTextColor(0, 0, 0);
    doc.text("Firmas", 14, y);
    doc.setFont("helvetica", "normal");
    doc.line(14, y + 22, 85, y + 22);
    doc.setFontSize(9);
    doc.text("Firma Técnico AYCA", 14, y + 28);
    doc.line(115, y + 22, 190, y + 22);
    doc.text("Firma Supervisor / Cliente", 115, y + 28);

    // ── Numeración de páginas ──
    const totalPag = doc.internal.getNumberOfPages();
    for (let i = 1; i <= totalPag; i++) {
      doc.setPage(i);
      doc.setFontSize(8);
      doc.setTextColor(140);
      doc.text(`Página ${i} de ${totalPag}`, 180, 290);
      doc.text("AYCA Smart Maintenance — Protocolo Dieléctrico", 14, 290);
    }

    doc.save(numProt + "_dielectrico.pdf");

  } catch (err) {
    alert("Error al generar PDF: " + err.message);
    console.error(err);
  }

}

// ── Reporte de Entrega de Equipo ──
function generarReporteEntrega() {
  try {
    if (!window.jspdf) { alert("Error: jsPDF no está cargado."); return; }
    if (typeof guardarEst1 === "function") guardarEst1();

    if (typeof guardarEst2  === "function") guardarEst2();
    if (typeof guardarRotor === "function") guardarRotor();

    const preEst1   = (typeof datosDielEst1  !== "undefined") ? datosDielEst1.pre   : null;
    const postEst1  = (typeof datosDielEst1  !== "undefined") ? datosDielEst1.post  : null;
    const preEst2   = (typeof datosDielEst2  !== "undefined") ? datosDielEst2.pre   : null;
    const postEst2  = (typeof datosDielEst2  !== "undefined") ? datosDielEst2.post  : null;
    const preRotor  = (typeof datosDielRotor !== "undefined") ? datosDielRotor.pre  : null;
    const postRotor = (typeof datosDielRotor !== "undefined") ? datosDielRotor.post : null;

    if (!preEst1 && !postEst1 && !preEst2 && !postEst2 && !preRotor && !postRotor) {
      alert("No hay datos guardados.\nGuarda primero el PRE o POST MANTENIMIENTO.");
      return;
    }

    const { jsPDF } = window.jspdf;
    const doc     = new jsPDF("p", "mm", "a4");
    const azul    = [11, 49, 88];
    const grisC   = [235, 240, 245];
    const TIEMPOS = ["0,5","1","2","3","4","5","6","7","8","9","10"];

    const numProt = document.getElementById("numProtocoloDiel")?.value || "MD-SIN-NUMERO";
    const cliente = document.getElementById("clienteDiel")?.value     || "";
    const equipo  = document.getElementById("equipoDiel")?.value      || "";

    let esPrimeraPagina = true;

    function cabeceraHoja() {
      if (!esPrimeraPagina) doc.addPage();
      esPrimeraPagina = false;
      doc.setFillColor(...azul);
      doc.rect(0, 0, 210, 24, "F");
      doc.setTextColor(255, 255, 255);
      doc.setFont("helvetica", "bold");
      doc.setFontSize(14);
      doc.text("AYCA SMART MAINTENANCE", 105, 9, { align: "center" });
      doc.setFont("helvetica", "normal");
      doc.setFontSize(8);
      doc.text("Servicios en Accionamiento y Control Automático SpA.  RUT 76.845.043-9", 105, 15, { align: "center" });
      doc.text("Av. Pdte. Kennedy Lateral 7900, Of. 502, Vitacura, Santiago  —  Tel. +569 23266267", 105, 20.5, { align: "center" });
      doc.setTextColor(0, 0, 0);
      return 27;
    }

    function tablaEstatores(tipo, est1, est2) {
      let y = cabeceraHoja();

      // Datos generales del protocolo
      doc.autoTable({
        startY: y,
        body: [
          [
            { content: "N° Protocolo",   styles: { fontStyle: "bold", fillColor: grisC } }, numProt,
            { content: "Cliente",        styles: { fontStyle: "bold", fillColor: grisC } }, cliente
          ],
          [
            { content: "Equipo / Motor", styles: { fontStyle: "bold", fillColor: grisC } },
            { content: equipo, colSpan: 3 }
          ]
        ],
        theme: "grid",
        styles: { fontSize: 8, cellPadding: 2 },
        columnStyles: { 0: { cellWidth: 33 }, 2: { cellWidth: 26 } },
        margin: { left: 14, right: 14 }
      });
      y = doc.lastAutoTable.finalY + 5;

      // Título de sección
      doc.setFont("helvetica", "bold");
      doc.setFontSize(12);
      doc.setTextColor(...azul);
      doc.text("Mediciones dieléctricas estator motor", 105, y, { align: "center" });
      y += 5;
      doc.setTextColor(0, 0, 0);

      // Banner PRE/POST
      doc.autoTable({
        startY: y,
        body: [[{
          content: "MEDICIONES DIELÉCTRICAS   " + tipo + "   MANTENIMIENTO",
          styles: { halign: "center", fontStyle: "bold", fillColor: azul, textColor: [255,255,255], fontSize: 10, cellPadding: 3 }
        }]],
        theme: "plain",
        margin: { left: 14, right: 14 }
      });
      y = doc.lastAutoTable.finalY;

      const e1 = est1 || {};
      const e2 = est2 || {};
      const m1 = e1.mediciones || [];
      const m2 = e2.mediciones || [];
      const lbl = (txt) => ({ content: txt, styles: { fontStyle: "bold", fillColor: grisC } });
      const sub = (txt) => ({ content: txt, styles: { fontStyle: "bold", fillColor: grisC, halign: "center" } });

      // Tabla principal 4 columnas (Estator 1 | Estator 2)
      doc.autoTable({
        startY: y,
        head: [[
          { content: "ESTATOR 1", colSpan: 2, styles: { halign: "center", fillColor: azul, textColor: [255,255,255], fontStyle: "bold" } },
          { content: "ESTATOR 2", colSpan: 2, styles: { halign: "center", fillColor: azul, textColor: [255,255,255], fontStyle: "bold" } }
        ]],
        body: [
          [lbl("Fecha"),        e1.fecha   ||"", lbl("Fecha"),        e2.fecha   ||""],
          [lbl("V.Prueba [V]"), e1.vprueba ||"", lbl("V.Prueba [V]"), e2.vprueba ||""],
          [lbl("T°[C°]"),       e1.temp    ||"", lbl("T°[C°]"),       e2.temp    ||""],
          [lbl("Cap. [µF]"),    e1.cap     ||"", lbl("Cap. [µF]"),    e2.cap     ||""],
          [lbl("IP"),           e1.ip      ||"", lbl("IP"),           e2.ip      ||""],
          [sub("Tiempo [min]"), sub("Resistencia"), sub("Tiempo [min]"), sub("Resistencia")],
          ...TIEMPOS.map((t, i) => [
            { content: t, styles: { halign: "center" } }, m1[i]?.r || "",
            { content: t, styles: { halign: "center" } }, m2[i]?.r || ""
          ])
        ],
        theme: "grid",
        styles: { fontSize: 8, cellPadding: 2 },
        columnStyles: {
          0: { cellWidth: 28 },
          1: { cellWidth: 63 },
          2: { cellWidth: 28 },
          3: { cellWidth: 63 }
        },
        margin: { left: 14, right: 14 }
      });
      y = doc.lastAutoTable.finalY + 6;

      if (y > 232) { doc.addPage(); y = 20; }

      // Resistencia Óhmica — dos tablas lado a lado
      const yOhm = y;
      const rohmHook = (data) => {
        if (data.section === "head") {
          if (data.row.index === 0) {
            data.cell.styles.fillColor = azul;
            data.cell.styles.textColor = [255, 255, 255];
            data.cell.styles.halign    = "center";
            data.cell.styles.fontStyle = "bold";
          } else {
            data.cell.styles.fillColor = grisC;
            data.cell.styles.textColor = [0, 0, 0];
            data.cell.styles.fontStyle = "bold";
          }
        }
        if (data.section === "body" && data.column.index === 0) {
          data.cell.styles.fontStyle  = "bold";
          data.cell.styles.fillColor  = grisC;
        }
      };

      doc.autoTable({
        startY: yOhm,
        head: [[{ content: "RESISTENCIA OHMICA ESTATOR 1", colSpan: 3 }], ["Fases", "Valor", "Unidad"]],
        body: [
          ["L1-L2", e1.l12 || "", "[mΩ]"],
          ["L1-L3", e1.l13 || "", "[mΩ]"],
          ["L2-L3", e1.l21 || "", "[mΩ]"]
        ],
        theme: "grid",
        styles: { fontSize: 8, cellPadding: 2 },
        columnStyles: { 0: { cellWidth: 25 }, 1: { cellWidth: 37 }, 2: { cellWidth: 25 } },
        tableWidth: 87,
        margin: { left: 14 },
        didParseCell: rohmHook
      });
      const finOhm1 = doc.lastAutoTable.finalY;

      doc.autoTable({
        startY: yOhm,
        head: [[{ content: "RESISTENCIA OHMICA ESTATOR 2", colSpan: 3 }], ["Fases", "Valor", "Unidad"]],
        body: [
          ["L1-L2", e2.l12 || "", "[mΩ]"],
          ["L1-L3", e2.l13 || "", "[mΩ]"],
          ["L2-L3", e2.l21 || "", "[mΩ]"]
        ],
        theme: "grid",
        styles: { fontSize: 8, cellPadding: 2 },
        columnStyles: { 0: { cellWidth: 25 }, 1: { cellWidth: 37 }, 2: { cellWidth: 25 } },
        tableWidth: 87,
        margin: { left: 109 },
        didParseCell: rohmHook
      });
      const finOhm2 = doc.lastAutoTable.finalY;

      return Math.max(finOhm1, finOhm2);
    }

    // Función para página de rotor
    function tablaRotor(tipo, rot) {
      if (!rot) return;
      const tieneDatos = rot.mediciones?.some(m => m.r) || rot.cap || rot.if_nA;
      if (!tieneDatos) return;

      let y = cabeceraHoja();

      doc.autoTable({
        startY: y,
        body: [
          [{ content: "N° Protocolo", styles:{fontStyle:"bold",fillColor:grisC}}, numProt,
           { content: "Cliente",      styles:{fontStyle:"bold",fillColor:grisC}}, cliente],
          [{ content: "Equipo / Motor",styles:{fontStyle:"bold",fillColor:grisC}}, {content: equipo, colSpan: 3}]
        ],
        theme: "grid", styles: { fontSize: 8, cellPadding: 2 },
        columnStyles: { 0: { cellWidth: 33 }, 2: { cellWidth: 26 } },
        margin: { left: 14, right: 14 }
      });
      y = doc.lastAutoTable.finalY + 5;

      doc.setFont("helvetica", "bold"); doc.setFontSize(12); doc.setTextColor(...azul);
      doc.text("Mediciones dieléctricas rotor motor", 105, y, { align: "center" });
      y += 5; doc.setTextColor(0, 0, 0);

      doc.autoTable({
        startY: y,
        body: [[{ content: "MEDICIONES DIELÉCTRICAS   " + tipo + "   MANTENIMIENTO",
          styles: { halign: "center", fontStyle: "bold", fillColor: azul, textColor: [255,255,255], fontSize: 10, cellPadding: 3 } }]],
        theme: "plain", margin: { left: 14, right: 14 }
      });
      y = doc.lastAutoTable.finalY;

      const m = rot.mediciones || [];
      const lbl = (txt) => ({ content: txt, styles: { fontStyle: "bold", fillColor: grisC } });
      const sub = (txt) => ({ content: txt, styles: { fontStyle: "bold", fillColor: grisC, halign: "center" } });

      doc.autoTable({
        startY: y,
        head: [[{ content: "ROTOR", colSpan: 2, styles: { halign: "center", fillColor: azul, textColor: [255,255,255], fontStyle: "bold" } }]],
        body: [
          [lbl("Fecha"),        rot.fecha   || ""],
          [lbl("V.Prueba [V]"), rot.vprueba || "500"],
          [lbl("T°[C°]"),       rot.temp    || ""],
          [lbl("Cap. [µF]"),    rot.cap     || ""],
          [lbl("IP"),           rot.ip      || ""],
          [sub("Tiempo [min]"), sub("Resistencia")],
          ...TIEMPOS.map((t, i) => [{ content: t, styles: { halign: "center" } }, m[i]?.r || ""])
        ],
        theme: "grid", styles: { fontSize: 8, cellPadding: 2 },
        columnStyles: { 0: { cellWidth: 35 }, 1: { cellWidth: 56 } },
        tableWidth: 91, margin: { left: 14 }
      });
      const finMed = doc.lastAutoTable.finalY + 6;

      if (finMed > 232) { doc.addPage(); y = 20; } else { y = finMed; }

      const rohmHookR = (data) => {
        if (data.section === "head") {
          if (data.row.index === 0) { data.cell.styles.fillColor = azul; data.cell.styles.textColor = [255,255,255]; data.cell.styles.halign = "center"; data.cell.styles.fontStyle = "bold"; }
          else { data.cell.styles.fillColor = grisC; data.cell.styles.textColor = [0,0,0]; data.cell.styles.fontStyle = "bold"; }
        }
        if (data.section === "body" && data.column.index === 0) { data.cell.styles.fontStyle = "bold"; data.cell.styles.fillColor = grisC; }
      };

      doc.autoTable({
        startY: y,
        head: [[{ content: "RESISTENCIA OHMICA ROTOR", colSpan: 3 }], ["Fases", "Valor", "Unidad"]],
        body: [["L1-L2", rot.l12 || "", "[Ω]"]],
        theme: "grid", styles: { fontSize: 8, cellPadding: 2 },
        columnStyles: { 0: { cellWidth: 25 }, 1: { cellWidth: 37 }, 2: { cellWidth: 25 } },
        tableWidth: 87, margin: { left: 14 },
        didParseCell: rohmHookR
      });
    }

    // Generar sección PRE
    if (preEst1 || preEst2) tablaEstatores("PRE",  preEst1,  preEst2);
    if (preRotor)            tablaRotor("PRE",  preRotor);

    // Generar sección POST
    if (postEst1 || postEst2) tablaEstatores("POST", postEst1, postEst2);
    if (postRotor)             tablaRotor("POST", postRotor);

    // Página de firmas
    doc.addPage();
    doc.setFillColor(...azul);
    doc.rect(0, 0, 210, 14, "F");
    doc.setTextColor(255, 255, 255);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(11);
    doc.text("REPORTE DE ENTREGA DE EQUIPO  —  N°: " + numProt, 105, 9.5, { align: "center" });
    doc.setTextColor(0, 0, 0);

    doc.setFont("helvetica", "bold");
    doc.setFontSize(10);
    doc.text("Declaración de conformidad", 14, 28);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(9);
    const texto = "Se certifica que el equipo \"" + equipo + "\" del cliente \"" + cliente + "\" ha sido sometido a las mediciones dieléctricas correspondientes al protocolo N° " + numProt + ", y que los resultados obtenidos han sido revisados y aceptados por las partes.";
    const lineas = doc.splitTextToSize(texto, 182);
    doc.text(lineas, 14, 35);

    doc.setFont("helvetica", "bold");
    doc.setFontSize(10);
    doc.text("Firmas", 14, 60);

    doc.setFont("helvetica", "normal");
    doc.setFontSize(9);
    doc.line(14, 80, 95, 80);
    doc.text("Firma Técnico AYCA", 14, 86);
    doc.text("Nombre: _____________________________", 14, 92);

    doc.line(115, 80, 196, 80);
    doc.text("Firma Supervisor / Cliente", 115, 86);
    doc.text("Nombre: _____________________________", 115, 92);

    // Numeración de páginas
    const totalPag = doc.internal.getNumberOfPages();
    for (let i = 1; i <= totalPag; i++) {
      doc.setPage(i);
      doc.setFontSize(7);
      doc.setTextColor(140);
      doc.text("Página " + i + " de " + totalPag, 196, 291, { align: "right" });
      doc.text("AYCA Smart Maintenance  —  Reporte de Entrega de Equipo  |  N°: " + numProt, 14, 291);
    }

    doc.save(numProt + "_reporte_entrega.pdf");

  } catch (err) {
    alert("Error al generar el reporte: " + err.message);
    console.error(err);
  }
}