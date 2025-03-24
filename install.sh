#!/bin/bash

# NAS QuickID Manager Installation Script
# ---------------------------------------

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Konfiguration
PROJECT_DIR="nas-quickid-manager"
ADMIN_USER="admin"
ADMIN_PASSWORD="admin123"
ADMIN_EMAIL="admin@example.com"
GITHUB_REPO="https://github.com/anonyme23-cpu"
PORT=8888 # Port, auf dem der Dienst laufen soll

echo -e "${GREEN}=== NAS QuickID Manager Installation ===${NC}"
echo -e "Dieses Script installiert den NAS QuickID Manager mit Docker."
echo ""

# Überprüfen, ob Docker installiert ist
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker ist nicht installiert. Installation wird versucht...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker-Installation fehlgeschlagen. Bitte installieren Sie Docker manuell.${NC}"
        exit 1
    fi
fi

# Überprüfen, ob Docker Compose installiert ist
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Docker Compose ist nicht installiert. Installation wird versucht...${NC}"
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}Docker Compose-Installation fehlgeschlagen. Bitte installieren Sie Docker Compose manuell.${NC}"
        exit 1
    fi
fi

# Git installieren, falls nicht vorhanden
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}Git ist nicht installiert. Installation wird versucht...${NC}"
    sudo apt-get update && sudo apt-get install -y git
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Git-Installation fehlgeschlagen. Bitte installieren Sie Git manuell.${NC}"
        exit 1
    fi
fi

# Bereinigen aller Docker-Ressourcen, falls gewünscht
echo -e "${YELLOW}Möchten Sie alle bestehenden Docker-Container, -Netzwerke und -Volumes bereinigen? (j/n)${NC}"
read -r clean_docker

if [[ "$clean_docker" =~ ^[Jj]$ ]]; then
    echo -e "${YELLOW}Bereinige Docker-Umgebung...${NC}"
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker rm $(docker ps -aq) 2>/dev/null || true
    docker network prune -f
    docker volume prune -f
    echo -e "${GREEN}Docker-Umgebung bereinigt.${NC}"
fi

# Repository klonen oder aktualisieren
if [ -d "$PROJECT_DIR" ]; then
    echo -e "${YELLOW}Projekt-Verzeichnis existiert bereits. Aktualisieren...${NC}"
    cd $PROJECT_DIR
    git pull
    cd ..
else
    echo -e "${YELLOW}Klone Repository...${NC}"
    git clone $GITHUB_REPO $PROJECT_DIR
    if [ $? -ne 0 ]; then
        echo -e "${RED}Fehler beim Klonen des Repositories. Erstelle Projektstruktur manuell...${NC}"
        mkdir -p $PROJECT_DIR
    fi
fi

cd $PROJECT_DIR

# Verzeichnisstruktur erstellen
mkdir -p api web

echo -e "${YELLOW}Erstelle docker-compose.yml${NC}"
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  # PostgreSQL Datenbank für die Speicherung der NAS-QuickID-Zuordnungen
  db:
    image: postgres:14
    container_name: nas-quickid-db
    environment:
      POSTGRES_USER: nasadmin
      POSTGRES_PASSWORD: securepassword
      POSTGRES_DB: nasquickid
    volumes:
      - db-data:/var/lib/postgresql/data
    restart: unless-stopped
    networks:
      - nas-network

  # Backend API Service
  api:
    image: node:16
    container_name: nas-quickid-api
    working_dir: /app
    volumes:
      - ./api:/app
    command: bash -c "npm install && npm start"
    environment:
      DB_HOST: db
      DB_USER: nasadmin
      DB_PASSWORD: securepassword
      DB_NAME: nasquickid
      NODE_ENV: production
      JWT_SECRET: your-very-secret-key
    ports:
      - "3000:3000"
    depends_on:
      - db
    restart: unless-stopped
    networks:
      - nas-network

  # Web Frontend
  web:
    image: nginx:alpine
    container_name: nas-quickid-web
    volumes:
      - ./web:/usr/share/nginx/html
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    ports:
      - "PORT_PLACEHOLDER:80"
    depends_on:
      - api
    restart: unless-stopped
    networks:
      - nas-network

networks:
  nas-network:
    driver: bridge

volumes:
  db-data:
EOF

# Port in der docker-compose.yml ersetzen
sed -i "s/PORT_PLACEHOLDER/$PORT/g" docker-compose.yml

