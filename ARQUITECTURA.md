# Blame the Guilty — Guía Completa de Arquitectura

## Arquitectura General

```
[macOS App] ←SignalR+REST→ [ngrok tunnel] → [ASP.NET Kestrel:5000] → [SQLite DB]
                              ↑                                            ↑
                         (Hetzner VPS)                         /var/lib/blame-the-guilty/
                                                                   blame_the_guilty.db
```

- **Backend**: App .NET 10 self-hosted en un VPS de Hetzner con systemd
- **Frontend**: App macOS nativa (SwiftUI) como menu bar utility (sin Dock, sin ventana principal)
- **Túnel público**: ngrok gratuito para recibir webhooks de GitHub
- **Sin Docker, sin nginx, sin CI/CD**

---

## Backend (`backend/`)

### Stack

| Componente | Tecnología |
|------------|-----------|
| Runtime | .NET 10 (`net10.0`) |
| ORM | Entity Framework Core 10 + SQLite |
| Tiempo real | SignalR (WebSocket) |
| Paquetes externos | Solo 2: `EF Core Sqlite` + `EF Core Design` |
| Webhooks | Endpoint con verificación HMAC-SHA256 |

### Estructura de archivos

```
backend/
├── Program.cs                          # Entry point, DI, CORS, SignalR, DB init
├── BlameTheGuilty.Api.csproj           # .NET 10, 2 NuGet refs
├── appsettings.json                    # Dev config (OAuth creds, DB path)
├── appsettings.Production.json         # Producción (DB en /var/lib/...)
├── Data/
│   └── AppDbContext.cs                 # EF DbContext: 5 DbSets
├── Models/
│   ├── GitHubUser.cs                   # id, username, AccessToken, PatToken, avatar
│   ├── WorkflowRun.cs                  # runId, status, headSha, actor, repo
│   ├── PullRequestEvent.cs             # prNumber, title, author, approval, comments
│   ├── CheckSuiteEvent.cs              # checkSuiteId, conclusion, prAuthor
│   └── PunishmentEvent.cs              # culprit, runId, workflow
├── Hubs/
│   └── PunishmentHub.cs                # SignalR: RegisterConnection, user groups
├── Services/
│   ├── GitHubOAuthService.cs           # OAuth flow: authorize URL + code exchange
│   └── UtcDateTimeConverter.cs         # JSON DateTime → ISO 8601 UTC
└── Controllers/
    ├── AuthController.cs               # /api/auth (login, callback, me, pat)
    ├── WebhookController.cs            # /api/webhook/github (11 eventos)
    ├── GitHubApiController.cs          # /api/github (branches, create-pr, pr-preview, interpret)
    ├── PullRequestsController.cs       # /api/pullrequests (active, detail, merge, draft, update-branch)
    ├── WorkflowsController.cs          # /api/workflows (runs, rerun, sync-active, targets)
    └── PunishmentsController.cs        # /api/punishments (list, summary)
```

### Base de datos (SQLite)

| Tabla | Propósito |
|-------|-----------|
| `GitHubUsers` | Usuarios con OAuth token + PAT opcional + conexión SignalR |
| `WorkflowRuns` | Cada ejecución de workflow (status: in_progress, success, failure, cancelled, superseded) |
| `PullRequestEvents` | PRs abiertos/mergeados con estado de CI, aprobación, comentarios |
| `CheckSuiteEvents` | Check suites completadas (para notificar al autor) |
| `PunishmentEvents` | Histórico de "castigos" por workflows fallidos |

### API endpoints

#### Auth
| Método | Ruta | Función |
|--------|------|---------|
| GET | `/api/auth/login` | Redirige al usuario a GitHub OAuth |
| GET | `/api/auth/callback` | Exchange code → token, upsert usuario, redirect a app |
| GET | `/api/auth/me` | Perfil del usuario |
| POST | `/api/auth/pat` | Guardar/borrar PAT del usuario |

#### Pull Requests
| Método | Ruta | Función |
|--------|------|---------|
| GET | `/api/pullrequests/active` | Lista PRs activos con ciStatus, comments, check-runs sync |
| GET | `/api/pullrequests/{n}/detail` | Mergeable state, behind/ahead |
| POST | `/api/pullrequests/{n}/merge` | Merge PR (squash/rebase/merge) |
| POST | `/api/pullrequests/{n}/draft` | Toggle draft vía GraphQL |
| POST | `/api/pullrequests/{n}/update-branch` | Merge base en head, marca runs viejos como superseded |

