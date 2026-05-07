# OpenClaw System Memory

> **Memoria local para tus agentes IA, vía MCP. Levantas Qdrant, configuras tu Ollama, pegas la URL en tu cliente y listo.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![MCP](https://img.shields.io/badge/MCP-Streamable_HTTP-green)](https://modelcontextprotocol.io)
[![Python](https://img.shields.io/badge/Python-3.11+-3776AB?logo=python&logoColor=white)](server/pyproject.toml)

Un servidor [MCP](https://modelcontextprotocol.io) que da a cualquier agente compatible (Claude Code, OpenCode, Cursor, Continue…) **memoria persistente con búsqueda semántica**:

- 🦙 **Embeddings** vía cualquier endpoint Ollama-compatible — **Ollama Cloud**, tu Ollama local, o un servidor remoto.
- 🔍 **Vector search** con [Qdrant](https://qdrant.tech) (cosine, payload indexes).
- 🧩 **Namespaces** para separar memoria por proyecto/agente.
- 🛠 **7 tools MCP**: `memory_save`, `memory_search`, `memory_delete`, `memory_list`, `memory_update`, `memory_recent`, `memory_stats`.
- 🐳 Docker-friendly **pero no obligatorio**.

---

## ⚡ Quickstart con Docker (3 pasos)

```bash
git clone https://github.com/GermaniU/GermaniU-OpenClawSystemMemory.git
cd GermaniU-OpenClawSystemMemory
cp .env.example .env
# edita .env: OLLAMA_API_KEY (cloud) o OLLAMA_URL=http://host.docker.internal:11434 (local)
docker compose up -d
```

Solo levanta dos contenedores: **Qdrant** (vector DB) y **mcp-memory** (servidor MCP). Ollama lo aportas tú — cloud o tu Mac.

Endpoint MCP: `http://localhost:8765/mcp`. Pégalo en la config de tu cliente ([`docs/CLIENTS.md`](docs/CLIENTS.md)).

---

## ⚡ Quickstart sin Docker (Python local)

Si ya tienes Qdrant en otro lado (servidor propio, Qdrant Cloud, …) y prefieres correr el MCP server como proceso Python:

```bash
git clone https://github.com/GermaniU/GermaniU-OpenClawSystemMemory.git
cd GermaniU-OpenClawSystemMemory/server
python -m venv .venv && source .venv/bin/activate
pip install -e .

# configura
export OLLAMA_URL=https://ollama.com
export OLLAMA_API_KEY=...
export QDRANT_URL=http://localhost:6333   # o tu Qdrant remoto
export EMBEDDING_MODEL=bge-m3
export EMBEDDING_DIM=1024

python -m openclaw_memory
# Listening on http://0.0.0.0:8765/mcp
```

---

## 🦙 Modos de Ollama

| Modo | `OLLAMA_URL` | `OLLAMA_API_KEY` |
|---|---|---|
| **Ollama Cloud** (default) | `https://ollama.com` | tu API key |
| **Ollama local** (Mac/Linux) | `http://host.docker.internal:11434` (en docker) o `http://localhost:11434` (sin docker) | _vacío_ |
| **Ollama remoto** (tu servidor) | `https://ollama.tu-dominio.com` | opcional, según tu proxy |

> **Importante**: el modelo configurado en `EMBEDDING_MODEL` debe estar disponible en el endpoint que elijas. Ollama Cloud no expone públicamente todos los modelos de embedding — verifica antes de elegir uno.

---

## 🛠 Tools expuestos

| Tool             | Para qué |
|------------------|----------|
| `memory_save`    | Guardar texto + tags + metadata; embebe automáticamente. |
| `memory_search`  | Búsqueda semántica con filtro por namespace y `min_score`. |
| `memory_update`  | Cambiar contenido/tags/metadata por id. Re-embebe si cambia el contenido. |
| `memory_delete`  | Borrar por id. |
| `memory_list`    | Paginado por namespace. |
| `memory_recent`  | Las últimas N por `updated_at`. |
| `memory_stats`   | Conteo, namespaces, oldest/newest. |

---

## 🧱 Arquitectura

```
┌─ tu agente (Claude Code / OpenCode / Cursor / …) ─┐
│           │ MCP streamable HTTP                    │
│           ▼                                        │
│    localhost:8765/mcp                              │
└────────────┬───────────────────────────────────────┘
             │
   ┌─────────▼────────┐         ┌─────────────────┐
   │   mcp-memory     │────────▶│  Ollama (cloud  │
   │   (Python+MCP)   │         │  o local)       │
   └─────────┬────────┘         └─────────────────┘
             │
             ▼
   ┌──────────────────┐
   │      Qdrant      │  ← docker compose o standalone
   └──────────────────┘
```

Vertical-slice: cada tool MCP vive en su propia carpeta con handler aislado, fácil de entender y testear sin levantar nada (`pytest tests/unit`, 16 tests, <0.3s).

Detalle: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## 📚 Docs

- [`docs/INSTALL.md`](docs/INSTALL.md) — instalación detallada, variables, troubleshooting.
- [`docs/CLIENTS.md`](docs/CLIENTS.md) — config para Claude Code, OpenCode, Cursor, Continue.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — decisiones técnicas y por qué.
- [`legacy/`](legacy/) — primera implementación en Node (deprecada, se conserva como referencia).

---

## 🤝 Cómo contribuir

```bash
cd server
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
pytest -q                     # 16 tests unitarios sin Docker ni Ollama
ruff check src tests
```

Disciplinas del repo: **Clean Code · SOLID · KISS · YAGNI · vertical slice · tests primero**. Una tool nueva = una carpeta nueva en `server/src/openclaw_memory/tools/`.

---

## 📄 Licencia

[MIT](LICENSE) — úsalo, fórkalo, regálale a otra gente más memoria local.
