# Auto-Sync Pipeline - Technical Spec

## Overview
Automated pipeline to sync episodic memory (Markdown files) → semantic memory (Qdrant vectors).

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  memory/*.md    │────▶│   sync-memory   │────▶│   Qdrant      │
│  (episodic)     │     │   script        │     │   (semantic)  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                                              ▲
        │                                              │
        └──────────────────────────────────────────────┘
                           MCP Hook (memory_add tool)
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
     a. Hash content for ID
     b. Generate embedding via llava:7b
     c. Upsert to Qdrant with metadata
  4. Log results
  ```

### 2. memory-hook.js (Backend)
- **Purpose**: Real-time memory addition
- **Methods**:
  - `memory_add`: Add single fact
  - `memory_sync`: Sync specific file
  - `memory_search`: Semantic search
- **Integration**: MCP server for OpenClaw

### 3. validate.sh (QA)
- **Purpose**: Integration tests
- **Coverage**:
  - Qdrant connectivity
  - Embedding proxy health
  - Script functionality
  - Hook API compliance

## Data Flow

### ID Generation
```python
# Stable IDs for deduplication
uuid5(uuid.NAMESPACE_DNS, f"{date}-{content_hash[:16]}")
```

### Vector Dimensions
- **llava:7b**: 4096 dimensions
- **Distance**: Cosine similarity
- **Collections**: memory_facts, memory_incidents

### Metadata Schema
```json
{
  "id": "uuid",
  "text": "content for embedding",
  "original_id": "human-readable-id",
  "date": "2026-02-25",
  "type": "architecture|fix|incident|deployment",
  "source": "session|manual|import"
}
```

## Cron Schedule

```cron
# Sync episodic memory every 6 hours
0 */6 * * * /root/workspace/memory-auto-sync/sync-memory.sh -v >> /var/log/memory-sync.log 2>&1
```

## Validation Checklist

- [ ] Script generates valid embeddings
- [ ] Qdrant accepts 4096-dim vectors
- [ ] Hook responds to MCP calls
- [ ] Deduplication works (same content = same ID)
- [ ] Tests pass in isolated environment

## Rollback

If issues detected:
```bash
# Restore from backup
curl -X POST http://localhost:6333/collections/memory_facts/snapshot/restore \
  -d '{"snapshot_name": "pre-sync-backup"}'
```