#### Workflows
| Método | Ruta | Función |
|--------|------|---------|
| GET | `/api/workflows/runs` | Lista runs recientes (propios + targeted) |
| POST | `/api/workflows/runs/{id}/rerun` | Re-ejecutar workflow |
| PUT | `/api/workflows/runs/{id}/target` | Asignar usuarios a notificar |
| POST | `/api/workflows/sync-active` | Sincroniza runs in_progress desde GitHub API |

#### GitHub API proxy
| Método | Ruta | Función |
|--------|------|---------|
| GET | `/api/github/my-branches` | Ramas del usuario en un repo |
| POST | `/api/github/create-pr` | Crear PR |
| POST | `/api/github/pr-preview` | Preview con template + commits + resumen Copilot |
| POST | `/api/github/interpret` | Interpretar lenguaje natural (legacy, eliminado del UI) |

### Webhooks de GitHub que maneja

| Evento | Acciones | Qué hace |
|--------|----------|----------|
| `workflow_run` | in_progress, completed | Crea/actualiza WorkflowRun, notifica por SignalR |
| `check_suite` | requested, completed | Crea CheckSuiteEvent, notifica al autor |
| `pull_request` | opened, synchronize, closed, ready_for_review, converted_to_draft | Crea/actualiza PullRequestEvent |
| `pull_request_review` | submitted | Marca approved, notifica `PrApproved` |
| `issue_comment` | created (en PRs) | Notifica `PrCommented` |
| `pull_request_review_comment` | created | Notifica `PrCommented` con file/line |

### Señales de SignalR que envía al cliente

| Evento | Payload | Cuándo |
|--------|---------|--------|
| `WorkflowRunStarted` | id, runId, workflowName, repo, branch, actor | Workflow empieza |
| `WorkflowRunCompleted` | runId, succeeded, conclusion, workflowName, repo, actor | Workflow termina |
| `PullRequestsUpdated` | *(ninguno)* | Cualquier cambio en PRs → cliente refetch |
| `PrApproved` | prNumber, repo, reviewerLogin, title | PR aprobado |
| `PrCommented` | prNumber, repo, commenterLogin, commentBody, commentUrl, filePath, line | Comentario nuevo |
| `MainBranchUpdated` | repo, prNumber, mergedBy, headSha | PR mergeado a main |
| `CheckSuiteStarted` / `CheckSuiteCompleted` | checkSuiteId, appName, repo, branch, prNumber, author | Check suite events |

### Gestión de tokens (orden de prioridad)
```
UserPatToken (PAT propio) > AccessToken (OAuth) > GitHub:PatToken (PAT compartido del servidor)
```

### Flujo de OAuth
1. App abre `{backend}/api/auth/login?redirect_uri=http://localhost:{random_port}/callback`
2. Backend redirige a GitHub → usuario autoriza → GitHub redirige a `/api/auth/callback`
3. Backend cambia code por access_token, busca/crea usuario en DB, redirige de vuelta a `localhost`
4. App captura la respuesta en un `NWListener` TCP, extrae `id`, `username`, `avatar`
5. App guarda sesión en Keychain (opcional, si "Keep signed in")

---

## Frontend macOS (`native/`)

### Stack
| Componente | Tecnología |
|------------|-----------|
| UI | SwiftUI (100%, sin storyboards ni xibs) |
| Ventanas | `NSPanel` flotantes para views modales |
| Menú bar | `MenuBarExtra` con estilo `.window` |
| SignalR | `URLSessionWebSocketTask` — protocolo manual (sin librería) |
| OAuth | `NWListener` TCP local para capturar callback |
| Git | Shell out a `git` CLI via `Process` |
| Keychain | Security framework directamente |
| Dependencias externas | **CERO** — solo Apple SDKs |

### Estructura de archivos (34 archivos .swift)

