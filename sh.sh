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

echo "[*] Membuat server Express dan manajemen chat dengan file JSON..."

cat <<'EOF' > server.js
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;

const DATA_FILE = path.join(__dirname, 'chat_data.json');

// Load data chat dari file, atau buat default
function loadData() {
  if (!fs.existsSync(DATA_FILE)) return {};
  try {
    const raw = fs.readFileSync(DATA_FILE);
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

// Simpan data chat ke file
function saveData(data) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
}

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
  const { username, password } = req.body;
  // Simple user auth: simpan user di file juga
  let data = loadData();
  if (data.users && data.users[username] && data.users[username].password === password) {
    req.session.user = username;
    res.redirect('/');
  } else {
    res.send('Login gagal. <a href="/login.html">Coba lagi</a>');
  }
});

app.post('/register', (req, res) => {
  const { username, password } = req.body;
  let data = loadData();
  data.users = data.users || {};
  if (data.users[username]) {
    res.send('Username sudah terdaftar. <a href="/login.html">Login</a>');
  } else {
    data.users[username] = { password };
    data.chats = data.chats || {};
    data.chats[username] = [];
    saveData(data);
    res.send('Pendaftaran berhasil. <a href="/login.html">Login</a>');
  }
});

app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login.html');
});

// Endpoint chat: simpan pertanyaan dan jawaban (balasan)
app.post('/chat', auth, (req, res) => {
  const user = req.session.user;
  const message = req.body.message;
  let data = loadData();
  data.chats = data.chats || {};
  data.chats[user] = data.chats[user] || [];

  // Simpan pertanyaan dulu, balasan dikirim dari frontend (Puter.js)
  data.chats[user].push({ q: message, a: null, timestamp: Date.now() });
  saveData(data);

  res.json({ status: 'ok' });
});

// Endpoint menyimpan balasan AI setelah dari frontend
app.post('/save_reply', auth, (req, res) => {
  const user = req.session.user;
  const { question, answer } = req.body;
  let data = loadData();
  data.chats = data.chats || {};
  data.chats[user] = data.chats[user] || [];

  // Cari entry terakhir dengan a=null dan q=question lalu update jawabannya
  for (let i = data.chats[user].length -1; i >= 0; i--) {
    if (data.chats[user][i].q === question && data.chats[user][i].a === null) {
      data.chats[user][i].a = answer;
      break;
    }
  }
  saveData(data);
  res.json({ status: 'ok' });
});

// Kirim history chat user (max 20 terakhir)
app.get('/history', auth, (req, res) => {
  const user = req.session.user;
  let data = loadData();
  data.chats = data.chats || {};
  let history = data.chats[user] || [];
  history = history.filter(c => c.a !== null);
  history = history.slice(-20);
  res.json(history);
});

app.listen(PORT, () => {
  console.log(`Server berjalan di http://0.0.0.0:${PORT}`);
});
EOF

echo "[*] Membuat halaman login dan register..."
cat <<EOF > login.html
<!DOCTYPE html>
<html><body>
<h2>Login</h2>
<form action="/login" method="post">
  Username: <input name="username" required><br>
  Password: <input name="password" type="password" required><br>
  <button type="submit">Login</button>
</form>
<p>Belum punya akun? <a href="/register.html">Daftar</a></p>
</body></html>
EOF

cat <<EOF > register.html
<!DOCTYPE html>
<html><body>
<h2>Daftar</h2>
<form action="/register" method="post">
  Username: <input name="username" required><br>
  Password: <input name="password" type="password" required><br>
  <button type="submit">Daftar</button>
</form>
</body></html>
EOF

echo "[*] Membuat halaman chat dengan Puter.js..."

cat <<'EOF' > index.html
<!DOCTYPE html>
<html>
<head>
  <title>ChatGPT Mini with Puter.js</title>
  <style>
    body { font-family: sans-serif; padding: 20px; max-width: 700px; margin: auto;}
    pre { background: #f0f0f0; padding: 10px; border-radius: 6px; position: relative; white-space: pre-wrap; word-wrap: break-word; }
    .copy-btn { position: absolute; top: 10px; right: 10px; background: #ccc; border: none; cursor: pointer; padding: 5px; }
    #history p { margin-bottom: 0; }
  </style>
</head>
<body>
  <h1>ChatGPT Mini with Puter.js</h1>
  <a href="/logout">Logout</a>
  <div id="history"></div>
  <input id="msg" placeholder="Tulis pertanyaan..." style="width: 80%;" autocomplete="off" />
  <button onclick="send()">Kirim</button>

  <script src="https://js.puter.com/v2/"></script>
  <script>
    let chatHistory = [];

    function append(q, a) {
      const div = document.getElementById('history');
      // Tambah user message
      const pUser = document.createElement('p');
      pUser.innerHTML = '<b>You:</b> ' + q;
      div.appendChild(pUser);

      // Tambah AI balasan dengan tombol salin
      const pre = document.createElement('pre');
      pre.textContent = a;

      const btn = document.createElement('button');
      btn.textContent = 'Salin';
      btn.className = 'copy-btn';
      btn.onclick = () => {
        navigator.clipboard.writeText(a);
        btn.textContent = 'Disalin!';
        setTimeout(() => btn.textContent = 'Salin', 1500);
      };

      const wrapper = document.createElement('div');
      wrapper.style.position = 'relative';
      wrapper.appendChild(pre);
      wrapper.appendChild(btn);

      div.appendChild(wrapper);
      div.scrollTop = div.scrollHeight;
    }

    function loadHistory() {
      fetch('/history').then(r => r.json()).then(data => {
        chatHistory = data;
        for (const c of data) {
          append(c.q, c.a);
        }
      });
    }

    async function send() {
      const input = document.getElementById('msg');
      const msg = input.value.trim();
      if (!msg) return alert('Isi pesan dulu');
      input.value = '';

      // Kirim pesan ke backend dulu (disimpan)
      await fetch('/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: msg })
      });

      // Buat prompt gabungan dari history + pesan baru
      let fullPrompt = '';
      for (const chat of chatHistory) {
        fullPrompt += `User: ${chat.q}\nAI: ${chat.a}\n`;
      }
      fullPrompt += `User: ${msg}\nAI:`;

      // Panggil Puter.js dengan prompt lengkap
      puter.ai.chat(fullPrompt).then(reply => {
        append(msg, reply);

        // Simpan balasan ke backend
        fetch('/save_reply', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ question: msg, answer: reply })
        });

        chatHistory.push({ q: msg, a: reply });
      });
    }

    loadHistory();
  </script>
</body>
</html>
EOF

echo "[*] Membuat systemd service..."
cat <<EOF > /etc/systemd/system/chatgpt-mini.service
[Unit]
Description=ChatGPT Mini Puter.js
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

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable chatgpt-mini
systemctl start chatgpt-mini

IP=$(curl -s ifconfig.me)
echo "========================================="
echo "ChatGPT Mini Puter.js aktif!"
echo "Akses di: http://$IP:3000/login.html"
echo "========================================="
