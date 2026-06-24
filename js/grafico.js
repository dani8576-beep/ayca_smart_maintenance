function dibujarGraficoExcentricidad() {

  const canvas = document.getElementById("graficoExcentricidad");
  if (!canvas) return;

  const ctx = canvas.getContext("2d");

  ctx.clearRect(0, 0, canvas.width, canvas.height);

  const cx = canvas.width / 2;
  const cy = canvas.height / 2;
  const radioEstator = 120;
  const radioRotor = 70;

  ctx.fillStyle = "white";
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  function promedioPosicion(pos) {
    if (!datosPosiciones[pos]) return 0;

    const filas = datosPosiciones[pos].entrehierro || [];
    let suma = 0;
    let cantidad = 0;

    filas.forEach(f => {
      const p = parseFloat(f.promedio);
      if (!isNaN(p) && p > 0) {
        suma += p;
        cantidad++;
      }
    });

    return cantidad ? suma / cantidad : 0;
  }

  const p0 = promedioPosicion("0°");
  const p90 = promedioPosicion("90°");
  const p180 = promedioPosicion("180°");
  const p270 = promedioPosicion("270°");

  const dxMm = (p90 - p270) / 2;
  const dyMm = (p180 - p0) / 2;
  const excentricidad = Math.sqrt(dxMm * dxMm + dyMm * dyMm);

  const escala = 8;
  const dx = dxMm * escala;
  const dy = dyMm * escala;

  // Estator
  ctx.beginPath();
  ctx.arc(cx, cy, radioEstator, 0, Math.PI * 2);
  ctx.lineWidth = 4;
  ctx.strokeStyle = "#0b3158";
  ctx.stroke();

  // Rotor desplazado
  ctx.beginPath();
  ctx.arc(cx + dx, cy + dy, radioRotor, 0, Math.PI * 2);
  ctx.lineWidth = 3;
  ctx.strokeStyle = "#dc2626";
  ctx.stroke();

  // Ejes
  ctx.beginPath();
  ctx.moveTo(cx - radioEstator - 20, cy);
  ctx.lineTo(cx + radioEstator + 20, cy);
  ctx.moveTo(cx, cy - radioEstator - 20);
  ctx.lineTo(cx, cy + radioEstator + 20);
  ctx.strokeStyle = "#c7c7c7";
  ctx.lineWidth = 1;
  ctx.stroke();

  // Centro ideal
  ctx.beginPath();
  ctx.arc(cx, cy, 5, 0, Math.PI * 2);
  ctx.fillStyle = "#16a34a";
  ctx.fill();

  // Centro real
  ctx.beginPath();
  ctx.arc(cx + dx, cy + dy, 6, 0, Math.PI * 2);
  ctx.fillStyle = "#dc2626";
  ctx.fill();

  // Flecha de excentricidad
  ctx.beginPath();
  ctx.moveTo(cx, cy);
  ctx.lineTo(cx + dx, cy + dy);
  ctx.strokeStyle = "#dc2626";
  ctx.lineWidth = 2;
  ctx.stroke();

  // Etiquetas grados
  ctx.fillStyle = "#111827";
  ctx.font = "bold 14px Arial";
  ctx.fillText("0°", cx - 10, cy - radioEstator - 12);
  ctx.fillText("90°", cx + radioEstator + 10, cy + 5);
  ctx.fillText("180°", cx - 18, cy + radioEstator + 22);
  ctx.fillText("270°", cx - radioEstator - 38, cy + 5);

  // Leyenda
  ctx.font = "12px Arial";
  ctx.fillStyle = "#0b3158";
  ctx.fillText("Estator", 15, 20);

  ctx.fillStyle = "#dc2626";
  ctx.fillText("Rotor / centro real", 15, 38);

  ctx.fillStyle = "#16a34a";
  ctx.fillText("Centro ideal", 15, 56);

  // Datos
  ctx.fillStyle = "#111827";
  ctx.font = "12px Arial";
  ctx.fillText(`P0: ${p0.toFixed(2)} mm`, 15, canvas.height - 70);
  ctx.fillText(`P90: ${p90.toFixed(2)} mm`, 15, canvas.height - 55);
  ctx.fillText(`P180: ${p180.toFixed(2)} mm`, 15, canvas.height - 40);
  ctx.fillText(`P270: ${p270.toFixed(2)} mm`, 15, canvas.height - 25);

  ctx.font = "bold 13px Arial";
  ctx.fillText(`Excentricidad: ${excentricidad.toFixed(2)} mm`, 150, canvas.height - 35);
}