```
native/
├── App/BlameTheGuiltyApp.swift          # @main, MenuBarExtra, LoginItem
├── Models/Models.swift                  # Todos los modelos + backendUrl
├── Services/
│   ├── SignalRService.swift             # WebSocket SignalR + REST polling (595 lines)
│   ├── OAuthService.swift               # GitHub login via NWListener
│   ├── GitService.swift                 # Git CLI actor (checkout, branch, PR, conflict)
│   ├── NotificationManager.swift         # Sonidos + dispatch a CustomNotification
│   ├── CustomNotification.swift          # NSPanel flotante tipo banner
│   ├── ConflictWatcherService.swift      # Detecta conflictos (poll + SignalR)
│   ├── MenuBarBadgeService.swift         # Contadores para el menú bar
│   ├── KeychainService.swift             # Persistencia de sesión
│   └── PersistenceService.swift          # Historial offline de workflows
├── Views/
│   ├── ContentView.swift                 # Popover principal (400×820)
│   ├── MenuBarLabelView.swift            # Label del menú bar (4 modos)
│   ├── SignInCardView.swift              # Botón "Sign in with GitHub"
│   ├── LoggedInCardView.swift            # Avatar + username + sign out
│   ├── KeepSignedInToggleView.swift      # Toggle "Keep me signed in"
│   ├── ActivePRsView.swift               # Lista de PRs con badges de estado
│   ├── PRDetailView.swift                # Popover detalle PR (merge, draft, update)
│   ├── PRDetailPanelManager.swift        # Manager NSPanel para PRDetailView
│   ├── LocalBranchesView.swift           # Repos + ramas local/remote
│   ├── BranchDetailView.swift            # Popover rama (checkout, delete, create PR)
│   ├── BranchDetailPanelManager.swift    # Manager NSPanel para BranchDetailView
│   ├── CreatePRPreviewView.swift         # Formulario crear PR con AI summary
│   ├── PRPreviewPanelManager.swift       # Manager NSPanel para CreatePRPreview
│   ├── QuickSearchView.swift             # Spotlight ⌘K con smart queries
│   ├── WorkflowHistoryView.swift         # Historial de workflows con targets
│   ├── WorkflowHistoryPanelManager.swift # Manager NSPanel para WorkflowHistory
│   ├── WebhookLogView.swift              # Log de webhooks (debug)
│   ├── WebhookLogPanelManager.swift      # Manager NSPanel para WebhookLog
│   ├── LastNotificationCardView.swift    # Último evento de castigo
│   ├── EmptyNotificationView.swift       # Estado vacío
│   ├── SettingsView.swift                # Settings (508 lines)
│   └── SettingsPanelManager.swift        # Manager NSPanel para Settings
└── Utils/
    ├── TeamDefaults.swift                # Defaults hardcodeados del equipo
    └── IDEOpener.swift                   # 27 IDEs detectados + open file/repo
```

### Cómo funciona la app

1. **Inicio**: `SMAppService.mainApp.register()` → auto-arranque al iniciar sesión. `MenuBarExtra` con icono llama + popover.

2. **Login**: `OAuthService` abre Safari para OAuth de GitHub. App recibe callback vía TCP local. Sesión opcional en Keychain.

3. **Tiempo real**: `SignalRService` conecta WebSocket a `wss://{backend}/hub/punishment`. Recibe eventos de workflows, PRs, comentarios, aprobaciones.

4. **PRs activos**: Cada 30s (o al recibir `PullRequestsUpdated`), refetch `GET /api/pullrequests/active`. Muestra tarjetas con color según `ciStatus`:
   - ⚪ DRAFT (gris), 🟡 WAITING (naranja), 🔵 REVIEW (azul), 🔴 FAIL (rojo), 🟢 READY (verde), 🟣 MERGED (púrpura)

5. **Acciones en PRs**: Desde el popover de detalle se puede: togglear draft, merge, update branch, ver comentarios.

6. **Ramas locales**: `GitService` descubre repos recursivamente (max 3 niveles) desde `workspacePath`. Muestra ramas locales (propias del usuario por email) y remotas (vía GitHub API).

7. **Spotlight (⌘K)**: Búsqueda con queries inteligentes: `"945"` → abre ticket Jira, `"checkout fix"` → checkout de rama, `"pr feature"` → crear PR, `"Open Jira Board"` → abre el board.

8. **Detección de conflictos**: Cada 60s + cuando se mergea algo a `main`, calcula si hay overlap entre archivos cambiados en `origin/main` y cambios locales o de la rama activa.

9. **Historial offline**: `PersistenceService` guarda los últimos workflows en `~/Library/Application Support/workflow_history.json`.

### UserDefaults keys

| Key | Default | Para qué |
|-----|---------|----------|
| `backendUrl` | `https://moonlike-silenced-sprung.ngrok-free.dev` | URL del backend |
| `workspacePath` | `~/Desktop/dev` | Dónde buscar repos |
| `jiraBoardUrl` | `https://easyjet.atlassian.net/browse/` | Base para tickets |
| `jiraBoardViewUrl` | URL del board LOY | Vista del board |
| `favoriteRepo` | `dcp-loyalty-monorepo` | Repo favorito |
| `defaultIDE` | `rider` | IDE por defecto |
| `customIDECommand` | `""` | Comando IDE custom |
| `menuBarWidgetMode` | `"Minimal"` | Modo del menú bar |

