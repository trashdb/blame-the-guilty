# Blame the Guilty

> Cuando un workflow de GitHub Actions falla tras un merge, el culpable recibe una notificación inmediata en el menú de macOS. No más enterarse horas después.

## Cómo funciona

```
Workflow falla en GitHub ──► Webhook ──► Backend (VPS) ──► SignalR ──► Tu Mac (menú bar 🔥)
                                                              │
                                                    Identifica quién
                                                    hizo el merge
```

El backend ya está corriendo en un VPS y conectado por ngrok. No necesitas montar nada.

## Requisitos

- macOS (Sequoia o superior)
- Xcode CLI tools (`xcode-select --install`) o Xcode
- Una cuenta de GitHub

## Instalación (una vez)

```bash
# Clonar el repo
git clone git@github.com:trashdb/blame-the-guilty.git
cd blame-the-guilty/native

# Compilar e instalar
swift build -c release
bash install.sh
```

Esto instala `BlameTheGuilty.app` en `~/Applications/` y lo lanza automáticamente. Aparecerá un icono 🔥 en tu menú bar.

## Uso diario

1. Haz clic en el icono 🔥 de la menú bar
2. Haz clic en **"Sign in with GitHub"**
3. Se abre el navegador — autoriza la app
4. Vuelve al menú: verás **"Connected & watching"** en verde

A partir de ahí, cuando alguien mergee un workflow que falle, te llegará una notificación con el culpable, el repo y el run. Haz clic en la notificación para abrir el workflow en el navegador.

## Conectar vuestros repos

Cada repo que queráis vigilar necesita un webhook apuntando al backend:

1. En GitHub: **Settings → Webhooks → Add webhook**
2. **Payload URL:** `https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github`
3. **Content type:** `application/json`
4. **Events:** "Let me select individual events" → marca **"Workflow runs"**
5. **Active:** ✅
6. **Add webhook**

## Cómo probar (sin romper nada)

```bash
curl -X POST https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github \
  -H "Content-Type: application/json" \
  -d '{
    "action": "completed",
    "workflow_run": {
      "id": 999,
      "conclusion": "failure",
      "head_commit": { "author": { "username": "el-usuario-del-culpable" } },
      "pull_requests": [{
        "merged_by": { "id": 12345, "login": "el-usuario-del-culpable" },
        "user": { "id": 12345, "login": "el-usuario-del-culpable" }
      }]
    },
    "repository": { "full_name": "tu-org/tu-repo" },
    "sender": { "id": 12345, "login": "el-usuario-del-culpable" }
  }'
```

Si la app está abierta y conectada, te saltará la notificación.

## Estructura del repo

```
blame-the-guilty/
├── backend/          # API .NET + SignalR (ya desplegada en VPS)
│   ├── Controllers/  # WebhookController, AuthController
│   ├── Hubs/         # SignalR hub
│   └── appsettings.*.json
├── native/           # Cliente macOS (SwiftUI, menú bar)
│   ├── Sources/BlameTheGuilty/
│   │   ├── App.swift        # UI de la menú bar
│   │   ├── SignalRService.swift
│   │   ├── OAuthService.swift
│   │   └── CustomNotification.swift
│   └── install.sh
└── deploy/           # Scripts de despliegue del backend
```
