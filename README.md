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

#### Trabajo Original (Inicial)
| Rol | Agente | Tarea | Status |
|-----|--------|-------|--------|
| **lead-orchestrator** | Claude Sonnet 4.6 | Coordination, planning, validation | ✅ |
| **devops-infra** | Claude Sonnet 4.6 | sync-memory.sh (400 líneas) | ✅ |
| **backend-coder** | Claude Sonnet 4.6 | memory-hook.js MCP server (580 líneas) | ✅ |
| **qa-tester** | Claude Sonnet 4.6 | validate.sh tests | ✅ 60% |

**Modelo usado (Inicial):** `anthropic/claude-sonnet-4-6`

#### Trabajo de Mejora (Este Desarrollo)
| Rol | Agente | Tarea | Status |
|-----|--------|-------|--------|
| **builder-orchestrator** | GLM-4.7 (Qwen3-Coder-Next) | Coordinación, delegación, planificación | ✅ |
| **backend-coder** | GLM-4.7 (Qwen3-Coder-Next) | 5 herramientas MCP + bug fixes | ✅ |
| **qa-tester** | GLM-4.7 (Qwen3-Coder-Next) | 6 tests de QA (todos pasan) | ✅ |
| **code-reviewer** | GLM-4.7 (Qwen3-Coder-Next) | 0 bloqueadores, 4 sugerencias opcionales | ✅ |

**Modelo usado (Mejora):** `zai/glm-4.7` y `ollama/qwen3-coder-next:cloud`

**Mejoras implementadas:**
- 5 herramientas MCP: add, sync, search, delete, stats
- Filtros por metadata en búsqueda semántica
- Corrección de 4 bugs críticos (endpoint DELETE, UUID v4, variables de entorno)
- Validación QA completa (6 tests pasando)
- README completo con ejemplos de uso

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

mcporter call memory memory_search \
  text="C+ Architecture sessions_spawn" \
  collection="memory_facts" \
  limit=3

mcporter call memory memory_stats \
  collection="memory_facts"

mcporter call memory memory_delete \
  collection="memory_facts" \
  point_id="uuid-del-punto"
```

### 4. Deduplicación Automática
- UUID v5 basado en content hash
- Evita duplicados al sincronizar
- Incremental: solo cambios nuevos

### 5. Embeddings Locales
- **nomic-embed-text** (768 dims) via localhost:11436
- Otros modelos disponibles: mxbai-embed-large (1024 dims)
- **Sin costo de API** (Ollama Cloud Proxy)
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
- ✅ **UUID v4** con content hash (deduplicación)
- ✅ **Embeddings** nomic-embed-text (768 dims) o mxbai-embed-large (1024 dims)
- ✅ **Qdrant** upsert con metadatos enriquecidos
- ✅ **5 MCP Tools** memory_add, memory_sync, memory_search, memory_delete, memory_stats
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
- `hook/` - MCP server con 5 herramientas
  - `memory-hook.js` - MCP server principal (5 herramientas)
  - `README.md` - Documentación completa del servidor
  - `USAGE.js` - Ejemplos de uso
  - `package.json` - Configuración de dependencias
  - `config.example.json` - Ejemplo de configuración
- `tests/` - Suite de validación
- `docs/` - Especificación técnica
- `IMPLEMENTATION.md` - Guía completa de implementación

## Git Log
```
3cebe64 feat: Add usage examples and validation tests
9693161 fix: Correct heredoc syntax
984df53 Initial implementation (MVP)
```

## Estado: ✅ PRODUCTION READY (5 Herramientas MCP)

**Último commit:** `7a1e349` - docs: actualizar README con modelo embeddings, dimensión y roles participantes

**Herramientas MCP disponibles:**
- ✅ `memory_add` - Agregar memorias con UUID v4
- ✅ `memory_sync` - Sincronizar archivos markdown
- ✅ `memory_search` - Búsqueda semántica con filtros por metadata
- ✅ `memory_delete` - Eliminar por ID o query semántica
- ✅ `memory_stats` - Estadísticas de colección

**Validación QA:** 6/6 tests pasan
- QA-001: memory_add (UUID v4 válido)
- QA-002: memory_search (score > 0.7)
- QA-003: memory_search (filtros por metadata)
- QA-004: memory_stats (status green)
- QA-005: memory_delete (ID)
- QA-006: memory_delete (query semántica)