### Cómo se instala la app (`native/install.sh`)
```bash
xcodebuild -project btg.xcodeproj -scheme BlameTheGuilty -configuration Release build
cp BlameTheGuilty.app ~/Applications/
lsregister -f ~/Applications/BlameTheGuilty.app
pkill -x BlameTheGuilty; open ~/Applications/BlameTheGuilty.app
```

---

## Despliegue

### Servidor (Hetzner VPS)

| Propiedad | Valor |
|-----------|-------|
| Host | `underlayer` (alias SSH) |
| IP | `49.13.88.205` |
| Usuario | `root` |
| SSH key | `~/.ssh/underlayer_ci_deploy` |
| OS | Linux (Debian/Ubuntu) |
| App path | `/opt/blame-the-guilty/` |
| DB path | `/var/lib/blame-the-guilty/blame_the_guilty.db` |

### Servicios systemd

1. **`blame-the-guilty.service`**: Ejecuta `BlameTheGuilty.Api` en `localhost:5000`
2. **`blame-the-guilty-tunnel.service`**: Ejecuta `ngrok http --url=moonlike-silenced-sprung.ngrok-free.dev 5000`

### Cómo desplegar (desde tu Mac)

```bash
# Backend
cd backend
dotnet publish -c Release -r linux-x64 --self-contained -o /tmp/blame-publish
rsync -az --delete /tmp/blame-publish/ underlayer:/opt/blame-the-guilty/
ssh underlayer "sudo systemctl daemon-reload && sudo systemctl restart blame-the-guilty"

# Frontend (macOS)
cd native
bash install.sh
```

### Configuración necesaria en GitHub

1. **GitHub OAuth App** en `github.com/settings/developers`:
   - Homepage URL: `https://moonlike-silenced-sprung.ngrok-free.dev`
   - Callback URL: `https://moonlike-silenced-sprung.ngrok-free.dev/api/auth/callback`
   - Scopes: `read:user`, `repo`
   - Client ID + Secret → `appsettings.json` / `appsettings.Production.json`

2. **Webhook** en cada repo (o a nivel org):
   - URL: `https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github`
   - Eventos: `Workflow runs`, `Check suites`, `Pull requests`, `Pull request reviews`, `Issue comments`, `Pull request review comments`
   - Secret: configurar uno para HMAC verification

3. **PAT compartido** (opcional): en `appsettings.Production.json` → `GitHub:PatToken`

---

## PR status (ciStatus) calculation

`ciStatus` se muestra en cada tarjeta de PR: WAITING, REVIEW, FAIL, READY, DRAFT, MERGED.

### Matching runs to PRs

Workflow runs se matching con PRs por `(repo, headSha, workflowName)`. El `headSha` es el commit SHA del head del PR — solo runs del mismo commit se consideran.

### SyncCheckRunsForCommit

En cada `GET /api/pullrequests/active`, el backend fetchea check-runs de GitHub para cada head SHA único y hace upsert en DB. Esto cubre webhooks perdidos.

### Lógica

1. No workflow runs para ese headSha → `waiting`
2. Any run `in_progress` → `waiting`
3. Any run `failure` → `failed`
4. All runs `success` → `review` (necesita aprobación humana)
5. `review` + `reviewApproved` → `ready`
6. `draft = true` → badge **DRAFT** (gray), overrides CI status
7. PR merged → `merged`

---

## Auth tokens

Cada llamada a GitHub API necesita un token. Orden de resolución:

```
User PAT  >  OAuth token  >  Shared PAT
```

1. **UserPatToken** — PAT configurable por usuario en Settings (scope: `repo`)
2. **AccessToken** — OAuth token del login de GitHub (scope: `read:user,repo`)
3. **PatToken** — token compartido en `appsettings.json` (opcional)

---

## Predictive Conflict Detection

Cuando alguien mergea un PR a main, el backend envía `MainBranchUpdated` via SignalR con repo, PR number, merged-by user, y merge commit SHA.

El `ConflictWatcherService` maneja este evento y también hace poll cada 60s. En cada check:

1. `git fetch origin main`
2. Compara el nuevo SHA de `origin/main` contra el último conocido
3. Si es diferente: `git diff --name-only <last>..origin/main`
4. Obtiene archivos sin commit: `git diff --name-only` + `git ls-files --others`
5. Obtiene diff de la rama actual vs main: `git diff --name-only origin/main...HEAD`
6. Si hay archivos en ambos sets → notificación

Notificaciones deduplicadas por `(repo, file, type)` durante 5 minutos.

