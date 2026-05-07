# Auto-Sync Pipeline - Technical Spec

## Overview
Automated pipeline to sync episodic memory (Markdown files) → semantic memory (Qdrant vectors).

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  memory/*.md   │────▶│  sync-memory   │────▶│   Qdrant        │
│  (episódica)   │     │  script        │     │  (semántica)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                                              ▲
        │                                              │
        └──────────────────────────────────────────────────────┘
                           │
                           ┌──────────────────┐
                           │  memory-hook.js  │
                           │  MCP Server      │
                           │  • memory_add    │
                           │  • memory_sync   │
                           │  • memory_search │
                           │  • memory_delete │
                           │  • memory_stats  │
                           └──────────────────┘
                                    ▲
                           OpenClaw (real-time)
```

## Components

### 1. sync-memory.sh (DevOps)
- **Purpose**: Batch sync markdown files to Qdrant
- **Trigger**: Manual, cron, or post-session
- **Algorithm**:
  ```
  1. List all .md files in /memory/
  2. Parse headers (##, ###)
  3. For each section:
     a. Generate ID with UUID v4
     b. Generate embedding via nomic-embed-text
     c. Upsert to Qdrant with metadata
     d. Log results
  ```

### 2. memory-hook.js (Backend)
- **Purpose**: Real-time memory management
- **Methods**:
  - `memory_add`: Add single fact
  - `memory_sync`: Sync specific file
  - `memory_search`: Semantic search with filters
  - `memory_delete`: Delete by ID or query
  - `memory_stats`: Collection statistics
- **Integration**: MCP server for OpenClaw

### 3. validate.sh (QA)
- **Purpose**: Integration tests
- **Coverage**:
  - Qdrant connectivity
  - Embedding proxy health
  - Script functionality
  - Hook API compliance (all 5 tools)

## Data Flow

### ID Generation
```javascript
// UUID v4 estándar para pointIds válidos
function generateUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}
```

### Vector Dimensions
- **nomic-embed-text**: 768 dimensions
- **Distance**: Cosine similarity
- **Collections**: memory_facts, memory_incidents, test_memory_points

### Metadata Schema
```json
{
  "id": "uuid-v4",
  "text": "content for embedding",
  "source": "memory_hook",
  "timestamp": "2026-02-26T12:33:00Z",
  "text_preview": "Texto de la memoria..."
}
```

## Cron Schedule

```cron
# Sync episodic memory every 6 hours
0 */6 * * * /root/workspace/scratch/2026-02-25/memory-auto-sync/sync-memory.sh -v >> /var/log/memory-sync.log 2>&1
```

## Validation Checklist

- [x] Script generates valid embeddings
- [x] Qdrant accepts 768-dim vectors
- [x] Hook responds to MCP calls (all 5 tools)
- [x] Deduplication works (UUID v4 unique)
- [x] Tests pass (6/6 QA tests)
- [x] Delete endpoint correct (POST /collections/{collection}/points/delete)

## Rollback

If issues detected:
```bash
# Restore from backup
curl -X POST http://localhost:6333/collections/memory_facts/snapshot/restore \
  -d '{"snapshot_name": "pre-sync-backup"}'
```

## MCP Tools Specification

### memory_add
- **Purpose**: Add single memory to Qdrant
- **Parameters**: collection, text, metadata, source
- **Returns**: { success, pointId, collection, message }

### memory_sync
- **Purpose**: Sync entire markdown file to Qdrant
- **Parameters**: date, file_path
- **Returns**: { success, message, details: { added, failed, sections } }

### memory_search
- **Purpose**: Semantic search with metadata filters
- **Parameters**: collection, text, limit, score_threshold, filter
- **Returns**: { success, collection, query, count, results: [ { id, score, text, metadata } ] }

### memory_delete
- **Purpose**: Delete by ID or semantic query
- **Parameters**: collection, point_id OR query, limit, score_threshold
- **Returns**: { success, collection, pointId OR deleted, pointIds }

### memory_stats
- **Purpose**: Get collection statistics
- **Parameters**: collection
- **Returns**: { success, collection, exists, points_count, segments_count, status, config }

## Bug Fixes Implemented

| ID | Bug | Fix |
|----|-----|-----|
| BUG-001 | Endpoint DELETE eliminaba toda la colección | Corregido a `POST /collections/{collection}/points/delete` |
| BUG-002 | Validación incorrecta en DELETE | Cambiado a `data.status === 'ok'` |
| BUG-003 | Variable de entorno incorrecta | Corregido a `EMBEDDING_PROXY_URL` |
| BUG-004 | PointId string inválido | Implementado `generateUUID()` con UUID v4 |

## Modelos y Tecnologías

### Embeddings
- **Modelo**: nomic-embed-text (por defecto)
- **Dimensión**: 768
- **Alternativo**: mxbai-embed-large (1024 dimensiones)
- **Proxy**: localhost:11436

### Servicios
- **Qdrant**: localhost:6333
- **Embedding Proxy**: localhost:11436

### LLM
- **Principal**: zai/glm-4.7 (Qwen3-Coder-Next)
- **Alternativo**: ollama/qwen3-coder-next:cloud

## References

- Toolplaybook: /root/.openclaw/workspace/docs/TOOLPLAYBOOK.md
- hook/README.md: Documentación completa de las 5 herramientas
- Qdrant API: https://qdrant.tech/documentation/
- MCP Spec: https://modelcontextprotocol.io/

---

**Last Updated**: 2026-02-26
**Commit**: da6bb45 - docs: actualizar README principal
