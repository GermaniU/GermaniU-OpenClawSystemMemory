# Memory Hook MCP Server

MCP server para OpenClaw que expone herramientas para gestionar memorias vectorizadas en Qdrant.

## 🌟 Características

- ✅ `memory_add`: Agregar memorias individuales a Qdrant
- ✅ `memory_sync`: Sincronizar archivos markdown completos
- ✅ `memory_search`: Búsqueda semántica con filtros por metadata
- ✅ `memory_delete`: Eliminar memorias por ID o query semántica
- ✅ `memory_stats`: Obtener estadísticas de colecciones
- ✅ Validación de conexión Qdrant antes de operaciones
- ✅ Error handling graceful (no falla si Qdrant está caído)
- ✅ Auto-creación de colecciones
- ✅ Generación de embeddings vía proxy local
- ✅ UUID v4 para pointIds válidos

## 📦 Instalación

```bash
cd /root/workspace/scratch/2026-02-25/memory-auto-sync/hook
npm install
```

## ⚙️ Configuración

Se pueden configurar las siguientes opciones:

### Via mcporter.json

En `~/.mcporter/mcporter.json`:
```json
{
  "mcpServers": {
    "memory": {
      "command": "node",
      "args": ["/root/workspace/scratch/2026-02-25/memory-auto-sync/hook/memory-hook.js"],
      "transport": "stdio",
      "disabled": false,
      "env": {
        "QDRANT_URL": "http://localhost:6333",
        "EMBEDDING_PROXY_URL": "http://localhost:11436"
      }
    }
  }
}
```

### Via variables de entorno

```bash
export QDRANT_URL="http://localhost:6333"
export EMBEDDING_PROXY_URL="http://localhost:11436"
```

**Nota:** `EMBEDDING_PROXY_URL` tiene fallback a `OLLAMA_PROXY_URL` si no está configurado.

## 🚀 Uso

### Tools disponibles (5 herramientas)

#### 1. `memory_add` - Agregar memoria

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

**Respuesta:**
```json
{
  "success": true,
  "pointId": "uuid-v4-valido",
  "collection": "memory_incidents",
  "message": "Memory added to collection 'memory_incidents'"
}
```

---

#### 2. `memory_sync` - Sincronizar archivo markdown

```json
{
  "date": "2026-02-25",
  "file_path": "/root/.openclaw/workspace/memory/2026-02-25.md"
}
```

**Respuesta:**
```json
{
  "success": true,
  "message": "Synced 5/5 sections from /root/.openclaw/workspace/memory/2026-02-25.md",
  "details": {
    "added": 5,
    "failed": 0,
    "sections": 5
  }
}
```

---

#### 3. `memory_search` - Búsqueda semántica

```json
{
  "collection": "memory_facts",
  "text": "API de autenticación",
  "limit": 3,
  "score_threshold": 0.7
}
```

**Con filtro por metadata:**
```json
{
  "collection": "memory_facts",
  "text": "API de autenticación",
  "limit": 5,
  "filter": {
    "must": [
      {
        "key": "source",
        "match": {
          "value": "memory_hook"
        }
      }
    ]
  }
}
```

**Respuesta:**
```json
{
  "success": true,
  "collection": "memory_facts",
  "query": "API de autenticación",
  "count": 3,
  "results": [
    {
      "id": "uuid-del-punto",
      "score": 0.95,
      "text": "Texto de la memoria...",
      "metadata": {
        "source": "memory_hook",
        "timestamp": "2026-02-26T12:33:00Z",
        "text_preview": "Texto de la memoria..."
      }
    }
  ]
}
```

---

#### 4. `memory_delete` - Eliminar memoria

**Por ID:**
```json
{
  "collection": "memory_facts",
  "point_id": "uuid-del-punto"
}
```

**Por query semántica:**
```json
{
  "collection": "memory_facts",
  "query": "textos duplicados de prueba",
  "limit": 5,
  "score_threshold": 0.8
}
```

**Respuesta:**
```json
{
  "success": true,
  "collection": "memory_facts",
  "pointId": "uuid-del-punto",
  "message": "Memory deleted from collection 'memory_facts'"
}
```

---

#### 5. `memory_stats` - Estadísticas de colección

```json
{
  "collection": "memory_facts"
}
```

**Respuesta:**
```json
{
  "success": true,
  "collection": "memory_facts",
  "exists": true,
  "points_count": 42,
  "segments_count": 2,
  "status": "green",
  "optimizer_status": "ok",
  "config": {
    "vector_size": 768,
    "distance": "Cosine"
  }
}
```

## 📂 Estructura del proyecto

```
hook/
├── memory-hook.js      # MCP server principal (5 herramientas)
├── package.json        # Configuración de dependencias
├── package-lock.json   # Lockfile
├── README.md           # Esta documentación
├── USAGE.js            # Ejemplos de uso
├── config.example.json # Ejemplo de configuración
└── .gitignore         # Archivos ignorados
```

## 📦 Dependencias

- `@modelcontextprotocol/sdk`: ^1.0.4
- Node.js >= 18.0.0

## 🔍 Health Check

```bash
# Verificar Qdrant disponible
curl localhost:6333/healthz

# Verificar proxy de embeddings
curl localhost:11436/api/tags

# Verificar el servidor MCP
mcporter list | grep memory
```

## 🧪 Validación QA

Todos los tests de QA pasan:

| Test ID | Herramienta | Resultado |
|---------|-------------|-----------|
| QA-001 | memory_add | ✅ PASS (UUID v4 válido) |
| QA-002 | memory_search | ✅ PASS (score > 0.7) |
| QA-003 | memory_search (filtros) | ✅ PASS (filter aplicado) |
| QA-004 | memory_stats | ✅ PASS (status green) |
| QA-005 | memory_delete (ID) | ✅ PASS (punto eliminado) |
| QA-006 | memory_delete (query) | ✅ PASS (batch delete) |

## 🐛 Bugs Corregidos

| ID | Bug | Fix |
|----|-----|-----|
| BUG-001 | Endpoint DELETE eliminaba toda la colección | Corregido a `POST /collections/{collection}/points/delete` |
| BUG-002 | Validación incorrecta en DELETE | Cambiado a `data.status === 'ok'` |
| BUG-003 | Variable de entorno incorrecta | Corregido a `EMBEDDING_PROXY_URL` |
| BUG-004 | PointId string inválido | Implementado `generateUUID()` con UUID v4 |

## 📝 Cambios Recientes

**Commit:** `2957615` - feat(memory): servidor MCP memory con 5 herramientas estables

- Implementadas 5 herramientas completas
- Corregidos 4 bugs críticos
- Validación QA: 6 tests pasan
- Code review: 0 bloqueadores, 4 sugerencias opcionales

## 🔗 Documentación Adicional

- `TOOLPLAYBOOK.md` en `/root/.openclaw/workspace/docs/`
- `USAGE.js` para ejemplos adicionales
- Referencia de Qdrant API: https://qdrant.tech/documentation/
