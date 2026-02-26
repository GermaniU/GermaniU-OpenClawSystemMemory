# Memory Hook - MCP Server para OpenClaw

**Sistema de memoria híbrida con búsqueda semántica en Qdrant.**

[![GitHub](https://img.shields.io/badge/GitHub-Germaniu%2FOpenClawSystemMemory-blue)](https://github.com/GermaniU/GermaniU-OpenClawSystemMemory)
[![MCP](https://img.shields.io/badge/MCP-Compatible-green)](https://modelcontextprotocol.io)

---

## 🎯 Objetivo

Sistema de memoria para OpenClaw que combina:
- **Memoria episódica:** Archivos Markdown (human-readable)
- **Búsqueda semántica:** Qdrant vectors (buscable por similitud)
- **5 herramientas MCP:** Para agregar, buscar, eliminar y estadísticas

---

## 📦 Instalación

```bash
cd /root/workspace/scratch/2026-02-25/memory-auto-sync/hook
npm install
```

---

## 🚀 Uso Rápido

### 1. Configurar en mcporter.json

```json
{
  "mcpServers": {
    "memory": {
      "command": "node",
      "args": ["/root/workspace/scratch/2026-02-25/memory-auto-sync/hook/memory-hook.js"],
      "transport": "stdio",
      "env": {
        "QDRANT_URL": "http://localhost:6333",
        "EMBEDDING_PROXY_URL": "http://localhost:11436"
      }
    }
  }
}
```

### 2. Usar desde OpenClaw

```javascript
// Agregar memoria
memory_add({
  text: "La API de autenticación retorna 403 cuando el token expira",
  collection: "memory_facts"
})

// Buscar memoria
memory_search({
  text: "autenticación",
  collection: "memory_facts",
  limit: 3
})

// Estadísticas
memory_stats({ collection: "memory_facts" })
```

---

## 🔧 Herramientas MCP (5)

| Herramienta | Descripción |
|-------------|-------------|
| `memory_add` | Agregar memorias individuales |
| `memory_sync` | Sincronizar archivos markdown |
| `memory_search` | Búsqueda semántica + filtros por metadata |
| `memory_delete` | Eliminar por ID o query semántica |
| `memory_stats` | Estadísticas de colección |

---

## 🧠 Embeddings

- **Modelo:** `nomic-embed-text` (768 dimensiones)
- **Alternativo:** `mxbai-embed-large` (1024 dimensiones)
- **Distance:** Cosine

---

## 📂 Estructura del Proyecto

```
memory-auto-sync/
├── hook/
│   ├── memory-hook.js      # MCP Server (5 herramientas)
│   ├── README.md           # Documentación detallada
│   └── package.json        # Dependencias
├── sync-memory.sh          # Script de sincronización
└── README.md               # Este documento (resumen)
```

---

## 📚 Documentación Detallada

- **hook/README.md** - Documentación completa de las 5 herramientas
- **USAGE.js** - Ejemplos de uso
- **docs/TOOLPLAYBOOK.md** - Reglas de uso en el workspace

---

## 🔍 Validación

**Todos los tests de QA pasan (6/6):**

- ✅ memory_add - UUID v4 válido
- ✅ memory_search - Búsqueda semántica funcional
- ✅ memory_search - Filtros por metadata
- ✅ memory_stats - Estadísticas de colección
- ✅ memory_delete - Eliminación por ID
- ✅ memory_delete - Eliminación por query semántica

---

## 🌐 Repositorio

**GitHub:** https://github.com/GermaniU/GermaniU-OpenClawSystemMemory.git

**Estado:** ✅ Production Ready (5 herramientas MCP funcionando)

---

## 📝 Cambios Recientes

**Último commit:** `7a1e349` - Documentación completa del servidor

**Herramientas implementadas:**
- memory_add, memory_sync, memory_search, memory_delete, memory_stats

**Bugs corregidos:**
- Endpoint DELETE corregido
- Validación de respuesta mejorada
- Variables de entorno configuradas
- UUID v4 implementado

---

## 🤖 Tecnologías

- **Qdrant** - Vector DB (768 dims, Cosine)
- **Ollama Cloud Proxy** - Embeddings locales
- **Node.js** - MCP Server
- **Model Context Protocol** - Integración OpenClaw

---

## 📄 Licencia

MIT

---

*Para más detalles, ver [hook/README.md](hook/README.md)*
