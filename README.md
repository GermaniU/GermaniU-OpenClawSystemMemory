# Auto-Sync Pipeline: Memory Episódica → Semántica

[![GitHub](https://img.shields.io/badge/GitHub-Germaniu%2FOpenClawSystemMemory-blue)](https://github.com/GermaniU/OpenClawSystemMemory)

## Objetivo
Automatizar el flujo de memoria desde archivos `/memory/*.md` hacia Qdrant para búsqueda semántica en OpenClaw.

## Repository
**GitHub:** https://github.com/GermaniU/OpenClawSystemMemory

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
