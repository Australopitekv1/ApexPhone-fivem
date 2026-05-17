// ============================================================
//  ApexPhone — app.js
//  Complete SPA: NUI bridge, all app modules, state management.
// ============================================================

'use strict';

// ── NUI Bridge ──────────────────────────────────────────────────
const NUI = {
  /** Send a callback message to Lua client. */
  callback(name, data = {}) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(data),
    }).then(r => r.json()).catch(() => null);
  },
};

// Polyfill for non-FiveM context (dev preview)
function GetParentResourceName() {
  return window.GetParentResourceName ? window.GetParentResourceName() : 'apexphone';
}

// ── State ────────────────────────────────────────────────────────
const State = {
  open:        false,
  unlocked:    false,
  phoneData:   {},
  appData:     {},          // app → data cache
  appStack:    [],          // navigation history
  activeApp:   null,
  activeCall:  null,
  callTimerInterval: null,
  battery:     100,
  signal:      3,
  airplaneMode: false,
  theme:       'dark',
  currentWallpaper: 'default',
  cryptoSelectedCoin: null,
};

// ── Utility ──────────────────────────────────────────────────────

/** Format seconds as MM:SS */
function fmtTime(sec) {
  const m = String(Math.floor(sec / 60)).padStart(2, '0');
  const s = String(sec % 60).padStart(2, '0');
  return `${m}:${s}`;
}

/** Escape HTML to prevent XSS from server data. */
function esc(str) {
  const d = document.createElement('div');
  d.textContent = str ?? '';
  return d.innerHTML;
}