echo -e "${YELLOW}Erstelle nginx.conf${NC}"
cat > nginx.conf << 'EOF'
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    location /api {
        proxy_pass http://api:3000/api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

echo -e "${YELLOW}Erstelle Backend (package.json)${NC}"
cat > api/package.json << 'EOF'
{
  "name": "nas-quickid-manager-api",
  "version": "1.0.0",
  "description": "API für den NAS QuickID Manager",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "bcrypt": "^5.0.1",
    "body-parser": "^1.19.0",
    "cors": "^2.8.5",
    "express": "^4.17.1",
    "jsonwebtoken": "^8.5.1",
    "pg": "^8.7.1"
  }
}
EOF

echo -e "${YELLOW}Erstelle Backend (server.js)${NC}"
cat > api/server.js << 'EOF'
// server.js
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const bodyParser = require('body-parser');

const app = express();
const port = 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());

// Database connection
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 5432,
});

// DB-Initialisierung
async function initDb() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(100) NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS nas_entries (
        id SERIAL PRIMARY KEY,
        customer_name VARCHAR(100) NOT NULL,
        quick_id VARCHAR(50) UNIQUE NOT NULL,
        nas_ip VARCHAR(15),
        nas_model VARCHAR(100),
        notes TEXT,
        created_by INTEGER REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    
    // Prüfen, ob bereits Admin-Benutzer vorhanden
    const result = await client.query('SELECT * FROM users WHERE username = $1', ['admin']);
    if (result.rows.length === 0) {
      // Admin-Benutzer erstellen
      const hashedPassword = await bcrypt.hash('admin123', 10);
      await client.query(
        'INSERT INTO users (username, password, email) VALUES ($1, $2, $3)',
        ['admin', hashedPassword, 'admin@example.com']
      );
      console.log('Admin-Benutzer erstellt');
    }
    
    console.log('Database initialized successfully');
  } catch (error) {
    console.error('Error initializing database:', error);
  } finally {
    client.release();
  }
}

initDb();

// Auth Middleware
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  
  if (!token) return res.status(401).json({ message: 'Nicht authentifiziert' });
  
  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ message: 'Token ungültig' });
    req.user = user;
    next();
  });
};

// Routes
// Login
app.post('/api/login', async (req, res) => {
  const { username, password } = req.body;
  
  try {
    const result = await pool.query('SELECT * FROM users WHERE username = $1', [username]);
    const user = result.rows[0];
    
    if (!user) {
      return res.status(401).json({ message: 'Ungültiger Benutzername oder Passwort' });
    }
    
    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) {
      return res.status(401).json({ message: 'Ungültiger Benutzername oder Passwort' });
    }
    
    const token = jwt.sign({ id: user.id, username: user.username }, process.env.JWT_SECRET, { expiresIn: '24h' });
    res.json({ token, user: { id: user.id, username: user.username, email: user.email } });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Serverfehler' });
  }
});

// Register user (Admin only in production)
app.post('/api/users', async (req, res) => {
  const { username, password, email } = req.body;
  
  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    const result = await pool.query(
      'INSERT INTO users (username, password, email) VALUES ($1, $2, $3) RETURNING id, username, email',
      [username, hashedPassword, email]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error(error);
    if (error.code === '23505') {
      res.status(400).json({ message: 'Benutzername oder E-Mail existiert bereits' });
    } else {
      res.status(500).json({ message: 'Serverfehler' });
    }
  }
});

