# Legacy — Implementación Node.js (deprecada)

Esta carpeta contiene la **primera versión** del sistema, escrita en Node.js como un MCP server stdio que asumía Qdrant + Ollama proxy ya levantados externamente. Se conserva como referencia y para usuarios que aún no migran al nuevo stack.

**No recibe mantenimiento.** El camino oficial es el servidor Python en [`../server/`](../server/) levantado con `docker compose up -d`.

## Diferencias principales

| Aspecto             | Legacy (Node)             | Actual (Python)             |
|---------------------|---------------------------|-----------------------------|
| Lenguaje            | Node.js                   | Python 3.11 + FastMCP       |
| Transport MCP       | stdio                     | Streamable HTTP             |
| Vector store        | Qdrant (asume externo)    | Qdrant (en docker-compose)  |
| Embeddings          | nomic-embed-text proxy    | Ollama bge-m3 oficial       |
| Aislamiento         | `collection`              | `namespace` (1 colección)   |
| Tools               | 5 (`memory_add`, `_sync`, `_search`, `_delete`, `_stats`) | 7 (+`update`, `_recent`, `_list`) |
| Setup               | paths hardcoded a `/root/...` | Docker compose self-contained |

## Por qué se reescribió

- **Cero infra externa**: el nuevo stack arranca con `docker compose up -d`. El legacy requería preparar Qdrant + un proxy de embeddings antes.
- **Disciplinas de mantenimiento**: vertical slice + Pydantic + tests unitarios primero. La nueva arquitectura admite añadir tools nuevas en una carpeta, sin tocar las demás.
- **Multilingüe**: `bge-m3` da resultados drásticamente mejores en español que `nomic-embed-text`.

Si dependías del legacy, el upgrade es: `docker compose up -d` y cambiar la config MCP de stdio a HTTP. La forma de los datos cambió (campo `collection` → `namespace`), así que conviene re-ingestar.
