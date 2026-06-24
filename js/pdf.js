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
// ===============================
// Gráfico de Excentricidad
// ===============================
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