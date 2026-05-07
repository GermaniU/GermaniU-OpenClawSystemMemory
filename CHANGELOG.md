# Changelog

Todos los cambios relevantes del proyecto se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el versionado [SemVer](https://semver.org/lang/es/).

---

## [Unreleased]

### Posibles próximos pasos
- Soporte para `EmbeddingsClient` adicionales (OpenAI, Voyage, Cohere) en paralelo a Ollama.
- Modo Qdrant embedded (sin docker, archivo en disco) para "instalación cero infra".
- Tool `memory_export` (JSONL/Markdown) para portabilidad.
- Tests de integración automatizados (`pytest -m integration`).
- Imagen oficial publicada en Docker Hub / GHCR.

> Estos son posibles, no garantizados. PRs bienvenidos — lee [CONTRIBUTING.md](CONTRIBUTING.md).

---

## [0.1.0] — 2026-05-07

### Reescritura completa: de Node.js stdio a Python MCP HTTP

Primera versión publicable. La implementación previa en Node.js se eliminó del árbol vivo — su trazabilidad permanece en el git history (`git log --before=2026-05-07`).

### Added
- Servidor MCP en **Python 3.11** con [FastMCP](https://gofastmcp.com) (Streamable HTTP, `:8765/mcp`).
- **Vertical-slice architecture**: una carpeta por tool en `server/src/mcp_memory/tools/` con handler aislado.
- **7 tools MCP**:
  - `memory_save` — guardar texto + tags + metadata, embebe automático.
  - `memory_search` — búsqueda semántica con filtro por namespace y `min_score`.
  - `memory_update` — modificar contenido/tags/metadata por id, re-embebe si cambia el contenido.
  - `memory_delete` — borrar por id.
  - `memory_list` — paginación por namespace.
  - `memory_recent` — últimas N por `updated_at`.
  - `memory_stats` — conteo, namespaces, oldest/newest.
- **Namespaces** para separar memoria por proyecto/agente (filtro por payload con índice keyword en Qdrant).
- **Ollama configurable** vía `OLLAMA_URL` + `OLLAMA_API_KEY`: soporta Ollama local, remoto y, en el futuro, cualquier endpoint Ollama-compatible.
- **Modelo de embeddings parametrizable** (`EMBEDDING_MODEL` + `EMBEDDING_DIM`). Default: `bge-m3` (multilingüe, 1024 dims).
- **`docker-compose.yml`** mínimo: solo Qdrant + mcp-memory. Ollama lo aporta el usuario.
- **16 tests unitarios** con `FakeStore` y `FakeEmbeddings` — corren en <0.3s sin Docker ni Ollama.
- **Documentación completa**: [README](README.md), [INSTALL](docs/INSTALL.md), [CLIENTS](docs/CLIENTS.md), [ARCHITECTURE](docs/ARCHITECTURE.md), [CONTRIBUTING](CONTRIBUTING.md).
- **Ejemplos de configuración** listos para Claude Code, OpenCode, Cursor, Continue en [`examples/`](examples/).
- **Imagen OG / social preview** (`docs/assets/og-image.png`).

### Changed
- Transport pasó de **stdio** (Node legacy) a **Streamable HTTP** — funciona con cualquier cliente MCP moderno sin wrappers.
- Aislamiento conceptual cambió de `collection` (Node legacy) a `namespace` — una sola colección Qdrant + filtro por payload.
- Modelo de embeddings default: `nomic-embed-text` (Node, 768 dim, inglés) → `bge-m3` (Python, 1024 dim, multilingüe).
- Setup pasó de paths hardcoded `/root/workspace/...` (Node legacy) a `docker compose up -d` self-contained.

### Discovered (gotchas documentadas)
- **Ollama Cloud (`https://ollama.com`) no expone modelos de embedding** — su catálogo cloud es solo chat (kimi-k2, deepseek, gpt-oss, etc.). `POST /api/embed` devuelve 401 incluso con API key válida para `/api/chat`. Documentado prominentemente en README + INSTALL.
- El protocolo MCP **exige** `Accept: application/json, text/event-stream`. Sin él, FastMCP devuelve 406 / connection reset.
- `EMBEDDING_DIM` debe coincidir EXACTO con la dimensión real del modelo, o Qdrant falla al insertar/buscar.

### Disciplinas aplicadas
Clean Code · SOLID (DIP con `Protocol`) · KISS · YAGNI · Vertical slice · Tests primero.

---

## [Legacy] — 2026-02-26 (Node.js, eliminado del árbol)

Primera implementación. **Eliminada del repo en 2026-05-07** (commit posterior). El código vive en el git history: `git log --all -- 'legacy/**'` lo recupera para inspección histórica.

### Highlights de la versión legacy
- Node.js, MCP **stdio** (`hook/memory-hook.js`, ~580 líneas).
- Asumía Qdrant + proxy de embeddings ya levantados externamente.
- 5 tools: `memory_add`, `memory_sync`, `memory_search`, `memory_delete`, `memory_stats`.
- `nomic-embed-text` (768 dim) como embedding.
- Aislamiento por `collection` (no namespace).
- Setup con paths hardcoded `/root/workspace/scratch/...`.

### Por qué se reescribió
- Cero infra externa: el nuevo stack arranca con un `docker compose up -d`.
- Mantenibilidad: vertical slice + tests unitarios + Pydantic vs ~580 líneas planas en JS sin tests automatizados.
- Multilingüe: `bge-m3` da resultados drásticamente mejores en español que `nomic-embed-text`.

---

[Unreleased]: https://github.com/GermaniU/mcp-memory/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/GermaniU/mcp-memory/releases/tag/v0.1.0
