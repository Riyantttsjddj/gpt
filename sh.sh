#!/bin/bash

echo "[*] Membersihkan instalasi sebelumnya..."
systemctl stop chatgpt-mini 2>/dev/null
systemctl disable chatgpt-mini 2>/dev/null
rm -rf /opt/chatgpt-mini-full
rm -f /etc/systemd/system/chatgpt-mini.service

echo "[*] Update & install dependensi..."
apt update -y
apt install -y nodejs npm curl

echo "[*] Setup folder project..."
mkdir -p /opt/chatgpt-mini-full
cd /opt/chatgpt-mini-full

echo "[*] Inisialisasi project Node.js..."
npm init -y
npm install express express-session body-parser

echo "[*] Membuat penyimpanan memori chat menggunakan file JSON (data.json)..."
cat <<'EOF' > data.js
const fs = require('fs');
const path = require('path');
const dataFile = path.join(__dirname, 'data.json');

function loadData() {
  if (!fs.existsSync(dataFile)) fs.writeFileSync(dataFile, '{}');
  return JSON.parse(fs.readFileSync(dataFile, 'utf8'));
}

function saveData(data) {
  fs.writeFileSync(dataFile, JSON.stringify(data, null, 2));
}

module.exports = { loadData, saveData };
EOF

echo "[*] Membuat server Express..."
cat <<'EOF' > server.js
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const path = require('path');
const { loadData, saveData } = require('./data');

const app = express();
const PORT = 3000;

app.use(express.static(__dirname));
app.use(bodyParser.urlencoded({ extended: false }));
app.use(bodyParser.json());

app.use(session({
  secret: 'secret123',
  resave: false,
  saveUninitialized: true
}));

function auth(req, res, next) {
  if (req.session.user) next();
  else res.redirect('/login.html');
}

app.get('/', auth, (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.post('/login', (req, res) => {
  const { username } = req.body;
  if (username) {
    req.session.user = username;
    const db = loadData();
    if (!db[username]) db[username] = { chats: [] };
    saveData(db);
    res.redirect('/');
  } else {
    res.send('Login gagal. <a href="/login.html">Coba lagi</a>');
  }
});

app.post('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login.html');
});

app.get('/history', auth, (req, res) => {
  const db = loadData();
  const user = req.session.user;
  const chats = (db[user] && db[user].chats) || [];
  res.json(chats.slice(-100));
});

app.post('/chat', auth, (req, res) => {
  const user = req.session.user;
  const msg = req.body.message;
  const db = loadData();
  if (!db[user]) db[user] = { chats: [] };
  db[user].chats.push({ q: msg, a: null, timestamp: Date.now() });
  saveData(db);
  res.json({ prompt: msg });
});

app.post('/save_reply', auth, (req, res) => {
  const { question, answer } = req.body;
  const user = req.session.user;
  const db = loadData();
  if (!db[user]) db[user] = { chats: [] };
  for (let i = db[user].chats.length - 1; i >= 0; i--) {
    if (db[user].chats[i].q === question && !db[user].chats[i].a) {
      db[user].chats[i].a = answer;
      break;
    }
  }
  saveData(db);
  res.json({ status: 'ok' });
});

app.post('/clear', auth, (req, res) => {
  const db = loadData();
  const user = req.session.user;
  if (db[user]) db[user].chats = [];
  saveData(db);
  res.json({ status: 'cleared' });
});

app.listen(PORT, () => {
  console.log(`Server berjalan di http://0.0.0.0:${PORT}`);
});
EOF

echo "[*] Membuat halaman login..."
cat <<'EOF' > login.html
<!DOCTYPE html>
<html>
<head><title>Login</title></head>
<body>
  <h2>Login ChatGPT Mini</h2>
  <form action="/login" method="post">
    Username: <input name="username" required><br>
    Password: <input name="password" type="password"><br>
    <button type="submit">Login</button>
  </form>
</body>
</html>
EOF

echo "[*] Membuat halaman utama Chat..."
cat <<'EOF' > index.html
<!DOCTYPE html>
<html>
<head>
  <title>ChatGPT Mini</title>
  <script src="https://js.puter.com/v2/"></script>
  <style>
    body { font-family: sans-serif; margin: 0; padding: 0; background: #f9f9f9; }
    #container { max-width: 800px; margin: auto; padding: 20px; }
    .message { margin-bottom: 20px; }
    .user { font-weight: bold; }
    pre { background: #eee; padding: 10px; border-radius: 8px; white-space: pre-wrap; position: relative; }
    .copy-btn { position: absolute; top: 10px; right: 10px; background: #ddd; border: none; cursor: pointer; }
    #controls { margin-top: 20px; display: flex; gap: 10px; }
    #msg { flex: 1; padding: 10px; width: 100%; box-sizing: border-box; }
  </style>
</head>
<body>
  <div id="container">
    <h2>ChatGPT Mini</h2>
    <form action="/logout" method="post"><button type="submit">Logout</button></form>
    <button onclick="clearChat()">Hapus Semua Chat</button>
    <div id="history"></div>
    <div id="controls">
      <input id="msg" placeholder="Tulis pertanyaan...">
      <button onclick="send()">Kirim</button>
    </div>
  </div>

  <script>
    fetch('/history').then(r => r.json()).then(data => {
      for (const chat of data) append(chat.q, chat.a);
    });

    function escapeHtml(text) {
      return text.replace(/[&<>"']/g, (m) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
      })[m]);
    }

    function append(q, a) {
      const div = document.getElementById('history');
      const item = document.createElement('div');
      item.className = 'message';

      let answerHTML = '';
      if (a) {
        answerHTML = `<pre>${escapeHtml(a)}<button class="copy-btn" onclick="copyToClipboard(this)">Salin</button></pre>`;
      } else {
        answerHTML = `<pre><i>Menunggu jawaban...</i></pre>`;
      }

      item.innerHTML = `<div class="user">You:</div><div>${escapeHtml(q)}</div>${answerHTML}`;
      div.appendChild(item);
      div.scrollTop = div.scrollHeight;
    }

    function send() {
      const input = document.getElementById('msg');
      const msg = input.value.trim();
      if (!msg) return;
      input.value = '';
      append(msg, null);

      fetch('/chat', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: msg })
      }).then(r => r.json()).then(data => {
        puter.ai.chat(data.prompt).then(reply => {
          append(msg, reply);
          fetch('/save_reply', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ question: msg, answer: reply })
          });
        });
      });
    }

    function clearChat() {
      if (!confirm('Yakin ingin hapus semua chat?')) return;
      fetch('/clear', { method: 'POST' }).then(() => {
        document.getElementById('history').innerHTML = '';
      });
    }

    function copyToClipboard(btn) {
      const text = btn.parentNode.innerText.replace('Salin', '').trim();
      navigator.clipboard.writeText(text);
      alert('Disalin!');
    }
  </script>
</body>
</html>
EOF

echo "[*] Membuat systemd service..."
cat <<EOF > /etc/systemd/system/chatgpt-mini.service
[Unit]
Description=ChatGPT Mini with Puter.js
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/chatgpt-mini-full/server.js
Restart=always
User=root
Environment=NODE_ENV=production
WorkingDirectory=/opt/chatgpt-mini-full

[Install]
WantedBy=multi-user.target
EOF

echo "[*] Menjalankan service..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable chatgpt-mini
systemctl start chatgpt-mini

IP=$(curl -s ifconfig.me)
echo "========================================="
echo "ChatGPT Mini aktif!"
echo "Akses di: http://$IP:3000/login.html"
echo "========================================="
