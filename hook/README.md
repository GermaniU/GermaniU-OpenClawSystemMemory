# Memory Hook MCP Server

MCP server para OpenClaw que expone herramientas para gestionar memorias vectorizadas en Qdrant.

## Características

- ✅ `memory_add`: Agregar memorias individuales a Qdrant
- ✅ `memory_sync`: Sincronizar archivos markdown completos
- ✅ Validación de conexión Qdrant antes de operaciones
- ✅ Error handling graceful (no falla si Qdrant está caído)
- ✅ Auto-creación de colecciones
- ✅ Generación de embeddings vía proxy local

## Instalación

```bash
cd /root/workspace/scratch/2026-02-25/memory-auto-sync/hook
npm install
```

## Configuración

Se pueden configurar las siguientes opciones:

### Via archivo de config (JSON)

En `~/.openclaw/config.json`:
```json
{
  "qdrantUrl": "http://localhost:6333",
  "defaultCollection": "memory_incidents",
  "embeddingModel": "nomic-embed-text",
  "embeddingProxyUrl": "http://localhost:18789"
}
```

### Via variables de entorno

```bash
export QDRANT_URL="http://localhost:6333"
export QDRANT_COLLECTION="memory_incidents"
export EMBEDDING_MODEL="nomic-embed-text"
export OLLAMA_PROXY_URL="http://localhost:18789"
```

## Uso

### Desde OpenClaw

Ejecuta el MCP server desde tu configuración de mcporter:

```json
{
  "mcpServers": {
    "memory": {
      "command": "node",
      "args": ["/root/workspace/scratch/2026-02-25/memory-auto-sync/hook/memory-hook.js"]
    }
  }
}
```

### Tools disponibles

#### `memory_add`

```json
{
  "collection": "memory_incidents",
  "text": "La API de autenticación retorna 403 cuando el token expira",
  "metadata": {
    "priority": "high",
    "component": "auth"
  },
  "source": "debugging-session-2025"
}
```

#### `memory_sync`

```json
{
  "date": "2026-02-25",
  "file_path": "/root/.openclaw/workspace/memory/2026-02-25.md"
}
```

## Estructura del proyecto

```
hook/
├── memory-hook.js      # MCP server principal
├── package.json        # Configuración de dependencias
├── README.md           # Documentación
├── config.example.json # Ejemplo de configuración
└── test/               # Tests (opcional)
```

## Dependencias

- `@modelcontextprotocol/sdk`: ^1.0.4
- Node.js >= 18.0.0

## Health Check

```bash
# Verificar Qdrant disponible
curl localhost:6333/healthz

# Verificar proxy de embeddings
curl localhost:18789/v1/models
```
