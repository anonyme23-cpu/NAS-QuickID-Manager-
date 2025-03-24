# NAS QuickID Manager

![NAS QuickID Manager Logo](https://img.shields.io/badge/NAS-QuickID%20Manager-blue)
![Version](https://img.shields.io/badge/version-1.0.0-green)
![Docker](https://img.shields.io/badge/docker-required-blue)
![License](https://img.shields.io/badge/license-MIT-yellow)

Ein einfaches, Docker-basiertes Verwaltungssystem für Synology NAS QuickIDs. Perfekt für IT-Administratoren, die mehrere Synology NAS-Geräte verwalten müssen.

![Screenshot](https://img.shields.io/badge/Screenshot-Demo-lightgrey)

## 🚀 Features

- **Zentrale Verwaltung**: Speichern und verwalten Sie alle NAS QuickIDs an einem Ort
- **Schneller Zugriff**: Direkter Zugriff auf NAS-Systeme über Synology QuickConnect
- **Kundeninformationen**: Speichern Sie Kundennamen und weitere Details zu jedem Gerät
- **Suchfunktion**: Schnelles Finden von Einträgen durch Suche nach Kunden oder QuickIDs
- **Benutzerkonten**: Mehrbenutzer-Unterstützung mit sicherer Authentifizierung
- **Mobil-freundlich**: Responsive Benutzeroberfläche für den Zugriff von überall

## 📋 Voraussetzungen

- Docker und Docker Compose
- Git (für die Installation)
- Internetverbindung (für das Herunterladen der Container-Images)

## 🔧 Installation

### One-Click Installation

```bash
# Repository klonen
git clone https://github.com/IHR_BENUTZERNAME/nas-quickid-manager.git
cd nas-quickid-manager

# Installationsskript ausführbar machen und ausführen
chmod +x install.sh
./install.sh
```

Das Installationsskript richtet alles automatisch ein und gibt nach der Installation die URL und Login-Daten aus.

### Manuelle Installation

Falls Sie das System manuell einrichten möchten:

1. Repository klonen:
```bash
git clone https://github.com/IHR_BENUTZERNAME/nas-quickid-manager.git
cd nas-quickid-manager
```

2. Docker Compose ausführen:
```bash
docker-compose up -d
```

3. Zugriff über:
```
http://SERVER_IP:8888
```

## 🔐 Standardzugang

- **Benutzername**: admin
- **Passwort**: admin123

⚠️ Bitte ändern Sie das Passwort nach der ersten Anmeldung!

## 🧩 Architektur

Das System besteht aus drei Docker-Containern:

1. **PostgreSQL Datenbank** - Speichert Benutzer und NAS-Einträge
2. **Node.js Backend** - REST API mit Express.js
3. **Nginx Frontend** - Weboberfläche mit HTML, JavaScript und TailwindCSS

## 🛠️ Wartung

### Aktualisierung

```bash
cd nas-quickid-manager
git pull
docker-compose down
docker-compose up -d
```

### Backup der Datenbank

```bash
docker exec -t nas-quickid-db pg_dumpall -c -U nasadmin > dump_$(date +%Y-%m-%d_%H_%M_%S).sql
```

### Wiederherstellung der Datenbank

```bash
cat your_dump.sql | docker exec -i nas-quickid-db psql -U nasadmin -d nasquickid
```

## 📝 Nutzung

1. Melden Sie sich mit den Anmeldeinformationen an
2. Fügen Sie neue NAS-Einträge hinzu über "Neuer Eintrag"
3. Klicken Sie auf eine QuickID in der Tabelle, um direkt Zugriff auf die NAS zu erhalten
4. Verwalten Sie bestehende Einträge über die Aktionsbuttons in der Tabelle

## ⚙️ Konfiguration

Die Konfiguration kann in der `docker-compose.yml` Datei angepasst werden.

### Port ändern

Bearbeiten Sie die Port-Einstellung in `docker-compose.yml`:
```yaml
ports:
  - "NEUER_PORT:80"
```

### Datenbank-Passwort ändern

Ändern Sie das Passwort in der `docker-compose.yml` und passen Sie auch die Umgebungsvariablen für den API-Service an.

## 🤝 Beitragen

Beiträge sind willkommen! Bitte erstellen Sie einen Fork des Projekts und senden Sie einen Pull Request.

## 📜 Lizenz

MIT-Lizenz - Siehe [LICENSE](LICENSE) für weitere Details.

## 📧 Kontakt

Haben Sie Fragen oder Vorschläge? Öffnen Sie ein Issue oder kontaktieren Sie mich:

- E-Mail: [Ihre E-Mail-Adresse]
- Twitter: [@IhrHandle]
- Website: [Ihre Website]
