function dibujarGraficoExcentricidad() {
  const canvas = document.getElementById("graficoExcentricidad");
  if (!canvas) return;

  const ctx = canvas.getContext("2d");
  const W = canvas.width;   // 320
  const H = canvas.height;  // 320

  ctx.clearRect(0, 0, W, H);

  // ── promedios de entrehierro por posición ──
  function avg(pos) {
    if (typeof datosPosiciones === "undefined" || !datosPosiciones[pos]) return 0;
    const filas = datosPosiciones[pos].entrehierro || [];
    let suma = 0, n = 0;
    filas.forEach(f => {
      const v = parseFloat(f.promedio);
      if (!isNaN(v) && v > 0) { suma += v; n++; }
    });
    return n ? suma / n : 0;
  }

  const p0   = avg("0°");
  const p90  = avg("90°");
  const p180 = avg("180°");
  const p270 = avg("270°");

  // centro y radios visuales
  const cx = W / 2;
  const cy = H / 2 + 8;  // ligeramente abajo para dejar espacio al título
  const R_ROTOR  = 72;
  const R_STATOR = 80;

  // desplazamiento del estator real respecto al nominal (mm → px)
  // Si p270 > p90 → estator desplazado a la derecha (dx > 0)
  // Si p180 > p0  → estator desplazado hacia abajo  (dy > 0)
  const ESC = 5;
  const dxMm = (p270 - p90)  / 2;
  const dyMm = (p180 - p0)   / 2;
  const dx = dxMm * ESC;
  const dy = dyMm * ESC;
  const excentricidad = Math.sqrt(dxMm * dxMm + dyMm * dyMm);

  // ── criterio de aceptación (Paso CD) ──
  const gapNominal = parseFloat((document.getElementById("gapNominal") || {}).value) || 0;
  const tolAlerta  = parseFloat((document.getElementById("tolAlertaPct") || {}).value);
  const tolFalla   = parseFloat((document.getElementById("tolFallaPct") || {}).value);

  function banda(desvPct) {
    if (isNaN(desvPct) || gapNominal <= 0) return { color: "#9aa0a6", txt: "SIN CRITERIO" };
    if (desvPct <= tolAlerta) return { color: "#1a9d4b", txt: "OK" };
    if (desvPct <= tolFalla)  return { color: "#e0a500", txt: "ALERTA" };
    return { color: "#d43a2f", txt: "FUERA DE RANGO" };
  }

  const eccPct  = gapNominal > 0 ? (excentricidad / gapNominal) * 100 : NaN;
  const vGlobal = banda(eccPct);

  // ── 1. fondo gris ──
  ctx.fillStyle = "#8a8a8a";
  ctx.fillRect(0, 0, W, H);

  // ── 2. contorno de carcasa del motor (octágono estilizado) ──
  ctx.beginPath();
  const pts = [
    [-70,-118],[70,-118],[100,-90],[100,90],[70,112],[-70,112],[-100,90],[-100,-90]
  ];
  ctx.moveTo(cx + pts[0][0], cy + pts[0][1]);
  pts.slice(1).forEach(([x, y]) => ctx.lineTo(cx + x, cy + y));
  ctx.closePath();
  ctx.fillStyle = "#aaaaaa";
  ctx.fill();
  ctx.strokeStyle = "#777";
  ctx.lineWidth = 2;
  ctx.stroke();

  // ── 3. carcasa del estator (rectángulo blanco) ──
  const rx = cx - 92, ry = cy - 95, rw = 184, rh = 185;
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(rx, ry, rw, rh);
  ctx.strokeStyle = "#cccccc";
  ctx.lineWidth = 1;
  ctx.strokeRect(rx, ry, rw, rh);

  // ── 4. tramas cruzadas en esquinas inferiores ──
  function hatch(x, y, w, h) {
    ctx.save();
    ctx.beginPath();
    ctx.rect(x, y, w, h);
    ctx.clip();
    ctx.fillStyle = "#d0d0d0";
    ctx.fillRect(x, y, w, h);
    ctx.strokeStyle = "#aaaaaa";
    ctx.lineWidth = 0.7;
    for (let i = -h; i <= w + h; i += 7) {
      ctx.beginPath(); ctx.moveTo(x + i, y); ctx.lineTo(x + i + h, y + h); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(x + i + h, y); ctx.lineTo(x + i, y + h); ctx.stroke();
    }
    ctx.restore();
  }
  hatch(rx,          ry + rh - 52, 52, 52);
  hatch(rx + rw - 52, ry + rh - 52, 52, 52);

  // ── 5. rotor (círculo gris relleno) ──
  ctx.beginPath();
  ctx.arc(cx, cy, R_ROTOR, 0, Math.PI * 2);
  ctx.fillStyle = "#c4c4c4";
  ctx.fill();
  ctx.strokeStyle = "#999999";
  ctx.lineWidth = 1.5;
  ctx.stroke();

  // ── 6. estator nominal (anillo azul, centrado) ──
  ctx.beginPath();
  ctx.arc(cx, cy, R_STATOR, 0, Math.PI * 2);
  ctx.lineWidth = 4;
  ctx.strokeStyle = "#4a8fd4";
  ctx.stroke();

  // ── 7. desviación del estator (anillo naranja, desplazado) ──
  ctx.beginPath();
  ctx.arc(cx + dx, cy + dy, R_STATOR, 0, Math.PI * 2);
  ctx.lineWidth = 4;
  ctx.strokeStyle = "#d4701a";
  ctx.stroke();

  // ── 8. etiquetas de medición en las 4 posiciones ──
  function labelMed(deg, val, lx, ly) {
    ctx.font = "bold 11px Arial";
    ctx.textAlign = "center";
    ctx.fillStyle = "#ffffff";
    ctx.fillText(deg, lx, ly - 14);

    let boxColor = "#1a1a1a";
    if (gapNominal > 0 && val > 0) {
      boxColor = banda(Math.abs(val - gapNominal) / gapNominal * 100).color;
    }
    ctx.fillStyle = boxColor;
    ctx.fillRect(lx - 21, ly - 11, 42, 20);
    ctx.strokeStyle = "#888888";
    ctx.lineWidth = 1;
    ctx.strokeRect(lx - 21, ly - 11, 42, 20);

    ctx.fillStyle = "#ffffff";
    ctx.font = "bold 12px Arial";
    ctx.fillText(val > 0 ? val.toFixed(1) : "—", lx, ly + 5);
  }

  const M = 26;
  labelMed("180°", p180, cx,                  cy - R_STATOR - M);
  labelMed("0°",   p0,   cx,                  cy + R_STATOR + M);
  labelMed("90°",  p90,  cx + R_STATOR + M,   cy);
  labelMed("270°", p270, cx - R_STATOR - M,   cy);

  // ── 9. título ──
  ctx.fillStyle = "#ffffff";
  ctx.font = "bold 12px Arial";
  ctx.textAlign = "center";
  ctx.fillText("Vista desde lado Descarga", cx, 14);

  // ── 10. excentricidad calculada ──
  ctx.font = "11px Arial";
  ctx.fillStyle = "#ffffff";
  ctx.textAlign = "center";
  ctx.fillText("Excentricidad: " + excentricidad.toFixed(2) + " mm", cx, H - 8);

  // ── veredicto en pantalla (Paso CD) ──
  const _vDiv = document.getElementById("veredictoEntrehierro");
  if (_vDiv) {
    if (gapNominal > 0) {
      _vDiv.style.background = vGlobal.color;
      _vDiv.style.color = "#ffffff";
      _vDiv.textContent = "Excentricidad " + excentricidad.toFixed(2) + " mm = " +
        eccPct.toFixed(1) + "% del nominal → " + vGlobal.txt +
        "  (alerta ±" + tolAlerta + "% · rechazo ±" + tolFalla + "%)";
    } else {
      _vDiv.style.background = "#eeeeee";
      _vDiv.style.color = "#333333";
      _vDiv.textContent = "Ingrese el entrehierro nominal para evaluar el criterio";
    }
  }

  // ── 11. leyenda (arriba derecha) ──
  const legX = W - 118, legY = 28;
  [
    { txt: "Rotor",           fill: "#c4c4c4", sc: "#999999", lw: 1.5, filled: true  },
    { txt: "Estator Nominal", fill: null,      sc: "#4a8fd4", lw: 4,   filled: false },
    { txt: "Desv. Estator",   fill: null,      sc: "#d4701a", lw: 4,   filled: false },
  ].forEach((item, i) => {
    const iy = legY + i * 17;
    ctx.strokeStyle = item.sc;
    ctx.lineWidth = item.lw;
    if (item.filled) {
      ctx.fillStyle = item.fill;
      ctx.fillRect(legX, iy - 7, 14, 11);
    }
    ctx.strokeRect(legX, iy - 7, 14, 11);
    ctx.fillStyle = "#ffffff";
    ctx.font = "10px Arial";
    ctx.textAlign = "left";
    ctx.fillText(item.txt, legX + 17, iy + 3);
  });
}
