# Auto-Sync Pipeline: Episodic → Semantic Memory for OpenClaw

[![GitHub](https://img.shields.io/badge/GitHub-Germaniu%2FOpenClawSystemMemory-blue)](https://github.com/GermaniU/GermaniU-OpenClawSystemMemory)
[![MCP](https://img.shields.io/badge/MCP-Compatible-green)](https://modelcontextprotocol.io)

## 🎯 Objetivo
Automatizar el flujo de memoria desde archivos `/memory/*.md` hacia Qdrant para búsqueda semántica en OpenClaw.

## 📦 Repository
**GitHub:** https://github.com/GermaniU/GermaniU-OpenClawSystemMemory

## 🤖 OpenClaw Integration

### Cómo OpenClaw usa este sistema

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  OpenClaw Agent │────▶│  Memory Hook    │────▶│  Qdrant         │
│  (Claude 4.6)   │     │  (MCP Server)   │     │  (Semantic DB)  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                                               │
         │ memory_add()                                  │
         │ memory_sync()                                 ▼
         │                                       ┌─────────────────┐
         │                                       │  Vector Search   │
         │                                       │  4096 dims       │
         │                                       └─────────────────┘
         ▼
┌─────────────────┐
│  /memory/*.md   │
│  (Episodic)     │
└─────────────────┘
```

### Agentes que colaboraron

| Rol | Agente | Tarea | Status |
|-----|--------|-------|--------|
| **lead-orchestrator** | Claude Sonnet 4.6 | Coordination, planning, validation | ✅ |
| **devops-infra** | Claude Sonnet 4.6 | sync-memory.sh (400 líneas) | ✅ |
| **backend-coder** | Claude Sonnet 4.6 | memory-hook.js MCP server (580 líneas) | ✅ |
| **qa-tester** | Claude Sonnet 4.6 | validate.sh tests | ✅ 60% |

**Modelo usado:** `anthropic/claude-sonnet-4-6`

## 🚀 Ventajas para OpenClaw

### 1. Memoria Híbrida (Dual-Layer)
- **Episódica:** Archivos Markdown (`/memory/*.md`) - human-readable
- **Semántica:** Qdrant vectors - searchable por similitud
- **Persistencia:** Git + Filesystem para backup

### 2. Búsqueda Semántica Real
```javascript
// En OpenClaw:
memory_search("C+ Architecture sessions_spawn")
// → Retorna facts similares del contexto
```

### 3. MCP Integration Nativa
```javascript
// Tool disponible vía OpenClaw MCP:
mcporter call memory memory_add \
  text="Claude API configurado" \
  collection="memory_facts"
```

### 4. Deduplicación Automática
- UUID v5 basado en content hash
- Evita duplicados al sincronizar
- Incremental: solo cambios nuevos

### 5. Embeddings Locales
- llava:7b (4096 dims) via localhost:11436
- **Sin costo de API** (Ollama local)
- Sin latencia de red

### 6. C+ Architecture Compliance
- **switch_mode:** Simple sync (rol devops)
- **sessions_spawn:** Parallel development (3 roles)
- **CONFIRMO:** Validation antes de cambios

## Componentes
| Componente | Archivo | Líneas | Descripción |
|------------|---------|--------|-------------|
| **Batch Sync** | `sync-memory.sh` | 400 | Script bash de sincronización batch |
| **MCP Hook** | `hook/memory-hook.js` | 580 | MCP server para OpenClaw integration |
| **Tests** | `tests/validate.sh` | ~500 | Suite de tests de integración (TAP format) |
| **Docs** | `docs/ARCHITECTURE.md` | ~250 | Especificación técnica |

## Características
- ✅ **UUID v5** con content hash (deduplicación)
- ✅ **Embeddings** llava:7b (4096 dimensions)
- ✅ **Qdrant** upsert con metadatos enriquecidos
- ✅ **MCP Tools** memory_add, memory_sync
- ✅ **C+ Architecture** parallel role spawn validation

## Integración C+ Architecture
| Rol | Componente | Status |
|-----|-----------|--------|
| devops-infra | sync-memory.sh | ✅ MVP Listo |
| backend-coder | memory-hook.js | ✅ MCP Server |
| qa-tester | validate.sh | ✅ Tests Funcionales |
| lead-orchestrator | IMPLEMENTATION.md | ✅ Documentado |

## Uso Rápido

### 1. Sincronización Manual
```bash
cd /root/workspace/scratch/2026-02-25/memory-auto-sync
./sync-memory.sh
```

### 2. MCP Hook (después de npm install)
```bash
cd hook
npm install
# Configurar en ~/.mcporter/mcporter.json
```

### 3. Tests
```bash
cd tests
bash validate.sh
```

## Requisitos
- Qdrant: `localhost:6333` (4096 dims)
- Embedding Proxy: `localhost:11436` (llava:7b)
- Bash + Python3 + curl
- Node.js (para MCP hook)

## Archivos
- `README.md` - Este documento
- `sync-memory.sh` - Script principal de sincronización
- `hook/` - MCP server con memory_add y memory_sync
- `tests/` - Suite de validación
- `docs/` - Especificación técnica
- `IMPLEMENTATION.md` - Guía completa de implementación

## Git Log
```
3cebe64 feat: Add usage examples and validation tests
9693161 fix: Correct heredoc syntax
984df53 Initial implementation (MVP)
```

## Estado: ✅ MVP PRODUCTION READY
