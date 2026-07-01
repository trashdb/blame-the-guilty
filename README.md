# Blame the Guilty - CI/CD Punishment System

> Cuando un workflow de GitHub falla tras un merge, el culpable recibe un castigo: pantalla bloqueada hasta que escriba una frase de arrepentimiento.

## Arquitectura

```
┌──────────────┐     GitHub Webhooks     ┌──────────────────┐
│  GitHub Repo │────────────────────────►│                  │
│  (Actions)   │                         │  ASP.NET API     │
└──────────────┘   POST /api/webhook     │  (SignalR Hub)   │
                                          │                  │
┌──────────────┐    GitHub OAuth         │  SQLite DB       │
│  Avalonia UI │◄───────────────────────►│  (GitHubUsers)   │
│  (Escritorio)│    SignalR (WebSocket)   └──────────────────┘
└──────────────┘
       │
       ▼
┌──────────────────┐
│ PunishmentWindow │  💀 Pantalla bloqueada hasta redención
└──────────────────┘
```

## Requisitos

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) (o superior)
- [ngrok](https://ngrok.com/download) (para exponer el backend local)
- Una cuenta de GitHub
- Un repo de GitHub con GitHub Actions habilitado

> **Escritorio:** La app usa **Avalonia UI** (cross-platform: macOS, Windows, Linux).

## Configuración

### 1. Instalar y configurar ngrok

ngrok expone tu servidor local a internet para que GitHub pueda enviarte webhooks.

```bash
# macOS (con Homebrew)
brew install ngrok

# O descarga manual desde https://ngrok.com/download
```

Regístrate gratis en https://dashboard.ngrok.com/signup y obtén tu token de autenticación en https://dashboard.ngrok.com/get-started/your-authtoken. Luego:

```bash
ngrok config add-authtoken TU_TOKEN
```

### 2. Arrancar el backend y ngrok

**Terminal 1 - Backend:**
```bash
cd blame-the-guilty/backend
dotnet run
```
Busca en la salida la línea: `Now listening on: http://localhost:5000`. Ese es el puerto que expondremos.

**Terminal 2 - ngrok:**
```bash
ngrok http 5000
```
Verás algo como:
```
Forwarding  https://a1b2c3d4e5f6.ngrok.io -> http://localhost:5000
```
Esa URL (`https://a1b2c3d4e5f6.ngrok.io`) es tu puerta a internet. **Cópiala**, la necesitarás en los siguientes pasos. Déjalo corriendo.

### 3. Crear una GitHub OAuth App

1. Ve a **Settings → Developer settings → OAuth Apps → New OAuth App** (https://github.com/settings/developers)
2. Rellena:
   - **Application name:** `BlameTheGuilty`
   - **Homepage URL:** `https://a1b2c3d4e5f6.ngrok.io` (la URL de ngrok)
   - **Authorization callback URL:** `https://a1b2c3d4e5f6.ngrok.io/api/auth/callback`
3. Haz clic en **Register application**
4. Guarda el `Client ID` que aparece
5. Haz clic en **Generate a new client secret**, copia el `Client Secret`

### 4. Configurar el backend

Edita `backend/appsettings.json` con los datos de tu OAuth App y tu URL de ngrok:

```json
{
  "GitHubOAuth": {
    "ClientId": "EL_CLIENT_ID_QUE_COPIASTE",
    "ClientSecret": "EL_CLIENT_SECRET_QUE_COPIASTE",
    "RedirectUri": "https://a1b2c3d4e5f6.ngrok.io/api/auth/callback"
  }
}
```

Edita `desktop/MainWindow.xaml.cs` con tu URL de ngrok:

```csharp
private const string BackendUrl = "https://a1b2c3d4e5f6.ngrok.io";
```

Reinicia el backend (Ctrl+C y `dotnet run` otra vez) para que coja los cambios.

### 5. Configurar el Webhook en GitHub

En tu repo de GitHub:
1. **Settings → Webhooks → Add webhook**
2. **Payload URL:** `https://a1b2c3d4e5f6.ngrok.io/api/webhook/github`
3. **Content type:** `application/json`
4. **Events:** Selecciona **"Let me select individual events"**, busca y marca **"Workflow runs"**
5. **Active:** ✅ (asegúrate de que está marcado)
6. Haz clic en **Add webhook**

### 6. Iniciar la app de escritorio

> La app usa **Avalonia UI** y funciona en macOS, Windows y Linux.

```bash
cd desktop
dotnet run
```

Haz clic en **"Login con GitHub"**. Se abrirá el navegador para autenticarte con GitHub. Una vez autenticado, la ventana se cierra sola y la app se conecta al Hub de SignalR. Verás:

- Status: `Authenticated` (verde)
- Connection: `Connected` (verde)

Si todo va bien, la app queda en escucha esperando el castigo.

## Cómo probar el castigo

### Opción A: Enviar un webhook simulado (recomendado)

La forma más rápida de probar es enviar un payload falso directamente al backend con `curl`:

```bash
curl -X POST "https://TU_SUBDOMINIO.ngrok.io/api/webhook/github" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "completed",
    "workflow_run": {
      "id": 12345678,
      "conclusion": "failure",
      "head_branch": "main",
      "head_commit": {
        "id": "abc123",
        "author": {
          "name": "tu_usuario_github",
          "username": "tu_usuario_github"
        }
      },
      "pull_requests": [
        {
          "number": 1,
          "merged_by": {
            "id": TU_GITHUB_ID_NUMERICO,
            "login": "tu_usuario_github"
          },
          "user": {
            "id": TU_GITHUB_ID_NUMERICO,
            "login": "tu_usuario_github"
          }
        }
      ]
    },
    "repository": {
      "full_name": "tu_usuario/tu_repo"
    },
    "sender": {
      "id": TU_GITHUB_ID_NUMERICO,
      "login": "tu_usuario_github"
    }
  }'
```

> **Nota 1:** Sustituye `TU_GITHUB_ID_NUMERICO` por tu ID numérico de GitHub. Puedes obtenerlo llamando a la API: `curl https://api.github.com/users/TU_USUARIO` y leyendo `id`.
>
> **Nota 2:** Si la WPF no está conectada cuando envías el webhook, verás en los logs del backend: `User 'xxx' not connected. Punishment queued.`

### Opción B: Con un workflow de verdad

Crea `.github/workflows/failing-test.yml` en tu repo:

```yaml
name: Failing Test
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Fail intentionally
        run: exit 1
```

**Para activar el castigo:**
1. Crea una rama `feature/test`, haz un commit vacío, y abre una PR
2. El workflow fallará (es intencionado)
3. Haz **merge** de la PR
4. El webhook `workflow_run` con `conclusion: failure` se enviará al backend
5. El backend identifica que tú hiciste el merge y te envía el `TriggerPunishment`

### Opción C: Simular con GitHub CLI

```bash
# Instala gh si no lo tienes: https://cli.github.com

# Dispara un workflow manual que falle
gh workflow run failing-test.yml --ref main
# Espera a que termine y el webhook llegará
```

## Estructura del proyecto

```
blame-the-guilty/
├── BlameTheGuilty.slnx
├── backend/
│   ├── Program.cs                    # Startup: DI, SignalR, EF Core
│   ├── appsettings.json              # Config: OAuth, DB, etc.
│   ├── Controllers/
│   │   ├── AuthController.cs         # GET /api/auth/login + /callback
│   │   └── WebhookController.cs      # POST /api/webhook/github
│   ├── Data/AppDbContext.cs          # EF Core context
│   ├── Hubs/PunishmentHub.cs         # SignalR: Register/Disconnect
│   ├── Models/GitHubUser.cs          # GitHubId + Username + ConnectionId
│   └── Services/GitHubOAuthService.cs
└── desktop/
    ├── MainWindow.axaml/.cs          # Login + SignalR escucha (Avalonia)
    ├── PunishmentWindow.axaml/.cs    # Lock screen modal 💀 (Avalonia)
    ├── Program.cs                    # Entry point (Avalonia)
    └── Services/
        ├── OAuthService.cs           # Loopback HTTP listener
        └── SignalRService.cs         # HubConnection + TriggerPunishment
```

## Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/api/auth/login?redirect_uri=...` | Inicia OAuth con GitHub |
| `GET` | `/api/auth/callback?code=...&state=...` | Callback OAuth, upsert usuario |
| `POST` | `/api/webhook/github` | Webhook de `workflow_run` |
| `WS` | `/hub/punishment` | SignalR Hub |

## Señal de castigo (JSON)

Cuando el backend detecta un workflow fallido, envía al cliente SignalR:

```json
{
  "message": "Workflow failed! Punishment for usuario.",
  "culprit": "usuario",
  "runId": 12345678,
  "repo": "usuario/repo"
}
```

## Frase de redención

```
Prometo correr los tests en local antes de mergear
```

Debe escribirse exactamente igual (sin copiar/pegar, está bloqueado).

ClientID = Ov23liSn2Q0DA4XlLs2m