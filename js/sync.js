// ===============================
// SINCRONIZACIÓN OFFLINE → NUBE
// ===============================

const _SYNC_KEY = 'aycaSyncPendiente';

// ---- Cola de pendientes ----

function encolarSync(tipo, numProtocolo) {
  let cola = _colaPendiente();
  const idx = cola.findIndex(i => i.tipo === tipo && i.numProtocolo === numProtocolo);
  const item = { tipo, numProtocolo, ts: Date.now() };
  if (idx >= 0) cola[idx] = item; else cola.push(item);
  localStorage.setItem(_SYNC_KEY, JSON.stringify(cola));
  _actualizarBadge();
}

function _quitarDeCola(tipo, numProtocolo) {
  const cola = _colaPendiente().filter(i => !(i.tipo === tipo && i.numProtocolo === numProtocolo));
  localStorage.setItem(_SYNC_KEY, JSON.stringify(cola));
  _actualizarBadge();
}

function _colaPendiente() {
  return JSON.parse(localStorage.getItem(_SYNC_KEY) || '[]');
}

// ---- Sincronizar todo ----

async function sincronizarTodo() {
  if (!navigator.onLine) return;
  if (typeof supabaseAYCA === 'undefined') return;

  const cola = _colaPendiente();
  if (cola.length === 0) return;

  _setStatusBar('sync');

  for (const item of [...cola]) {
    try {
      const ok = await _subirItem(item);
      if (ok) _quitarDeCola(item.tipo, item.numProtocolo);
    } catch (e) {
      console.warn('AYCA Sync error:', e);
    }
  }

  const restantes = _colaPendiente().length;
  _setStatusBar(restantes === 0 ? 'ok' : 'error', restantes);
  if (restantes === 0) setTimeout(_actualizarEstadoRed, 3000);
}

async function _subirItem({ tipo, numProtocolo }) {
  const data = JSON.parse(localStorage.getItem(`${tipo}_${numProtocolo}`) || 'null');
  if (!data) return true; // dato ya no existe localmente, quitar de cola

  const registro = {
    numero:     numProtocolo,
    fecha:      data.fecha      || '',
    cliente:    data.cliente    || '',
    faena:      data.faena      || data.equipo || data.ventiladorNum || '',
    area:       data.area || _label(tipo),
    tecnico:    data.tecnico    || '',
    // CD: solo las posiciones, mismo formato que guarda pdf.js y que lee _abrirCDNube
    posiciones: JSON.stringify(tipo === 'cd' ? (data.posiciones || {}) : data)
  };

  const { error } = await supabaseAYCA
    .from('protocolos_ayca')
    .upsert([registro], { onConflict: 'numero' });

  if (error) { console.error('Sync upload error:', error); return false; }
  return true;
}

function _label(tipo) {
  return { carbones: 'Carbones', ventilador: 'Ventilador', cd: 'Control Dimensional' }[tipo] || tipo;
}

// ---- Indicador visual ----

function _actualizarEstadoRed() {
  const bar = document.getElementById('syncBar');
  const txt = document.getElementById('syncTxt');
  const badge = document.getElementById('syncBadge');
  if (!bar || !txt) return;

  const n = _colaPendiente().length;

  if (navigator.onLine) {
    bar.style.background = '#f0fdf4';
    bar.style.borderBottomColor = '#bbf7d0';
    txt.innerHTML = '🟢 En línea';
    txt.style.color = '#166534';
  } else {
    bar.style.background = '#fef2f2';
    bar.style.borderBottomColor = '#fecaca';
    txt.innerHTML = '🔴 Sin conexión &mdash; datos guardados en el dispositivo';
    txt.style.color = '#991b1b';
  }

  if (badge) {
    badge.style.display = n > 0 ? '' : 'none';
    badge.textContent = `${n} pendiente${n !== 1 ? 's' : ''}`;
  }
}

function _setStatusBar(estado, n = 0) {
  const bar = document.getElementById('syncBar');
  const txt = document.getElementById('syncTxt');
  if (!bar || !txt) return;

  if (estado === 'sync') {
    bar.style.background = '#fef9c3'; bar.style.borderBottomColor = '#fde047';
    txt.innerHTML = '🔄 Sincronizando con la nube…'; txt.style.color = '#92400e';
  } else if (estado === 'ok') {
    bar.style.background = '#f0fdf4'; bar.style.borderBottomColor = '#bbf7d0';
    txt.innerHTML = '✅ Sincronizado con la nube'; txt.style.color = '#166534';
  } else if (estado === 'error') {
    bar.style.background = '#fef2f2'; bar.style.borderBottomColor = '#fecaca';
    txt.innerHTML = `⚠️ Sin conexión &mdash; ${n} protocolo${n !== 1 ? 's' : ''} pendiente${n !== 1 ? 's' : ''}`;
    txt.style.color = '#991b1b';
  }
}

function _actualizarBadge() {
  const badge = document.getElementById('syncBadge');
  const n = _colaPendiente().length;
  if (!badge) return;
  badge.style.display = n > 0 ? '' : 'none';
  badge.textContent = `${n} pendiente${n !== 1 ? 's' : ''}`;
}

// ---- Eventos de red ----

window.addEventListener('online',  () => { _actualizarEstadoRed(); sincronizarTodo(); });
window.addEventListener('offline', () => { _actualizarEstadoRed(); });
document.addEventListener('DOMContentLoaded', _actualizarEstadoRed);