// NAS Entries Management
// Get all entries
app.get('/api/nas', authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT n.*, u.username as created_by_username 
      FROM nas_entries n
      JOIN users u ON n.created_by = u.id
      ORDER BY n.created_at DESC
    `);
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Serverfehler' });
  }
});

// Get entry by QuickID
app.get('/api/nas/quickid/:quickId', authenticateToken, async (req, res) => {
  const { quickId } = req.params;
  
  try {
    const result = await pool.query('SELECT * FROM nas_entries WHERE quick_id = $1', [quickId]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'NAS-Eintrag nicht gefunden' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Serverfehler' });
  }
});

// Create new entry
app.post('/api/nas', authenticateToken, async (req, res) => {
  const { customer_name, quick_id, nas_ip, nas_model, notes } = req.body;
  
  try {
    const result = await pool.query(
      'INSERT INTO nas_entries (customer_name, quick_id, nas_ip, nas_model, notes, created_by) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
      [customer_name, quick_id, nas_ip, nas_model, notes, req.user.id]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error(error);
    if (error.code === '23505') {
      res.status(400).json({ message: 'QuickID existiert bereits' });
    } else {
      res.status(500).json({ message: 'Serverfehler' });
    }
  }
});

// Update entry
app.put('/api/nas/:id', authenticateToken, async (req, res) => {
  const { id } = req.params;
  const { customer_name, quick_id, nas_ip, nas_model, notes } = req.body;
  
  try {
    const result = await pool.query(
      `UPDATE nas_entries 
       SET customer_name = $1, quick_id = $2, nas_ip = $3, nas_model = $4, notes = $5, updated_at = CURRENT_TIMESTAMP
       WHERE id = $6 RETURNING *`,
      [customer_name, quick_id, nas_ip, nas_model, notes, id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'NAS-Eintrag nicht gefunden' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error(error);
    if (error.code === '23505') {
      res.status(400).json({ message: 'QuickID existiert bereits' });
    } else {
      res.status(500).json({ message: 'Serverfehler' });
    }
  }
});

// Delete entry
app.delete('/api/nas/:id', authenticateToken, async (req, res) => {
  const { id } = req.params;
  
  try {
    const result = await pool.query('DELETE FROM nas_entries WHERE id = $1 RETURNING *', [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'NAS-Eintrag nicht gefunden' });
    }
    
    res.json({ message: 'NAS-Eintrag erfolgreich gelöscht' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Serverfehler' });
  }
});

app.listen(port, () => {
  console.log(`NAS QuickID Manager API running on port ${port}`);
});
EOF

echo -e "${YELLOW}Erstelle Frontend (index.html)${NC}"
cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NAS QuickID Manager</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/tailwindcss/2.2.19/tailwind.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
    <style>
        .modal {
            transition: opacity 0.25s ease;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        }
    </style>
</head>
<body class="bg-gray-100">
    <!-- Navigation -->
    <nav class="bg-blue-600 text-white shadow-lg">
        <div class="max-w-7xl mx-auto px-4">
            <div class="flex justify-between h-16">
                <div class="flex items-center">
                    <div class="flex-shrink-0 flex items-center">
                        <i class="fas fa-server text-2xl mr-2"></i>
                        <span class="font-bold text-xl">NAS QuickID Manager</span>
                    </div>
                </div>
                <div class="flex items-center">
                    <div id="userInfo" class="hidden">
                        <span id="username" class="mr-4"></span>
                        <button id="logoutBtn" class="bg-blue-700 hover:bg-blue-800 text-white py-2 px-4 rounded">
                            <i class="fas fa-sign-out-alt mr-1"></i> Abmelden
                        </button>
                    </div>
                </div>
            </div>
        </div>
    </nav>

    <!-- Login Form -->
    <div id="loginContainer" class="max-w-md mx-auto mt-20 bg-white p-8 rounded shadow-md">
        <h2 class="text-2xl font-bold mb-6 text-center text-gray-800">Anmeldung</h2>
        <form id="loginForm">
            <div class="mb-4">
                <label class="block text-gray-700 text-sm font-bold mb-2" for="username">
                    Benutzername
                </label>
                <input class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline" 
                    id="loginUsername" type="text" placeholder="Benutzername" required>
            </div>
            <div class="mb-6">
                <label class="block text-gray-700 text-sm font-bold mb-2" for="password">
                    Passwort
                </label>
                <input class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 mb-3 leading-tight focus:outline-none focus:shadow-outline" 
                    id="loginPassword" type="password" placeholder="******************" required>
            </div>
            <div id="loginError" class="text-red-500 text-center mb-4 hidden"></div>
            <div class="flex items-center justify-between">
                <button class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline w-full" 
                    type="submit">
                    Anmelden
                </button>
            </div>
        </form>
    </div>

    <!-- Main Content -->
    <div id="mainContent" class="max-w-7xl mx-auto px-4 py-8 hidden">
        <!-- Search and Action Bar -->
        <div class="flex flex-col md:flex-row justify-between mb-6">
            <div class="mb-4 md:mb-0 md:w-1/2">
                <div class="relative">
                    <input type="text" id="searchInput" 
                        class="w-full pl-10 pr-4 py-2 rounded-lg border focus:outline-none focus:ring-2 focus:ring-blue-600" 
                        placeholder="Nach QuickID oder Kundenname suchen...">
                    <div class="absolute left-0 top-0 mt-2 ml-3 text-gray-400">
                        <i class="fas fa-search"></i>
                    </div>
                </div>
            </div>
            <div class="flex space-x-2">
                <button id="addNewBtn" class="bg-green-500 hover:bg-green-600 text-white py-2 px-4 rounded">
                    <i class="fas fa-plus mr-1"></i> Neuer Eintrag
                </button>
                <button id="refreshBtn" class="bg-blue-500 hover:bg-blue-600 text-white py-2 px-4 rounded">
                    <i class="fas fa-sync-alt mr-1"></i> Aktualisieren
                </button>
            </div>
        </div>

        <!-- NAS Table -->
        <div class="bg-white rounded-lg shadow overflow-x-auto">
            <table class="min-w-full">
                <thead>
                    <tr class="bg-gray-200 text-gray-700">
                        <th class="py-3 px-4 text-left">Kunde</th>
                        <th class="py-3 px-4 text-left">QuickID</th>
                        <th class="py-3 px-4 text-left">NAS IP</th>
                        <th class="py-3 px-4 text-left">NAS Modell</th>
                        <th class="py-3 px-4 text-left">Erstellt von</th>
                        <th class="py-3 px-4 text-left">Datum</th>
                        <th class="py-3 px-4 text-center">Aktionen</th>
                    </tr>
                </thead>
                <tbody id="nasTableBody">
                    <!-- Tabellendaten werden durch JavaScript eingefügt -->
                </tbody>
            </table>
        </div>
    </div>

    <!-- NAS Entry Modal -->
    <div id="nasModal" class="modal opacity-0 pointer-events-none fixed w-full h-full top-0 left-0 flex items-center justify-center z-50">
        <div class="modal-overlay absolute w-full h-full bg-gray-900 opacity-50"></div>
        
        <div class="modal-container bg-white w-11/12 md:max-w-md mx-auto rounded shadow-lg z-50 overflow-y-auto">
            <div class="modal-content py-4 text-left px-6">
                <div class="flex justify-between items-center pb-3">
                    <p id="modalTitle" class="text-2xl font-bold">Neuer NAS-Eintrag</p>
                    <div class="modal-close cursor-pointer z-50" id="closeModal">
                        <i class="fas fa-times text-gray-500 hover:text-gray-800"></i>
                    </div>
                </div>

                <form id="nasForm">
                    <input type="hidden" id="nasId">
                    <div class="mb-4">
                        <label class="block text-gray-700 text-sm font-bold mb-2" for="customerName">
                            Kundenname
                        </label>
                        <input class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline" 
                            id="customerName" type="text" required>
                    </div>
                    <div class="mb-4">
                        <label class="block text-gray-700 text-sm font-bold mb-2" for="quickId">
                            QuickID
                        </label>
                        <input class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline" 
                            id="quickId" type="text" required pattern="[a-zA-Z0-9\-_]+">
                        <p class="text-gray-500 text-xs italic mt-1">Nur Buchstaben, Zahlen, Bindestriche und Unterstriche</p>
                    </div>
                    <div class="mb-4">
                        <label class="block text-gray-700 text-sm font-bold mb-2" for="nasIp">
                            NAS IP-Adresse
                        </label>
                        <input class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline" 
                            id="nasIp" type="text" pattern="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$">
                        <p class="text-gray-500 text-xs italic mt-1">Format: 192.168.1.1</p>
                    </div>
                    <div class="mb-4">
                        <label class="block text-gray-700 text-sm font-bold mb-2" for="nasModel">
                            NAS Modell
                        </label>
                        <input class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline" 
                            id="nasModel" type="text">
                    </div>
                    <div class="mb-4">
                        <label class="block text-gray-700 text-sm font-bold mb-2" for="notes">
                            Notizen
                        </label>
                        <textarea class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline" 
                            id="notes" rows="3"></textarea>
                    </div>
                    <div class="flex justify-end pt-2">
                        <button type="button" id="cancelBtn" class="mr-2 px-4 bg-gray-200 p-3 rounded text-gray-700 hover:bg-gray-300">
                            Abbrechen
                        </button>
                        <button type="submit" id="saveBtn" class="px-4 bg-blue-500 p-3 rounded text-white hover:bg-blue-600">
                            Speichern
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <!-- Delete Confirmation Modal -->
    <div id="deleteModal" class="modal opacity-0 pointer-events-none fixed w-full h-full top-0 left-0 flex items-center justify-center z-50">
        <div class="modal-overlay absolute w-full h-full bg-gray-900 opacity-50"></div>
        
        <div class="modal-container bg-white w-11/12 md:max-w-md mx-auto rounded shadow-lg z-50 overflow-y-auto">
            <div class="modal-content py-4 text-left px-6">
                <div class="flex justify-between items-center pb-3">
                    <p class="text-xl font-bold">Eintrag löschen</p>
                    <div class="modal-close cursor-pointer z-50" id="closeDeleteModal">
                        <i class="fas fa-times text-gray-500 hover:text-gray-800"></i>
                    </div>
                </div>

                <p class="text-gray-700 mb-6">Sind Sie sicher, dass Sie diesen NAS-Eintrag löschen möchten? Diese Aktion kann nicht rückgängig gemacht werden.</p>
                
                <input type="hidden" id="deleteNasId">
                
                <div class="flex justify-end pt-2">
                    <button id="cancelDeleteBtn" class="mr-2 px-4 bg-gray-200 p-3 rounded text-gray-700 hover:bg-gray-300">
                        Abbrechen
                    </button>
                    <button id="confirmDeleteBtn" class="px-4 bg-red-500 p-3 rounded text-white hover:bg-red-600">
                        Löschen
                    </button>
                </div>
            </div>
        </div>
    </div>

    <script>
        // API URL
        const API_URL = '/api';
        let token = localStorage.getItem('token');
        let currentUser = JSON.parse(localStorage.getItem('user') || '{}');
        let nasEntries = [];
        
        // DOM-Elemente
        const loginContainer = document.getElementById('loginContainer');
        const mainContent = document.getElementById('mainContent');
        const userInfo = document.getElementById('userInfo');
        const usernameEl = document.getElementById('username');
        const loginForm = document.getElementById('loginForm');
        const loginError = document.getElementById('loginError');
        const nasTableBody = document.getElementById('nasTableBody');
        const searchInput = document.getElementById('searchInput');
        const logoutBtn = document.getElementById('logoutBtn');
        const addNewBtn = document.getElementById('addNewBtn');
        const refreshBtn = document.getElementById('refreshBtn');
        const nasModal = document.getElementById('nasModal');
        const modalTitle = document.getElementById('modalTitle');
        const nasForm = document.getElementById('nasForm');
const nasId = document.getElementById('nasId');
        const closeModal = document.getElementById('closeModal');
        const cancelBtn = document.getElementById('cancelBtn');
        const deleteModal = document.getElementById('deleteModal');
        const deleteNasId = document.getElementById('deleteNasId');
        const closeDeleteModal = document.getElementById('closeDeleteModal');
        const cancelDeleteBtn = document.getElementById('cancelDeleteBtn');
        const confirmDeleteBtn = document.getElementById('confirmDeleteBtn');

        // Beim Laden der Seite
        document.addEventListener('DOMContentLoaded', () => {
            checkAuth();
            setupEventListeners();
        });

        // Event-Listener einrichten
        function setupEventListeners() {
            loginForm.addEventListener('submit', handleLogin);
            logoutBtn.addEventListener('click', handleLogout);
            addNewBtn.addEventListener('click', showAddModal);
            refreshBtn.addEventListener('click', fetchNasEntries);
            nasForm.addEventListener('submit', handleSaveNas);
            closeModal.addEventListener('click', closeNasModal);
            cancelBtn.addEventListener('click', closeNasModal);
            closeDeleteModal.addEventListener('click', closeDeleteConfirmation);
            cancelDeleteBtn.addEventListener('click', closeDeleteConfirmation);
            confirmDeleteBtn.addEventListener('click', handleDeleteNas);
            searchInput.addEventListener('input', handleSearch);
        }

        // Authentifizierung prüfen
        function checkAuth() {
            if (token) {
                showMainContent();
                usernameEl.textContent = currentUser.username || 'Benutzer';
                fetchNasEntries();
            } else {
                showLoginForm();
            }
        }

        // Login-Formular anzeigen
        function showLoginForm() {
            loginContainer.classList.remove('hidden');
            mainContent.classList.add('hidden');
            userInfo.classList.add('hidden');
        }

        // Hauptinhalt anzeigen
        function showMainContent() {
            loginContainer.classList.add('hidden');
            mainContent.classList.remove('hidden');
            userInfo.classList.remove('hidden');
        }

        // Login-Handler
        async function handleLogin(e) {
            e.preventDefault();
            const username = document.getElementById('loginUsername').value;
            const password = document.getElementById('loginPassword').value;

            try {
                const response = await fetch(`${API_URL}/login`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ username, password })
                });

                const data = await response.json();

                if (!response.ok) {
                    throw new Error(data.message || 'Login fehlgeschlagen');
                }

                token = data.token;
                currentUser = data.user;
                localStorage.setItem('token', token);
                localStorage.setItem('user', JSON.stringify(currentUser));
                showMainContent();
                usernameEl.textContent = currentUser.username;
                fetchNasEntries();
            } catch (error) {
                loginError.textContent = error.message;
                loginError.classList.remove('hidden');
            }
        }

        // Logout-Handler
        function handleLogout() {
            localStorage.removeItem('token');
            localStorage.removeItem('user');
            token = null;
            currentUser = {};
            showLoginForm();
        }

        // NAS-Einträge abrufen
        async function fetchNasEntries() {
            try {
                const response = await fetch(`${API_URL}/nas`, {
                    headers: {
                        'Authorization': `Bearer ${token}`
                    }
                });

                if (!response.ok) {
                    if (response.status === 401 || response.status === 403) {
                        handleLogout();
                        return;
                    }
                    throw new Error('Fehler beim Abrufen der Daten');
                }

                nasEntries = await response.json();
                renderNasEntries(nasEntries);
            } catch (error) {
                console.error('Fehler:', error);
                alert(error.message);
            }
        }

        // NAS-Einträge rendern
        function renderNasEntries(entries) {
            nasTableBody.innerHTML = '';
            
            if (entries.length === 0) {
                nasTableBody.innerHTML = `
                    <tr>
                        <td colspan="7" class="py-4 px-4 text-center text-gray-500">
                            Keine Einträge gefunden
                        </td>
                    </tr>
                `;
                return;
            }
            
            entries.forEach(entry => {
                const createdDate = new Date(entry.created_at).toLocaleDateString('de-DE');
                
                // QuickConnect-Link erstellen
                const quickConnectLink = `<a href="https://${entry.quick_id}.quickconnect.to/#/signin" target="_blank" class="text-blue-600 hover:text-blue-800 font-mono">${escapeHtml(entry.quick_id)}</a>`;
                
                nasTableBody.innerHTML += `
                    <tr class="border-b hover:bg-gray-50">
                        <td class="py-3 px-4">${escapeHtml(entry.customer_name)}</td>
                        <td class="py-3 px-4">${quickConnectLink}</td>
                        <td class="py-3 px-4 font-mono">${escapeHtml(entry.nas_ip || '-')}</td>
                        <td class="py-3 px-4">${escapeHtml(entry.nas_model || '-')}</td>
                        <td class="py-3 px-4">${escapeHtml(entry.created_by_username || '-')}</td>
                        <td class="py-3 px-4">${createdDate}</td>
                        <td class="py-3 px-4 text-center">
                            <button class="text-blue-500 hover:text-blue-700 mr-2" onclick="editNas('${entry.id}')">
                                <i class="fas fa-edit"></i>
                            </button>
                            <button class="text-red-500 hover:text-red-700" onclick="showDeleteConfirmation('${entry.id}')">
                                <i class="fas fa-trash-alt"></i>
                            </button>
                        </td>
                    </tr>
                `;
            });
        }

        // HTML-Escape-Funktion
        function escapeHtml(unsafe) {
            if (unsafe === null || unsafe === undefined) return '';
            return unsafe
                .toString()
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&#039;");
        }

        // Suche nach Einträgen
        function handleSearch() {
            const searchTerm = searchInput.value.toLowerCase();
            
            if (searchTerm === '') {
                renderNasEntries(nasEntries);
                return;
            }
            
            const filteredEntries = nasEntries.filter(entry => 
                entry.customer_name.toLowerCase().includes(searchTerm) ||
                entry.quick_id.toLowerCase().includes(searchTerm) ||
                (entry.nas_ip && entry.nas_ip.toLowerCase().includes(searchTerm)) ||
                (entry.nas_model && entry.nas_model.toLowerCase().includes(searchTerm))
            );
            
            renderNasEntries(filteredEntries);
        }

        // Modal zum Hinzufügen anzeigen
        function showAddModal() {
            modalTitle.textContent = 'Neuer NAS-Eintrag';
            nasId.value = '';
            nasForm.reset();
            openNasModal();
        }

        // NAS-Eintrag bearbeiten
        function editNas(id) {
            const entry = nasEntries.find(e => e.id == id);
            if (!entry) return;
            
            modalTitle.textContent = 'NAS-Eintrag bearbeiten';
            nasId.value = entry.id;
            document.getElementById('customerName').value = entry.customer_name;
            document.getElementById('quickId').value = entry.quick_id;
            document.getElementById('nasIp').value = entry.nas_ip || '';
            document.getElementById('nasModel').value = entry.nas_model || '';
            document.getElementById('notes').value = entry.notes || '';
            
            openNasModal();
        }

        // NAS-Modal öffnen
        function openNasModal() {
            nasModal.classList.remove('opacity-0', 'pointer-events-none');
        }

        // NAS-Modal schließen
        function closeNasModal() {
            nasModal.classList.add('opacity-0', 'pointer-events-none');
        }

        // NAS speichern (hinzufügen oder aktualisieren)
        async function handleSaveNas(e) {
            e.preventDefault();
            
            const id = nasId.value;
            const data = {
                customer_name: document.getElementById('customerName').value,
                quick_id: document.getElementById('quickId').value,
                nas_ip: document.getElementById('nasIp').value,
                nas_model: document.getElementById('nasModel').value,
                notes: document.getElementById('notes').value
            };
            
            try {
                let url = `${API_URL}/nas`;
                let method = 'POST';
                
                if (id) {
                    url = `${API_URL}/nas/${id}`;
                    method = 'PUT';
                }
                
                const response = await fetch(url, {
                    method,
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${token}`
                    },
                    body: JSON.stringify(data)
                });
                
                const responseData = await response.json();
                
                if (!response.ok) {
                    throw new Error(responseData.message || 'Fehler beim Speichern des Eintrags');
                }
                
                closeNasModal();
                fetchNasEntries();
            } catch (error) {
                console.error('Fehler:', error);
                alert(error.message);
            }
        }

        // Löschen-Bestätigung anzeigen
        function showDeleteConfirmation(id) {
            deleteNasId.value = id;
            deleteModal.classList.remove('opacity-0', 'pointer-events-none');
        }

        // Löschen-Bestätigung schließen
        function closeDeleteConfirmation() {
            deleteModal.classList.add('opacity-0', 'pointer-events-none');
        }

        // NAS-Eintrag löschen
        async function handleDeleteNas() {
            const id = deleteNasId.value;
            
            try {
                const response = await fetch(`${API_URL}/nas/${id}`, {
                    method: 'DELETE',
                    headers: {
                        'Authorization': `Bearer ${token}`
                    }
                });
                
                if (!response.ok) {
                    const data = await response.json();
                    throw new Error(data.message || 'Fehler beim Löschen des Eintrags');
                }
                
                closeDeleteConfirmation();
                fetchNasEntries();
            } catch (error) {
                console.error('Fehler:', error);
                alert(error.message);
            }
        }

        // Globale Funktionen für onclick-Events
        window.editNas = editNas;
        window.showDeleteConfirmation = showDeleteConfirmation;
    </script>
</body>
</html>
EOF

echo -e "${YELLOW}Starte die Container${NC}"
docker-compose up -d

# Warten auf den Start der Datenbank und API
echo -e "${YELLOW}Warte auf den Start der Dienste...${NC}"
sleep 10

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}NAS QuickID Manager wurde erfolgreich installiert!${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}Zugriff:${NC}"
echo -e "Frontend: http://$(hostname -I | awk '{print $1}'):$PORT"
echo -e "API: http://$(hostname -I | awk '{print $1}'):3000/api"
echo -e ""
echo -e "${GREEN}Login-Daten:${NC}"
echo -e "Benutzername: admin"
echo -e "Passwort: admin123"
echo -e ""
echo -e "${YELLOW}Aus Sicherheitsgründen sollten Sie das Passwort nach dem ersten Login ändern!${NC}"
echo -e "${GREEN}======================================================${NC}"