/** Format a date string. */
function fmtDate(str) {
  if (!str) return '';
  const d = new Date(str);
  if (isNaN(d)) return str;
  return d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

/** Debounce helper. */
function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

// ── Clock ────────────────────────────────────────────────────────
function updateClock() {
  const now  = new Date();
  const h    = String(now.getHours()).padStart(2, '0');
  const m    = String(now.getMinutes()).padStart(2, '0');
  const time = `${h}:${m}`;
  const date = now.toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long' });

  document.getElementById('sb-time').textContent     = time;
  document.getElementById('lock-time').textContent   = time;
  document.getElementById('widget-time').textContent = time;

  const d = document.getElementById('lock-date');
  if (d) d.textContent = date;
  const wd = document.getElementById('widget-date');
  if (wd) wd.textContent = now.toLocaleDateString('en-US', { weekday: 'short', day: 'numeric', month: 'short' });
}

setInterval(updateClock, 1000);
updateClock();

// ── Battery UI ───────────────────────────────────────────────────
function updateBatteryUI(battery, charging) {
  const fill = document.getElementById('sb-bat-fill');
  if (!fill) return;
  fill.style.width = `${battery}%`;
  fill.className = '';
  if (charging)       fill.style.background = '#3a86ff';
  else if (battery <= 5)  fill.classList.add('critical');
  else if (battery <= 15) fill.classList.add('low');
}

// ── Signal UI ────────────────────────────────────────────────────
function updateSignalUI(signal) {
  const el = document.getElementById('sb-signal');
  if (!el) return;
  el.className = `icon-signal s${signal}`;
}

// ── Toast Notifications ──────────────────────────────────────────

const TOAST_ICONS = {
  success: '✅', error: '❌', warning: '⚠️',
  message: '💬', call: '📞', email: '✉️',
  ride: '🚕', invoice: '💳', alert: '🚨',
  contact: '👤', info: 'ℹ️',
};

const Toast = {
  show(notif) {
    const container = document.getElementById('toast-container');
    const el = document.createElement('div');
    el.className = `toast ${notif.type || 'info'}`;
    el.innerHTML = `
      <span class="toast-icon">${TOAST_ICONS[notif.type] || 'ℹ️'}</span>
      <div class="toast-body">
        <div class="toast-title">${esc(notif.title || '')}</div>
        <div class="toast-text">${esc(notif.message || '')}</div>
      </div>`;

    // Click action based on type
    el.addEventListener('click', () => {
      el.style.animation = 'toastOut 0.25s forwards';
      setTimeout(() => el.remove(), 260);
      if (notif.type === 'message') App.open('messages');
      if (notif.type === 'call')    { /* handled by incoming-call overlay */ }
      if (notif.type === 'email')   App.open('email');
    });

    container.prepend(el);

    // Auto-dismiss
    setTimeout(() => {
      if (el.parentNode) {
        el.style.animation = 'toastOut 0.25s forwards';
        setTimeout(() => el.remove(), 260);
      }
    }, 5000);

    // Max 3 toasts
    while (container.children.length > 3) {
      container.lastChild.remove();
    }
  },
};

// ── Authentication ───────────────────────────────────────────────

const Auth = {
  pinBuffer: '',
  attempts:  0,

  startFingerprint() {
    const overlay = document.getElementById('fp-overlay');
    overlay.classList.remove('hidden');
    document.getElementById('fp-status').textContent = 'Scanning…';
    document.getElementById('fp-ring').style.borderColor = '#3a86ff';
    NUI.callback('verifyFingerprint');
  },

  onFingerprintResult(success) {
    const overlay = document.getElementById('fp-overlay');
    if (success) {
      document.getElementById('fp-status').textContent = 'Unlocked ✓';
      document.getElementById('fp-ring').style.borderColor = '#2ecc71';
      setTimeout(() => { overlay.classList.add('hidden'); Auth.unlock(); }, 600);
    } else {
      document.getElementById('fp-status').textContent = 'Not recognized';
      document.getElementById('fp-ring').style.borderColor = '#e74c3c';
      setTimeout(() => overlay.classList.add('hidden'), 1200);
    }
  },

  showPIN() {
    document.getElementById('pin-pad').classList.remove('hidden');
    this.pinBuffer = '';
    this._renderDots();
  },

  pinKey(key) {
    const err = document.getElementById('pin-error');
    err.classList.add('hidden');

    if (key === 'C') {
      this.pinBuffer = this.pinBuffer.slice(0, -1);
    } else if (key === 'OK') {
      if (this.pinBuffer.length >= 4) NUI.callback('verifyPIN', { pin: this.pinBuffer });
      return;
    } else if (this.pinBuffer.length < 6) {
      this.pinBuffer += key;
      if (this.pinBuffer.length >= 4) {
        // auto-submit at 4 digits if no PIN is set (quick unlock)
        NUI.callback('verifyPIN', { pin: this.pinBuffer });
        return;
      }
    }
    this._renderDots();
  },

  onPINResult(success) {
    if (success) {
      document.getElementById('pin-pad').classList.add('hidden');
      Auth.unlock();
    } else {
      this.attempts++;
      const err = document.getElementById('pin-error');
      err.textContent = this.attempts >= 3 ? 'Phone locked — try again later.' : 'Incorrect PIN';
      err.classList.remove('hidden');
      this.pinBuffer = '';
      this._renderDots();
    }
  },

  _renderDots() {
    const dots = document.querySelectorAll('#pin-dots .dot');
    dots.forEach((d, i) => d.classList.toggle('filled', i < this.pinBuffer.length));
  },

  unlock() {
    State.unlocked = true;
    document.getElementById('screen-lock').classList.remove('active');
    document.getElementById('screen-lock').classList.add('hidden');
    document.getElementById('screen-home').classList.remove('hidden');
    document.getElementById('screen-home').classList.add('active');
  },

  lock() {
    State.unlocked = false;
    document.getElementById('screen-home').classList.add('hidden');
    document.querySelectorAll('.app-screen').forEach(s => s.classList.add('hidden'));
    document.getElementById('screen-lock').classList.remove('hidden');
    document.getElementById('screen-lock').classList.add('active');
    State.appStack = [];
    State.activeApp = null;
  },
};

// ── App Navigation ───────────────────────────────────────────────

const App = {
  open(name) {
    const screen = document.getElementById(`app-${name}`);
    if (!screen) return;

    // Hide current app
    if (State.activeApp) {
      const cur = document.getElementById(`app-${State.activeApp}`);
      if (cur) cur.classList.add('hidden');
    }

    State.appStack.push(State.activeApp);
    State.activeApp = name;

    screen.classList.remove('hidden');
    screen.classList.add('slide-in');
    screen.addEventListener('animationend', () => screen.classList.remove('slide-in'), { once: true });

    // Lazy-load data for the app
    NUI.callback('loadApp', { app: name });

    // Special handling per app
    if (name === 'phone')       Phone.onOpen();
    if (name === 'messages')    Messages.onOpen();
    if (name === 'contacts')    Contacts.onOpen();
    if (name === 'camera')      Camera.onOpen();
    if (name === 'music')       Music.onOpen();
    if (name === 'darkweb')     DarkWeb.onOpen();
    if (name === 'mdt')         MDT.onOpen();
    if (name === 'flirtdate')   FlirtDate.onOpen();
    if (name === 'crypto')      Crypto.onOpen();
  },

  back() {
    if (State.activeApp) {
      const cur = document.getElementById(`app-${State.activeApp}`);
      if (cur) {
        cur.classList.add('slide-out');
        cur.addEventListener('animationend', () => {
          cur.classList.add('hidden');
          cur.classList.remove('slide-out');
        }, { once: true });
      }
    }
    const prev = State.appStack.pop();
    State.activeApp = prev || null;
    if (prev) {
      const ps = document.getElementById(`app-${prev}`);
      if (ps) ps.classList.remove('hidden');
    }
  },

  home() {
    // Close all apps and go to home
    if (State.activeApp) {
      const cur = document.getElementById(`app-${State.activeApp}`);
      if (cur) cur.classList.add('hidden');
    }
    State.activeApp = null;
    State.appStack  = [];
    // Close any sub-panels
    document.querySelectorAll('.app-screen').forEach(s => s.classList.add('hidden'));
  },
};

// ── Phone / Calls ────────────────────────────────────────────────

const Phone = {
  dialBuffer: '',
  callTimer:  0,

  onOpen() {
    this.tab('keypad');
    const hist = State.appData.callhistory || [];
    this._renderHistory(hist);
  },

  tab(name) {
    document.querySelectorAll('#app-phone .tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('#app-phone .tab-content').forEach(c => c.classList.remove('active'));
    const btn = Array.from(document.querySelectorAll('#app-phone .tab-btn'))
                     .find(b => b.textContent.toLowerCase() === name.toLowerCase());
    if (btn) btn.classList.add('active');
    const tab = document.getElementById(`phone-${name}`);
    if (tab) tab.classList.add('active');

    if (name === 'recent') NUI.callback('loadApp', { app: 'callhistory' });
  },

  dial(char) {
    if (this.dialBuffer.length >= 15) return;
    this.dialBuffer += char;
    document.getElementById('dial-number').textContent = this.dialBuffer;
  },

  dialBack() {
    this.dialBuffer = this.dialBuffer.slice(0, -1);
    document.getElementById('dial-number').textContent = this.dialBuffer;
  },

  call() {
    if (!this.dialBuffer) return;
    NUI.callback('makeCall', { number: this.dialBuffer });
    Toast.show({ title: 'Calling…', message: this.dialBuffer, type: 'call' });
  },

  answer() {
    NUI.callback('answerCall');
    this._showActiveCall();
  },

  decline() {
    NUI.callback('declineCall');
    document.getElementById('incoming-call-overlay').classList.add('hidden');
    State.activeCall = null;
  },

  hangup() {
    NUI.callback('endCall');
    this._endCallUI();
  },

  toggleSpeaker() {
    const btn = document.getElementById('btn-speaker');
    const on  = btn.classList.toggle('active');
    NUI.callback('setSpeaker', { enabled: on });
  },

  showIncoming(callId, number, name) {
    State.activeCall = { callId, number, name };
    const overlay = document.getElementById('incoming-call-overlay');
    document.getElementById('ic-name').textContent   = name || number;
    document.getElementById('ic-number').textContent = number;
    overlay.classList.remove('hidden');

    // Dynamic Island
    DynamicIsland.show('call', `📞 ${name || number}`);
  },

  onCallConnected(callId) {
    document.getElementById('incoming-call-overlay').classList.add('hidden');
    this._showActiveCall();
  },

  onCallEnded(callId, reason) {
    this._endCallUI();
    const msgs = { ended: 'Call ended', declined: 'Call declined', missed: 'Missed call', unavailable: 'Unavailable' };
    Toast.show({ title: msgs[reason] || 'Call ended', type: reason === 'missed' ? 'error' : 'info' });
    DynamicIsland.hide();
  },

  _showActiveCall() {
    const ic = document.getElementById('incoming-call-overlay');
    ic.classList.add('hidden');
    const ac = document.getElementById('active-call-overlay');
    if (State.activeCall) {
      document.getElementById('ac-name').textContent   = State.activeCall.name || State.activeCall.number;
      document.getElementById('ac-number').textContent = State.activeCall.number;
    }
    ac.classList.remove('hidden');
    this.callTimer = 0;
    clearInterval(this.callTimerInterval);
    this.callTimerInterval = setInterval(() => {
      this.callTimer++;
      document.getElementById('ac-timer').textContent = fmtTime(this.callTimer);
    }, 1000);

    DynamicIsland.show('call', `🟢 ${State.activeCall?.name || 'Active call'}`);
  },

  _endCallUI() {
    document.getElementById('active-call-overlay').classList.add('hidden');
    document.getElementById('incoming-call-overlay').classList.add('hidden');
    clearInterval(this.callTimerInterval);
    State.activeCall = null;
    DynamicIsland.hide();
  },

  _renderHistory(data) {
    const list = document.getElementById('call-history-list');
    if (!list) return;
    list.innerHTML = (data || []).map(c => `
      <li onclick="Phone._callFromHistory('${esc(c.number)}')">
        <span class="call-icon-${c.direction === 'in' ? (c.status === 'missed' ? 'miss' : 'in') : 'out'}">
          ${c.direction === 'out' ? '↗' : (c.status === 'missed' ? '↘' : '↙')}
        </span>
        <div style="flex:1">
          <div style="font-size:14px;color:var(--text-primary)">${esc(c.number)}</div>
          <div style="font-size:12px;color:var(--text-secondary)">${fmtDate(c.created_at)} · ${c.status}</div>
        </div>
        <div style="font-size:12px;color:var(--text-secondary)">${c.duration ? fmtTime(c.duration) : ''}</div>
      </li>`).join('');
  },

  _callFromHistory(number) {
    Phone.dialBuffer = number;
    document.getElementById('dial-number').textContent = number;
    Phone.tab('keypad');
  },
};

// ── Messages ─────────────────────────────────────────────────────

const Messages = {
  activeThread: null,
  activeThreadData: [],

  onOpen() {
    this._renderThreadList(State.appData.messages || []);
  },

  _renderThreadList(threads) {
    const el = document.getElementById('thread-list');
    if (!el) return;

    // Group by thread_id and show latest per thread
    const grouped = {};
    (threads || []).forEach(m => {
      const key = m.thread_id;
      if (!grouped[key] || new Date(m.created_at) > new Date(grouped[key].created_at)) {
        grouped[key] = m;
      }
    });

    const contacts = State.appData.contacts || [];
    const entries  = Object.values(grouped).sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

    el.innerHTML = entries.map(m => {
      const otherNum = m.from_number === State.phoneData?.number ? m.to_number : m.from_number;
      const contact  = contacts.find(c => c.number === otherNum);
      const name     = contact ? contact.name : otherNum;
      const initials = name.charAt(0).toUpperCase();
      const preview  = m.type === 'location' ? '📍 Location' : (m.message || '').substring(0, 40);

      return `<div class="thread-item ${m.unread > 0 ? 'unread' : ''}" onclick="Messages.openThread('${esc(m.thread_id)}','${esc(otherNum)}','${esc(name)}')">
        <div class="thread-avatar">${initials}</div>
        <div class="thread-info">
          <div class="thread-name">${esc(name)}</div>
          <div class="thread-preview">${esc(preview)}</div>
        </div>
        <div class="thread-time">${fmtDate(m.created_at)}</div>
        ${m.unread > 0 ? `<span class="badge">${m.unread}</span>` : ''}
      </div>`;
    }).join('');
  },

  openThread(threadId, number, name) {
    this.activeThread = { threadId, number, name };
    document.getElementById('thread-contact-name').textContent = name;
    const view = document.getElementById('thread-view');
    view.classList.remove('hidden');

    const msgs = (State.appData.messages || []).filter(m => m.thread_id === threadId);
    this._renderMessages(msgs);

    const input = document.getElementById('msg-input');
    input.dataset.to = number;
    setTimeout(() => input.focus(), 100);
  },

  closeThread() {
    document.getElementById('thread-view').classList.add('hidden');
    this.activeThread = null;
  },

  _renderMessages(msgs) {
    const el = document.getElementById('thread-messages');
    if (!el) return;

    el.innerHTML = msgs.map(m => {
      const isOut = m.from_number === State.phoneData?.number;
      let content = esc(m.message);

      if (m.type === 'location' && m.media) {
        const loc = typeof m.media === 'string' ? JSON.parse(m.media) : m.media;
        content = `<span class="location-link" onclick="NUI.callback('setWaypoint',{x:${loc.x},y:${loc.y}})">📍 Tap to navigate</span>`;
      }

      return `<div class="msg-bubble ${isOut ? 'out' : 'in'} ${m.type === 'location' ? 'location' : ''}">
        ${content}
        <span class="msg-time">${fmtDate(m.created_at)}</span>
      </div>`;
    }).join('');

    el.scrollTop = el.scrollHeight;
  },

  send() {
    const input = document.getElementById('msg-input');
    const msg   = input.value.trim();
    if (!msg || !this.activeThread) return;

    NUI.callback('sendMessage', { to: this.activeThread.number, message: msg });

    // Optimistic update
    const now = new Date().toISOString();
    State.appData.messages = State.appData.messages || [];
    State.appData.messages.push({
      thread_id:   this.activeThread.threadId,
      from_number: State.phoneData?.number,
      to_number:   this.activeThread.number,
      message:     msg,
      type:        'sms',
      created_at:  now,
    });

    const msgs = (State.appData.messages || []).filter(m => m.thread_id === this.activeThread.threadId);
    this._renderMessages(msgs);
    input.value = '';
  },

  compose() {
    document.getElementById('compose-view').classList.remove('hidden');
  },

  closeCompose() {
    document.getElementById('compose-view').classList.add('hidden');
  },

  sendCompose() {
    const to   = document.getElementById('compose-to').value.trim();
    const body = document.getElementById('compose-body').value.trim();
    if (!to || !body) return;
    NUI.callback('sendMessage', { to, message: body });
    document.getElementById('compose-to').value   = '';
    document.getElementById('compose-body').value = '';
    this.closeCompose();
    Toast.show({ title: 'Sent', message: `To ${to}`, type: 'success' });
  },

  attachImage() {
    // Trigger gallery pick — in FiveM this would be a base64 screenshot
    Toast.show({ title: 'Attach Image', message: 'Use Camera to take a photo first.', type: 'info' });
  },

  shareLocation() {
    if (!this.activeThread) return;
    NUI.callback('sendLocationSMS', { to: this.activeThread.number });
    Toast.show({ title: 'Location Shared', type: 'success' });
  },

  onNewMessage(data) {
    State.appData.messages = State.appData.messages || [];
    State.appData.messages.unshift(data);

    if (this.activeThread && data.thread_id === this.activeThread.threadId) {
      const msgs = State.appData.messages.filter(m => m.thread_id === this.activeThread.threadId);
      this._renderMessages(msgs);
    } else {
      this._renderThreadList(State.appData.messages);
      // Update badge
      const badge = document.getElementById('badge-messages');
      if (badge) {
        const count = parseInt(badge.textContent || '0') + 1;
        badge.textContent = count;
        badge.classList.remove('hidden');
      }
    }
  },
};

// ── Contacts ─────────────────────────────────────────────────────

const Contacts = {
  onOpen() {
    this.render(State.appData.contacts || []);
  },

  render(data) {
    const list = document.getElementById('contacts-list');
    if (!list) return;
    const sorted = [...(data || [])].sort((a, b) => a.name.localeCompare(b.name));
    list.innerHTML = sorted.map(c => `
      <li class="contact-item">
        <div class="contact-avatar">${esc(c.name.charAt(0).toUpperCase())}</div>
        <div class="contact-info">
          <div class="contact-name">${esc(c.name)}</div>
          <div class="contact-number">${esc(c.number)}</div>
        </div>
        <div class="contact-actions">
          <button onclick="Phone.dialBuffer='${esc(c.number)}';Phone.tab('keypad');App.open('phone')">📞</button>
          <button onclick="Messages.openThread('${esc(c.number)}_${esc(State.phoneData?.number||'')}','${esc(c.number)}','${esc(c.name)}');App.open('messages')">💬</button>
          <button onclick="Contacts.delete(${c.id})">🗑</button>
        </div>
      </li>`).join('');
  },

  filter: debounce(function(query) {
    const all = State.appData.contacts || [];
    const q   = query.toLowerCase();
    Contacts.render(q ? all.filter(c => c.name.toLowerCase().includes(q) || c.number.includes(q)) : all);
  }, 200),

  showAdd() { document.getElementById('add-contact-view').classList.remove('hidden'); },
  hideAdd() { document.getElementById('add-contact-view').classList.add('hidden'); },

  save() {
    const name   = document.getElementById('new-contact-name').value.trim();
    const number = document.getElementById('new-contact-number').value.trim();
    if (!name || !number) return;
    NUI.callback('saveContact', { name, number });
    document.getElementById('new-contact-name').value   = '';
    document.getElementById('new-contact-number').value = '';
    this.hideAdd();
    Toast.show({ title: 'Contact Saved', type: 'success' });
  },

  delete(id) {
    NUI.callback('deleteContact', { id });
    State.appData.contacts = (State.appData.contacts || []).filter(c => c.id !== id);
    this.render(State.appData.contacts);
  },
};

// ── Bank ─────────────────────────────────────────────────────────

const Bank = {
  render(data) {
    document.getElementById('bank-balance').textContent = `$${(data.bank || 0).toLocaleString()}`;
    document.getElementById('bank-cash').textContent    = `$${(data.cash || 0).toLocaleString()}`;
    this._renderInvoices(data.invoices || []);
  },

  showTransfer() {
    Bank._toggle('bank-transfer-panel');
  },

  showHistory() {
    NUI.callback('loadApp', { app: 'bank' });
    Bank._toggle('bank-history-panel');
  },

  showInvoices() {
    Bank._toggle('bank-invoices-panel');
  },

  _toggle(id) {
    ['bank-transfer-panel', 'bank-history-panel', 'bank-invoices-panel'].forEach(pid => {
      document.getElementById(pid).classList.toggle('hidden', pid !== id);
    });
  },

  transfer() {
    const target = document.getElementById('transfer-target').value.trim();
    const amount = parseFloat(document.getElementById('transfer-amount').value);
    const note   = document.getElementById('transfer-note').value.trim();
    if (!target || !amount || amount <= 0) return;
    NUI.callback('bankTransfer', { target, amount, note });
  },

  _renderInvoices(invoices) {
    const list = document.getElementById('invoices-list');
    if (!list) return;
    list.innerHTML = invoices.length
      ? invoices.map(inv => `
          <li style="padding:12px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:12px">
            <div style="flex:1">
              <div style="font-size:14px;color:var(--text-primary)">${esc(inv.note || 'Invoice')}</div>
              <div style="font-size:12px;color:var(--text-secondary)">Due: ${fmtDate(inv.due_at)}</div>
            </div>
            <div style="font-size:16px;color:var(--accent-red);font-weight:700">$${(inv.amount || 0).toLocaleString()}</div>
            <button onclick="Bank.payInvoice(${inv.id})" style="background:var(--accent-green);border:none;border-radius:8px;padding:8px 14px;color:#fff;cursor:pointer">Pay</button>
          </li>`).join('')
      : '<li style="padding:20px;text-align:center;color:var(--text-secondary)">No pending invoices</li>';
  },

  payInvoice(id) {
    NUI.callback('payInvoice', { invoiceId: id });
  },
};

// ── Crypto ────────────────────────────────────────────────────────

const Crypto = {
  onOpen() {
    NUI.callback('loadApp', { app: 'crypto' });
  },

  render(data) {
    this._renderPortfolio(data.holdings || [], data.prices || []);
    this._renderMarket(data.coins || [], data.prices || []);
  },

  _renderPortfolio(holdings, prices) {
    const el = document.getElementById('crypto-portfolio');
    if (!el) return;
    if (!holdings.length) { el.innerHTML = '<p style="padding:16px;color:var(--text-secondary)">No holdings</p>'; return; }

    el.innerHTML = '<h4 style="padding:12px 16px 4px;font-size:13px;color:var(--text-secondary);text-transform:uppercase;letter-spacing:1px">Your Holdings</h4>'
      + holdings.map(h => {
          const price = (prices.find(p => p.coin === h.coin) || {}).price || 0;
          const value = (h.amount * price).toFixed(2);
          return `<div class="crypto-row" onclick="Crypto.selectCoin('${esc(h.coin)}')">
            <span class="crypto-symbol">${esc(h.coin)}</span>
            <span class="crypto-name">${esc(h.coin)} · ${parseFloat(h.amount).toFixed(4)}</span>
            <span class="crypto-price">$${parseFloat(value).toLocaleString()}</span>
          </div>`;
        }).join('');
  },

  _renderMarket(coins, prices) {
    const el = document.getElementById('crypto-market');
    if (!el) return;
    el.innerHTML = '<h4 style="padding:12px 16px 4px;font-size:13px;color:var(--text-secondary);text-transform:uppercase;letter-spacing:1px">Market</h4>'
      + coins.map(c => {
          const priceRow = prices.find(p => p.coin === c.id) || {};
          const price    = priceRow.price || c.basePrice;
          const change   = ((price - c.basePrice) / c.basePrice * 100).toFixed(2);
          const dir      = change >= 0 ? 'up' : 'down';
          return `<div class="crypto-row" onclick="Crypto.selectCoin('${esc(c.id)}')">
            <span class="crypto-symbol">${esc(c.id)}</span>
            <span class="crypto-name">${esc(c.name)}</span>
            <span class="crypto-price">$${parseFloat(price).toLocaleString()}</span>
            <span class="crypto-change ${dir}">${change >= 0 ? '+' : ''}${change}%</span>
          </div>`;
        }).join('');
  },

  selectCoin(coin) {
    State.cryptoSelectedCoin = coin;
    const panel = document.getElementById('crypto-trade-panel');
    document.getElementById('crypto-trade-coin').textContent = `Trade ${coin}`;
    panel.classList.remove('hidden');
  },

  buy() {
    const amount = parseFloat(document.getElementById('crypto-trade-amount').value);
    if (!amount || amount <= 0 || !State.cryptoSelectedCoin) return;
    NUI.callback('buyCrypto', { coin: State.cryptoSelectedCoin, amount });
  },

  sell() {
    const amount = parseFloat(document.getElementById('crypto-trade-amount').value);
    if (!amount || amount <= 0 || !State.cryptoSelectedCoin) return;
    NUI.callback('sellCrypto', { coin: State.cryptoSelectedCoin, amount });
  },

  updatePrices(prices) {
    prices.forEach(p => {
      // Update rendered prices in-place
      document.querySelectorAll(`.crypto-row`).forEach(row => {
        const sym = row.querySelector('.crypto-symbol');
        if (sym && sym.textContent === p.coin) {
          const priceEl = row.querySelector('.crypto-price');
          if (priceEl) priceEl.textContent = `$${parseFloat(p.price).toLocaleString()}`;
        }
      });
    });
  },
};

// ── Gallery ───────────────────────────────────────────────────────

const Gallery = {
  selectedId: null,

  render(data) {
    const grid = document.getElementById('gallery-grid');
    if (!grid) return;
    grid.innerHTML = (data || []).map(p => `
      <div class="gallery-thumb" onclick="Gallery.openViewer(${p.id})">
        ${p.data ? `<img src="${p.data}" alt="${esc(p.caption || '')}" loading="lazy"/>` : '📷'}
      </div>`).join('');
  },

  openViewer(id) {
    const photo = (State.appData.gallery || []).find(p => p.id === id);
    if (!photo) return;
    this.selectedId = id;
    document.getElementById('photo-viewer-img').src = photo.data || '';
    document.getElementById('photo-viewer-caption').textContent = photo.caption || '';
    document.getElementById('photo-viewer').classList.remove('hidden');
  },

  closeViewer() {
    document.getElementById('photo-viewer').classList.add('hidden');
    this.selectedId = null;
  },

  share() {
    if (!this.selectedId) return;
    Toast.show({ title: 'Share', message: 'Send via MMS: open Messages and attach.', type: 'info' });
  },

  delete() {
    if (!this.selectedId) return;
    NUI.callback('deletePhoto', { id: this.selectedId });
    State.appData.gallery = (State.appData.gallery || []).filter(p => p.id !== this.selectedId);
    this.closeViewer();
    this.render(State.appData.gallery);
  },
};

// ── Camera ────────────────────────────────────────────────────────

const Camera = {
  canvas: null,
  ctx:    null,

  onOpen() {
    this.canvas = document.getElementById('camera-canvas');
    this.ctx    = this.canvas?.getContext('2d');
    // In FiveM, we render the GTA viewport; here we draw a placeholder
    if (this.ctx) {
      this.canvas.width  = 375;
      this.canvas.height = 450;
      this._drawViewfinder();
    }
  },

  _drawViewfinder() {
    if (!this.ctx) return;
    const w = this.canvas.width, h = this.canvas.height;
    this.ctx.fillStyle = '#111';
    this.ctx.fillRect(0, 0, w, h);
    // Rule-of-thirds grid
    this.ctx.strokeStyle = 'rgba(255,255,255,0.2)';
    this.ctx.lineWidth = 0.5;
    for (let i = 1; i < 3; i++) {
      this.ctx.beginPath(); this.ctx.moveTo(w/3*i, 0); this.ctx.lineTo(w/3*i, h); this.ctx.stroke();
      this.ctx.beginPath(); this.ctx.moveTo(0, h/3*i); this.ctx.lineTo(w, h/3*i); this.ctx.stroke();
    }
    // Focus square
    this.ctx.strokeStyle = 'rgba(255,255,255,0.5)';
    this.ctx.lineWidth = 1.5;
    const sq = 80;
    this.ctx.strokeRect(w/2-sq/2, h/2-sq/2, sq, sq);
  },

  switch() {
    Toast.show({ title: 'Camera', message: 'Front/rear switch toggled.', type: 'info' });
  },

  shoot() {
    if (!this.canvas) return;
    const flash = document.getElementById('camera-flash');
    flash.classList.add('flash');
    setTimeout(() => flash.classList.remove('flash'), 150);

    const base64 = this.canvas.toDataURL('image/jpeg', 0.8);
    const caption = `Photo ${new Date().toLocaleString()}`;

    NUI.callback('savePhoto', { base64, caption });

    // Add to local gallery
    State.appData.gallery = State.appData.gallery || [];
    State.appData.gallery.unshift({ id: Date.now(), data: base64, caption });
    Toast.show({ title: 'Photo saved', type: 'success' });
  },
};

// ── GPS ───────────────────────────────────────────────────────────

const GPS = {
  liveLocations: {},

  shareLocation() {
    const number = prompt('Share with (number):');
    if (number) {
      NUI.callback('shareLiveLocation', { target: number });
      Toast.show({ title: 'GPS Sharing', message: `Sharing with ${number}`, type: 'success' });
    }
  },

  stopShare() {
    NUI.callback('stopLiveLocation');
    Toast.show({ title: 'GPS Sharing', message: 'Stopped sharing location.', type: 'info' });
  },

  onLiveLocation(data) {
    this.liveLocations[data.number] = data;
    this._renderLiveList();
  },

  _renderLiveList() {
    const el = document.getElementById('gps-live-list');
    if (!el) return;
    el.innerHTML = Object.values(this.liveLocations).map(l => `
      <li style="padding:10px;border-bottom:1px solid var(--border);cursor:pointer"
          onclick="NUI.callback('setWaypoint',{x:${l.x},y:${l.y}})">
        📍 ${esc(l.name)} (${l.x.toFixed(1)}, ${l.y.toFixed(1)})
      </li>`).join('') || '<li style="padding:10px;color:var(--text-secondary)">No active shares</li>';
  },
};

// ── Marketplace ──────────────────────────────────────────────────

const Market = {
  render(data) {
    const grid = document.getElementById('market-grid');
    if (!grid) return;
    grid.innerHTML = (data || []).map(l => `
      <div class="market-card">
        <div class="market-card-img">${l.images && l.images[0] ? `<img src="${esc(l.images[0])}" alt=""/>` : '🛍️'}</div>
        <div class="market-card-body">
          <div class="market-card-title">${esc(l.title)}</div>
          <div class="market-card-price">$${(l.price || 0).toLocaleString()}</div>
          <div class="market-card-cat">${esc(l.category)}</div>
          <button onclick="Market.contact('${esc(l.seller_number)}','${esc(l.title)}')" style="margin-top:6px;background:var(--accent);border:none;border-radius:6px;padding:6px 10px;color:#fff;cursor:pointer;font-size:12px">Contact</button>
        </div>
      </div>`).join('') || '<p style="padding:20px;color:var(--text-secondary);grid-column:span 2">No listings found</p>';
  },

  filter() {
    const cat  = document.getElementById('market-cat').value;
    const data = State.appData.marketplace || [];
    this.render(cat ? data.filter(l => l.category === cat) : data);
  },

  showCreate()  { document.getElementById('market-create-panel').classList.remove('hidden'); },
  hideCreate()  { document.getElementById('market-create-panel').classList.add('hidden'); },

  create() {
    const title = document.getElementById('market-title').value.trim();
    const desc  = document.getElementById('market-desc').value.trim();
    const price = parseFloat(document.getElementById('market-price').value);
    const cat   = document.getElementById('market-category').value;
    if (!title || !price) return;
    NUI.callback('createListing', { title, description: desc, price, category: cat });
    this.hideCreate();
    Toast.show({ title: 'Listing Posted', type: 'success' });
  },

  contact(sellerNumber, title) {
    NUI.callback('contactSeller', { sellerNumber, title });
    Toast.show({ title: 'Message Sent', message: 'Opening chat…', type: 'success' });
    setTimeout(() => App.open('messages'), 500);
  },
};

// ── Email ─────────────────────────────────────────────────────────

const Email = {
  selectedId: null,

  render(data) {
    const list = document.getElementById('email-list');
    if (!list) return;
    list.innerHTML = (data || []).map(e => `
      <li class="email-item ${e.read ? '' : 'unread'}" onclick="Email.read(${e.id})">
        <div style="display:flex;justify-content:space-between">
          <span class="email-from">From: ${esc(e.from_number)}</span>
          <span class="email-time">${fmtDate(e.created_at)}</span>
        </div>
        <div class="email-subject">${esc(e.subject)}</div>
      </li>`).join('') || '<li style="padding:20px;text-align:center;color:var(--text-secondary)">No emails</li>';

    const unread = (data || []).filter(e => !e.read).length;
    const badge  = document.getElementById('badge-email');
    if (badge) {
      badge.textContent = unread || '';
      badge.classList.toggle('hidden', !unread);
    }
  },

  read(id) {
    const email = (State.appData.email || []).find(e => e.id === id);
    if (!email) return;
    this.selectedId = id;
    document.getElementById('email-read-subject').textContent = email.subject;
    document.getElementById('email-read-from').textContent    = `From: ${email.from_number}`;
    document.getElementById('email-read-body').textContent    = email.body;
    document.getElementById('email-read-view').classList.remove('hidden');
    email.read = true;
  },

  closeRead() {
    document.getElementById('email-read-view').classList.add('hidden');
    this.selectedId = null;
  },

  compose()       { document.getElementById('email-compose-view').classList.remove('hidden'); },
  closeCompose()  { document.getElementById('email-compose-view').classList.add('hidden'); },

  send() {
    const to      = document.getElementById('email-to').value.trim();
    const subject = document.getElementById('email-subject').value.trim();
    const body    = document.getElementById('email-body').value.trim();
    if (!to || !subject || !body) return;
    NUI.callback('sendEmail', { to, subject, body });
    this.closeCompose();
    Toast.show({ title: 'Email Sent', type: 'success' });
  },
};

// ── Social Media ─────────────────────────────────────────────────

function renderSocialFeed(feedId, posts, app) {
  const el = document.getElementById(feedId);
  if (!el) return;
  el.innerHTML = (posts || []).map(p => {
    const media = typeof p.media === 'string' ? JSON.parse(p.media || 'null') : p.media;
    return `<div class="social-post">
      <div class="post-header">
        <div class="post-avatar">${esc((p.display_name || '?').charAt(0))}</div>
        <div>
          <div class="post-name">${esc(p.display_name || 'Anonymous')}</div>
          <div class="post-time">${fmtDate(p.created_at)}</div>
        </div>
      </div>
      <div class="post-content">${esc(p.content)}</div>
      ${media?.url ? `<div class="post-media"><img src="${esc(media.url)}" alt=""/></div>` : ''}
      <div class="post-actions">
        <button id="like-${p.id}-${app}" onclick="likeSocial(${p.id},'${app}',this)">♥ ${p.likes || 0}</button>
        <button onclick="replyToPost('${esc(p.display_name)}')">💬 Reply</button>
        <button onclick="deleteSocial(${p.id},'${app}')">🗑</button>
      </div>
    </div>`;
  }).join('') || '<p style="padding:20px;text-align:center;color:var(--text-secondary)">No posts yet</p>';
}

function likeSocial(id, app, btn) {
  NUI.callback('likeSocialPost', { postId: id, app });
  const txt = btn.textContent.replace(/\d+/, n => parseInt(n) + 1);
  btn.textContent = txt;
  btn.classList.add('liked');
}

function deleteSocial(id, app) {
  NUI.callback('deleteSocialPost', { postId: id, app });
  Toast.show({ title: 'Post deleted', type: 'success' });
}

function replyToPost(name) {
  Toast.show({ title: 'Reply', message: `Reply to @${name} via Messages`, type: 'info' });
}

// Catiter
const Catiter = {
  compose() {
    const panel = document.getElementById('catiter-compose');
    panel.classList.toggle('hidden');
  },

  post() {
    const text = document.getElementById('catiter-text').value.trim();
    if (!text) return;
    NUI.callback('postTweet', { content: text });
    document.getElementById('catiter-text').value = '';
    this.compose(); // hide compose
    Toast.show({ title: 'Posted on Catiter', type: 'success' });
  },
};

document.getElementById('catiter-text')?.addEventListener('input', function() {
  const remain = 280 - this.value.length;
  document.getElementById('catiter-char-count').textContent = remain;
  document.getElementById('catiter-char-count').style.color = remain < 20 ? 'var(--accent-red)' : 'var(--text-secondary)';
});

// InstaPic
const InstaPic = {
  selectedPhoto: null,

  compose()       { document.getElementById('instapic-compose').classList.remove('hidden'); },
  closeCompose()  { document.getElementById('instapic-compose').classList.add('hidden'); },

  pickPhoto() {
    const photos = State.appData.gallery || [];
    if (!photos.length) { Toast.show({ title: 'No photos', message: 'Take a photo first.', type: 'info' }); return; }
    this.selectedPhoto = photos[0].data;
    const img = document.getElementById('instapic-preview-img');
    if (img) img.src = this.selectedPhoto;
    document.getElementById('instapic-preview').classList.remove('hidden');
  },

  post() {
    const caption = document.getElementById('instapic-caption').value.trim();
    NUI.callback('postInstaPic', { caption, media: this.selectedPhoto ? { url: this.selectedPhoto } : null });
    this.closeCompose();
    Toast.show({ title: 'Posted on InstaPic', type: 'success' });
  },
};

// FlirtDate
const FlirtDate = {
  profiles: [],
  index:    0,

  onOpen() {
    this.profiles = State.appData.flirtdate || [];
    this.index    = 0;
    this._showCard();
  },

  _showCard() {
    if (this.index >= this.profiles.length) {
      document.getElementById('flirt-name').textContent = "You've seen everyone!";
      document.getElementById('flirt-bio').textContent  = '';
      return;
    }
    const p = this.profiles[this.index];
    document.getElementById('flirt-name').textContent = p.display_name || 'Unknown';
    document.getElementById('flirt-bio').textContent  = p.bio || '';
    const photo = document.getElementById('flirt-photo');
    if (p.photos) {
      const photos = typeof p.photos === 'string' ? JSON.parse(p.photos) : p.photos;
      if (photos?.url) photo.style.backgroundImage = `url(${photos.url})`;
    }
  },

  like() {
    const p = this.profiles[this.index];
    if (p) Toast.show({ title: '❤️ Liked', message: p.display_name, type: 'success' });
    this._next();
  },

  nope() { this._next(); },

  superLike() {
    const p = this.profiles[this.index];
    if (p) Toast.show({ title: '⭐ Super Like!', message: p.display_name, type: 'success' });
    this._next();
  },

  _next() {
    const card = document.getElementById('flirt-card');
    card.style.transform = 'translateX(120%) rotate(20deg)';
    card.style.opacity   = '0';
    setTimeout(() => {
      card.style.transform = '';
      card.style.opacity   = '';
      this.index++;
      this._showCard();
    }, 300);
  },
};

// ── Dark Web ──────────────────────────────────────────────────────

const DarkWeb = {
  onOpen() {
    this.tab('market');
    this._renderMarket(State.appData.darkweb?.listings || []);
    this._fillItemSelect();
    if (State.phoneData?.imei) {
      document.getElementById('imei-current-display').textContent = `IMEI: ${State.phoneData.imei}`;
    }
  },

  tab(name) {
    document.querySelectorAll('#app-darkweb .tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('#app-darkweb .tab-content').forEach(c => c.classList.remove('active'));
    const tabs = { market: 'dw-market', chat: 'dw-chat', imei: 'dw-imei' };
    const btnIndex = { market: 0, chat: 1, imei: 2 };
    const btns = document.querySelectorAll('#app-darkweb .tab-btn');
    if (btns[btnIndex[name]]) btns[btnIndex[name]].classList.add('active');
    const tab = document.getElementById(tabs[name]);
    if (tab) tab.classList.add('active');
  },

  _renderMarket(listings) {
    const el = document.getElementById('dark-market-list');
    if (!el) return;
    el.innerHTML = (listings || []).map(l => `
      <div class="dark-listing">
        <span class="dark-listing-name">${esc(l.item_label)}</span>
        <span class="dark-listing-price">$${(l.price || 0).toLocaleString()}</span>
        <button onclick="DarkWeb.buy(${l.id})">Buy</button>
      </div>`).join('') || '<p style="color:#666;font-family:monospace;padding:12px">No listings available</p>';
  },

  _fillItemSelect() {
    const sel = document.getElementById('dw-item-select');
    if (!sel) return;
    const blacklist = State.appData.darkweb?.blacklist || [];
    sel.innerHTML = blacklist.map(i => `<option value="${esc(i.item)}">${esc(i.label)} (~$${i.price})</option>`).join('');
  },

  buy(id) {
    NUI.callback('darkWebBuy', { itemId: id });
  },

  showSell() { document.getElementById('dw-sell-panel').classList.remove('hidden'); },
  hideSell() { document.getElementById('dw-sell-panel').classList.add('hidden'); },

  sell() {
    const item  = document.getElementById('dw-item-select').value;
    const price = parseFloat(document.getElementById('dw-item-price').value);
    if (!item || !price) return;
    NUI.callback('darkWebSell', { itemName: item, price });
    this.hideSell();
    Toast.show({ title: 'Dark Web', message: 'Listing posted.', type: 'success' });
  },

  sendChat() {
    const to  = document.getElementById('dark-chat-to').value.trim();
    const msg = document.getElementById('dark-chat-msg').value.trim();
    if (!to || !msg) return;
    NUI.callback('sendDarkChat', { to, message: msg });
    this._appendDarkMsg(`me → ${to}`, msg);
    document.getElementById('dark-chat-msg').value = '';
  },

  _appendDarkMsg(from, text) {
    const el = document.getElementById('dark-chat-messages');
    if (!el) return;
    const div = document.createElement('div');
    div.className = 'dark-msg';
    div.innerHTML = `<span class="from">${esc(from)}:</span> <span class="text">${esc(text)}</span>`;
    el.appendChild(div);
    el.scrollTop = el.scrollHeight;
  },

  startIMEIClone() {
    NUI.callback('startIMEIClone');
  },

  launchMinigame() {
    document.getElementById('imei-clone-info').classList.add('hidden');
    document.getElementById('imei-minigame').classList.remove('hidden');

    const solution = Array.from({ length: 6 }, () => Math.floor(Math.random() * 10)).join('');
    let buffer     = '';
    const display  = document.getElementById('imei-keypad-display');

    display.textContent = '_ _ _ _ _ _';

    const numpad = document.getElementById('imei-numpad');
    const digits = [0,1,2,3,4,5,6,7,8,9,'DEL','OK'];
    numpad.innerHTML = digits.map(d => `<button onclick="DarkWeb._mgKey('${d}')">${d}</button>`).join('');

    // Timer
    const fill     = document.getElementById('imei-timer-fill');
    const duration = 30;
    let elapsed    = 0;
    const timerInt = setInterval(() => {
      elapsed++;
      const pct = (1 - elapsed / duration) * 100;
      fill.style.width = `${pct}%`;
      if (pct < 30) fill.style.background = '#e74c3c';
      if (elapsed >= duration) {
        clearInterval(timerInt);
        DarkWeb._mgFinish(false);
      }
    }, 1000);

    DarkWeb._mgBuffer   = '';
    DarkWeb._mgSolution = solution;
    DarkWeb._mgTimer    = timerInt;
    DarkWeb._mgDisplay  = display;
  },

  _mgKey(key) {
    if (key === 'DEL') {
      DarkWeb._mgBuffer = DarkWeb._mgBuffer.slice(0, -1);
    } else if (key === 'OK') {
      clearInterval(DarkWeb._mgTimer);
      DarkWeb._mgFinish(DarkWeb._mgBuffer === DarkWeb._mgSolution);
      return;
    } else if (DarkWeb._mgBuffer.length < 6) {
      DarkWeb._mgBuffer += key;
      if (DarkWeb._mgBuffer.length === 6) {
        clearInterval(DarkWeb._mgTimer);
        DarkWeb._mgFinish(DarkWeb._mgBuffer === DarkWeb._mgSolution);
        return;
      }
    }
    const filled = DarkWeb._mgBuffer.padEnd(6, '_').split('').join(' ');
    DarkWeb._mgDisplay.textContent = filled;
  },

  _mgFinish(success) {
    document.getElementById('imei-minigame').classList.add('hidden');
    document.getElementById('imei-clone-info').classList.remove('hidden');
    NUI.callback('imeiCloneResult', { success });
  },
};

// ── MDT ───────────────────────────────────────────────────────────

const MDT = {
  onOpen() {
    NUI.callback('loadApp', { app: 'mdt' });
  },

  onData(data) {
    if (!data.access) {
      document.getElementById('mdt-panel').classList.add('hidden');
      document.getElementById('mdt-no-access').classList.remove('hidden');
    }
  },

  tab(name) {
    document.querySelectorAll('#app-mdt .tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('#app-mdt .tab-content').forEach(c => c.classList.remove('active'));
    const tabs = { imei: 'mdt-imei', persons: 'mdt-persons', dispatch: 'mdt-dispatch' };
    const btnIdx = { imei: 0, persons: 1, dispatch: 2 };
    const btns = document.querySelectorAll('#app-mdt .tab-btn');
    if (btns[btnIdx[name]]) btns[btnIdx[name]].classList.add('active');
    const tab = document.getElementById(tabs[name]);
    if (tab) tab.classList.add('active');
  },

  lookupIMEI() {
    const imei = document.getElementById('mdt-imei-input').value.trim();
    if (!imei) return;
    NUI.callback('mdtLookupIMEI', { imei });
  },

  renderIMEIResult(data) {
    const el = document.getElementById('mdt-imei-result');
    if (!el) return;
    if (!data.phone) { el.innerHTML = '<p>No record found.</p>'; return; }
    const p = data.phone;
    el.innerHTML = `
      <div class="mdt-row"><span class="mdt-label">IMEI</span><span class="mdt-value ${p.imei_flagged ? 'mdt-flagged' : ''}">${esc(p.imei)} ${p.imei_flagged ? '🚨 FLAGGED' : ''}</span></div>
      <div class="mdt-row"><span class="mdt-label">Model</span><span class="mdt-value">${esc(p.model)}</span></div>
      <div class="mdt-row"><span class="mdt-label">Owner</span><span class="mdt-value">${esc(p.owner)}</span></div>
      <div class="mdt-row"><span class="mdt-label">Serial</span><span class="mdt-value">${esc(p.serial)}</span></div>
      <h4 style="margin-top:12px;margin-bottom:6px;font-size:13px;color:var(--text-secondary)">History</h4>
      ${(data.history || []).map(h => `<div class="mdt-row"><span class="mdt-label">${fmtDate(h.created_at)}</span><span class="mdt-value">${esc(h.action)}</span></div>`).join('')}
      <button onclick="MDT.flagIMEI('${esc(p.imei)}')" style="margin-top:8px;background:var(--accent-red);border:none;border-radius:6px;padding:8px 14px;color:#fff;cursor:pointer">Flag IMEI</button>`;
  },

  flagIMEI(imei) {
    const reason = prompt('Reason for flagging:') || 'Stolen';
    NUI.callback('mdtFlagIMEI', { imei, reason });
  },

  lookupPerson() {
    Toast.show({ title: 'MDT', message: 'Person lookup requires character DB integration.', type: 'info' });
  },
};

// ── Taxi ──────────────────────────────────────────────────────────

const Taxi = {
  request() {
    const dest = document.getElementById('taxi-dest').value.trim();
    NUI.callback('requestRide', { dest });
    Toast.show({ title: 'Ride Requested', message: 'Looking for a driver…', type: 'success' });
    document.getElementById('taxi-dest').value = '';
  },

  renderRequests(data) {
    const list = document.getElementById('taxi-requests-list');
    if (!list) return;
    list.innerHTML = (data || []).map(r => `
      <li class="taxi-request-item">
        <span>📍 ${r.pickup_x?.toFixed(0)}, ${r.pickup_y?.toFixed(0)} ${r.dest ? `→ ${esc(r.dest)}` : ''}</span>
        <button onclick="Taxi.accept(${r.id})">Accept</button>
      </li>`).join('') || '<li style="color:var(--text-secondary)">No requests</li>';
  },

  accept(id) { NUI.callback('acceptRide', { rideId: id }); },
};

// ── Music ─────────────────────────────────────────────────────────

const Music = {
  playlist: [
    { title: 'Los Santos Radio',    artist: 'LS FM',     duration: '3:22' },
    { title: 'Night Drive',         artist: 'Neon Drift', duration: '4:05' },
    { title: 'Gangsta Paradise',    artist: 'Coolio',     duration: '4:02' },
    { title: 'Welcome to the City', artist: 'RP Beats',   duration: '2:58' },
  ],
  current: -1,
  playing: false,

  onOpen() {
    this._renderPlaylist();
  },

  _renderPlaylist() {
    const list = document.getElementById('music-playlist');
    if (!list) return;
    list.innerHTML = this.playlist.map((t, i) => `
      <li class="playlist-item ${i === this.current ? 'playing' : ''}" onclick="Music.play(${i})">
        <span class="playlist-num">${i === this.current && this.playing ? '♪' : i + 1}</span>
        <span class="playlist-title">${esc(t.title)}</span>
        <span class="playlist-dur">${t.duration}</span>
      </li>`).join('');
  },

  play(i) {
    this.current = i;
    this.playing = true;
    const t = this.playlist[i];
    document.getElementById('music-title').textContent  = t.title;
    document.getElementById('music-artist').textContent = t.artist;
    document.getElementById('btn-play-pause').textContent = '⏸';
    this._renderPlaylist();
    DynamicIsland.show('music', `🎵 ${t.title}`);
  },

  togglePlay() {
    if (this.current < 0) { this.play(0); return; }
    this.playing = !this.playing;
    document.getElementById('btn-play-pause').textContent = this.playing ? '⏸' : '▶';
    if (this.playing) DynamicIsland.show('music', `🎵 ${this.playlist[this.current]?.title}`);
    else DynamicIsland.hide();
  },

  prev() { if (this.current > 0) this.play(this.current - 1); },
  next() { if (this.current < this.playlist.length - 1) this.play(this.current + 1); },
};

// ── Settings ──────────────────────────────────────────────────────

const Settings = {
  applyTheme(theme) {
    State.theme = theme;
    document.body.classList.toggle('theme-light', theme === 'light');
  },

  applyWallpaper(name) {
    State.currentWallpaper = name;
    const wallpapers = {
      default:  'linear-gradient(160deg,#1a1a2e,#16213e,#0f3460)',
      city:     'linear-gradient(160deg,#0a0a1a,#1a1a3a)',
      mountain: 'linear-gradient(160deg,#1a3a2e,#0a2a1a)',
      beach:    'linear-gradient(160deg,#1a3a5e,#0a2a4e)',
    };
    const bg = wallpapers[name] || wallpapers.default;
    document.getElementById('home-wallpaper').style.background    = bg;
    document.getElementById('lock-wallpaper').style.background    = bg;
  },

  toggleAirplane(enabled) {
    NUI.callback('toggleAirplaneMode', { enabled });
  },

  save() {
    const theme      = document.getElementById('s-theme').value;
    const wallpaper  = document.getElementById('s-wallpaper').value;
    const ringtone   = document.getElementById('s-ringtone').value;
    const pin        = document.getElementById('s-pin').value.trim();
    const duressPin  = document.getElementById('s-duress-pin').value.trim();

    this.applyTheme(theme);
    this.applyWallpaper(wallpaper);

    NUI.callback('saveSettings', { theme, wallpaper, ringtone, pin: pin || undefined, duressPin: duressPin || undefined });
    Toast.show({ title: 'Settings saved', type: 'success' });
  },

  remoteLock() {
    const number = document.getElementById('s-remote-number').value.trim();
    if (!number) return;
    NUI.callback('remoteLock', { targetNumber: number });
    Toast.show({ title: 'Remote Lock', message: `Sent lock command to ${number}`, type: 'success' });
  },

  findMyPhone() {
    Toast.show({ title: 'Find My Phone', message: 'Locating your device…', type: 'info' });
    NUI.callback('findMyPhone', {});
  },

  cloudBackup()  { NUI.callback('cloudBackup'); },
  cloudRestore() { NUI.callback('cloudRestore'); },

  dataTransfer() {
    NUI.callback('requestNearby');
    Toast.show({ title: 'Data Transfer', message: 'Searching for nearby phones…', type: 'info' });
  },
};

// ── Dynamic Island ────────────────────────────────────────────────

const DynamicIsland = {
  timeout: null,

  show(type, content) {
    const di = document.getElementById('dynamic-island');
    const ct = document.getElementById('di-content');
    di.className = `di-${type}`;
    ct.textContent = content;
    clearTimeout(this.timeout);
    if (type !== 'call' && type !== 'music') {
      this.timeout = setTimeout(() => this.hide(), 5000);
    }
  },

  hide() {
    const di = document.getElementById('dynamic-island');
    di.className = 'di-idle';
    document.getElementById('di-content').textContent = '';
  },
};

// ── Main NUI message handler ──────────────────────────────────────

window.addEventListener('message', ({ data }) => {
  if (!data || !data.action) return;
  const { action, data: d } = data;

  switch (action) {

    case 'open': {
      const el = document.getElementById('phone-container');
      el.classList.remove('hidden');
      el.classList.add('open');

      State.open        = true;
      State.phoneData   = d || {};
      State.battery     = d?.battery ?? 100;
      State.signal      = d?.signal  ?? 3;
      State.airplaneMode = d?.airplaneMode ?? false;

      updateBatteryUI(State.battery, false);
      updateSignalUI(State.signal);

      // Apply saved theme / wallpaper
      if (d?.theme)     Settings.applyTheme(d.theme);
      if (d?.wallpaper) Settings.applyWallpaper(d.wallpaper);

      // Show lock screen if phone has a PIN or fingerprint model
      if (!State.unlocked) {
        document.getElementById('screen-lock').classList.remove('hidden');
        document.getElementById('screen-lock').classList.add('active');
        document.getElementById('screen-home').classList.add('hidden');
        // Auto-unlock if no PIN set and no fingerprint model
        if (!d?.hasPin && !Config.PhoneModels?.[d?.model]?.fingerprint) {
          Auth.unlock();
        }
      } else {
        document.getElementById('screen-home').classList.remove('hidden');
        document.getElementById('screen-home').classList.add('active');
      }
      break;
    }

    case 'close': {
      const el = document.getElementById('phone-container');
      el.classList.add('hidden');
      el.classList.remove('open');
      State.open = false;
      break;
    }

    case 'phoneData':
      State.phoneData = { ...State.phoneData, ...d };
      // Update settings panel
      const imeiEl = document.getElementById('settings-imei-val');
      const serEl  = document.getElementById('settings-serial-val');
      const numEl  = document.getElementById('settings-number-val');
      if (imeiEl) imeiEl.textContent = d.imei || '—';
      if (serEl)  serEl.textContent  = d.serial || '—';
      if (numEl)  numEl.textContent  = d.number || '—';
      if (document.getElementById('imei-current-display'))
        document.getElementById('imei-current-display').textContent = `IMEI: ${d.imei || '—'}`;
      break;

    case 'appData':
      if (d.app) {
        State.appData[d.app] = d.data;

        // Dispatch to app modules
        if (d.app === 'contacts')   Contacts.render(d.data);
        if (d.app === 'callhistory') Phone._renderHistory(d.data);
        if (d.app === 'bank')       Bank.render(d.data);
        if (d.app === 'crypto')     Crypto.render(d.data);
        if (d.app === 'gallery')    Gallery.render(d.data);
        if (d.app === 'marketplace') Market.render(d.data);
        if (d.app === 'email')      Email.render(d.data);
        if (d.app === 'catiter')    renderSocialFeed('catiter-feed', d.data, 'catiter');
        if (d.app === 'instapic')   renderSocialFeed('instapic-feed', d.data, 'instapic');
        if (d.app === 'tiktok')     renderSocialFeed('tiktok-feed', d.data, 'tiktok');
        if (d.app === 'flirtdate')  FlirtDate.onOpen();
        if (d.app === 'darkweb')    DarkWeb.onOpen();
        if (d.app === 'mdt')        MDT.onData(d.data);
        if (d.app === 'messages')   Messages._renderThreadList(d.data);
        if (d.app === 'garage')     renderGarage(d.data);
        if (d.app === 'newMessage') Messages.onNewMessage(d.data);
        if (d.app === 'darkChat')   DarkWeb._appendDarkMsg(d.data.from, d.data.message);
        if (d.app === 'mdtIMEIResult') MDT.renderIMEIResult(d.data);
        if (d.app === 'findMyPhone')   handleFindMyPhone(d.data);
      }
      break;

    case 'batteryUpdate':
      State.battery = d.battery;
      updateBatteryUI(d.battery, d.charging);
      break;

    case 'signalUpdate':
      State.signal      = d.signal;
      State.airplaneMode = d.airplaneMode ?? State.airplaneMode;
      updateSignalUI(d.signal);
      break;

    case 'incomingCall':
      Phone.showIncoming(d.callId, d.number, d.name);
      break;

    case 'callConnected':
      Phone.onCallConnected(d.callId);
      break;

    case 'callEnded':
      Phone.onCallEnded(d.callId, d.reason);
      break;

    case 'callUpdate':
      if (d.speaker !== undefined) {
        document.getElementById('btn-speaker').classList.toggle('active', d.speaker);
      }
      break;

    case 'fingerprintResult':
      // Used for both fingerprint and PIN
      Auth.onFingerprintResult(d.success);
      Auth.onPINResult(d.success);
      break;

    case 'notify':
      Toast.show({ title: d.title || '', message: d.message || d.message, type: d.type || 'info' });
      break;

    case 'pushNotification':
      Toast.show(d);
      // Update badges
      if (d.type === 'message') {
        const b = document.getElementById('badge-messages');
        if (b) { b.textContent = parseInt(b.textContent || '0') + 1; b.classList.remove('hidden'); }
      }
      if (d.type === 'call') {
        Phone.showIncoming(d.callId, d.number || d.message, d.title);
      }
      break;

    case 'liveLocation':
      GPS.onLiveLocation(d);
      break;

    case 'dynamicIsland':
      DynamicIsland.show(d.type, d.data?.message || d.data?.title || '');
      break;

    case 'remoteLock':
      Auth.lock();
      State.unlocked = false;
      break;

    case 'phoneDamaged':
      document.getElementById('cracked-overlay').classList.remove('hidden');
      break;

    case 'duressWipe':
      State.appData = {};
      Toast.show({ title: 'Phone data wiped', type: 'error' });
      break;

    case 'dataTransferRequest':
      Toast.show({
        title:   `📲 Transfer Request`,
        message: `${d.fromName} wants to transfer data. Tap to accept.`,
        type:    'info',
      });
      // Auto-accept for demo; in production show confirm dialog
      setTimeout(() => NUI.callback('acceptDataTransfer', { transferId: d.transferId }), 3000);
      break;

    case 'dataTransferProgress': {
      const pct = d.progress;
      DynamicIsland.show('transfer', `⬇️ Transfer ${pct}%`);
      break;
    }

    case 'dataTransferComplete':
      DynamicIsland.hide();
      Toast.show({ title: 'Transfer Complete', type: 'success' });
      break;

    case 'nearbyPlayers': {
      // Show picker for data transfer target
      if (d.players?.length) {
        const names = d.players.map((p, i) => `${i + 1}. ${p.name}`).join('\n');
        const choice = parseInt(prompt(`Nearby phones:\n${names}\nEnter number:`)) - 1;
        if (d.players[choice]) {
          NUI.callback('initiateDataTransfer', { targetServerId: d.players[choice].id });
        }
      } else {
        Toast.show({ title: 'No nearby phones', type: 'info' });
      }
      break;
    }

    case 'startMinigame':
      if (d.type === 'imei_clone') DarkWeb.launchMinigame();
      break;

    case 'cryptoPriceUpdate':
      Crypto.updatePrices(d);
      break;

    case 'newSocialPost':
      if (d.app === 'catiter')  NUI.callback('loadApp', { app: 'catiter' });
      if (d.app === 'instapic') NUI.callback('loadApp', { app: 'instapic' });
      break;
  }
});

// ── Helper: Garage ────────────────────────────────────────────────

function renderGarage(vehicles) {
  const list = document.getElementById('garage-list');
  if (!list) return;
  list.innerHTML = (vehicles || []).map(v => `
    <li class="garage-item">
      <span class="garage-icon">🚗</span>
      <div class="garage-info">
        <div class="garage-plate">${esc(v.plate || v.mods?.plate || '???')}</div>
        <div class="garage-model">${esc(v.model || 'Vehicle')}</div>
      </div>
      <button onclick="NUI.callback('retrieveVehicle',{plate:'${esc(v.plate || '')}'})"  >Retrieve</button>
    </li>`).join('') || '<li style="padding:20px;text-align:center;color:var(--text-secondary)">No vehicles</li>';
}

// ── Helper: Find My Phone ─────────────────────────────────────────

function handleFindMyPhone(data) {
  if (!data) return;
  Toast.show({ title: 'Device Found', message: `Coords: ${data.x?.toFixed(0)}, ${data.y?.toFixed(0)}`, type: 'success' });
  NUI.callback('setWaypoint', { x: data.x, y: data.y });
}

// ── Keyboard listeners ────────────────────────────────────────────

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') NUI.callback('closePhone');
});

// ── Prevent context menu in phone UI ─────────────────────────────
document.addEventListener('contextmenu', e => e.preventDefault());

// ── DOMContentLoaded init ─────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
  updateClock();
  // Ensure phone starts hidden
  document.getElementById('phone-container').classList.add('hidden');
});