---

## Seguridad y Profesionalización

### Problemas de seguridad actuales

| Problema | Riesgo | Gravedad |
|----------|--------|----------|
| ~~Webhook sin HMAC~~ | ✅ Ya implementado — verifica HMAC-SHA256 | ~~Media~~ |
| OAuth client secret en `appsettings.json` | Expuesto si alguien accede al VPS | Media |
| Sin HTTPS entre Kestrel y ngrok | Tráfico en localhost sin cifrar | Baja |
| Sin rate limiting | Posible abuso del endpoint webhook | Baja |
| Secrets en Git (si se comitea `appsettings.Production.json`) | Filtración en GitHub | Alta |

### Cómo profesionalizar (orden recomendado)

#### 1. HMAC verification en webhooks ✅ (implementado)

- Se verifica `X-Hub-Signature-256` usando `HMACSHA256.HashData` con `CryptographicOperations.FixedTimeEquals`
- Si `WebhookSecret` no está configurado (o es el placeholder), se salta la verificación — compatible con setups existentes
- El secreto se lee de configuración (env var `WebhookSecret` o `appsettings.json`)

#### 2. Secrets como environment variables (15 min)

En el service systemd:
```
[Service]
Environment=OAUTH_CLIENT_ID=...
Environment=OAUTH_CLIENT_SECRET=...
Environment=GITHUB_PAT_TOKEN=...
Environment=WEBHOOK_SECRET=...
```

Quitar del `appsettings.json` los valores sensibles. `Program.cs` lee:
```csharp
builder.Configuration.AddEnvironmentVariables();
```

#### 3. Health check endpoint (15 min)

```csharp
app.MapGet("/health", () => Results.Ok(new {
    status = "healthy",
    database = db.Database.CanConnect(),
    timestamp = DateTime.UtcNow
}));
```

#### 4. Logs estructurados con Serilog (30 min)

```bash
dotnet add package Serilog.AspNetCore
dotnet add package Serilog.Sinks.File
```

Rotación diaria, retención 30 días, nivel mínimo Warning en producción.

#### 5. CI/CD con GitHub Actions (2h)

Flujo: push a `main` → `dotnet publish` → `rsync` → `systemctl restart`.

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: dotnet publish -c Release -r linux-x64 --self-contained -o publish
        working-directory: backend
      - run: rsync -az --delete publish/ underlayer:/opt/blame-the-guilty/
      - run: ssh underlayer "sudo systemctl restart blame-the-guilty"
```

Necesitas añadir `SSH_PRIVATE_KEY` y `SSH_KNOWN_HOSTS` como secrets de GitHub.

#### 6. Docker (1h)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Release -r linux-x64 --self-contained -o /app

FROM mcr.microsoft.com/dotnet/runtime-deps:10.0
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:5000
ENTRYPOINT ["./BlameTheGuilty.Api"]
```

Combinado con docker-compose para ngrok:
```yaml
services:
  app:
    build: .
    environment:
      - OAUTH_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}
      - GITHUB_PAT_TOKEN=${GITHUB_PAT_TOKEN}
      - WEBHOOK_SECRET=${WEBHOOK_SECRET}
    volumes:
      - blame-data:/var/lib/blame-the-guilty
    restart: always
  tunnel:
    image: ngrok/ngrok:latest
    command: http http://app:5000 --url=moonlike-silenced-sprung.ngrok-free.dev
    environment:
      - NGROK_AUTHTOKEN=${NGROK_AUTHTOKEN}
    depends_on:
      - app
volumes:
  blame-data:
```

#### 7. Migraciones EF (1h)

Reemplazar `EnsureCreated()` por migrations reales:
```bash
dotnet ef migrations add InitialCreate
dotnet ef database update
```

En producción, aplicar migrations al arrancar:
```csharp
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}
```

#### 8. IP whitelist para webhooks (1h)

GitHub publica sus IPs en `https://api.github.com/meta`. Puedes cachearlas y validar que `Request.HttpContext.Connection.RemoteIpAddress` esté en ese rango. Sobra si ya tienes HMAC.

---

## Costes actuales

| Concepto | Coste |
|----------|-------|
| VPS Hetzner | ~4-6 €/mes |
| ngrok (gratuito) | 0 € (pero URL cambia si no es estática) |
| ngrok estático | ~5-10 $/mes (dominio fijo) |
| Dominio propio | ~10-15 €/año |
| Apple Developer | 99 €/año (solo si subes a App Store) |
| **Total con dominio propio** | **~90-130 €/año + VPS** |
