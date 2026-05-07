# Instalación detallada

Hay dos modos: **con Docker** (recomendado para no pelearse con Python) y **sin Docker** (proceso Python directo).

---

## ⚠️ Pre-requisito: Ollama con un modelo de embeddings

Antes de levantar nada, asegúrate de que tu Ollama responde con embeddings. **Ollama Cloud (`https://ollama.com`) no ofrece este endpoint** — solo modelos de chat. Necesitas Ollama local o remoto:

```bash
# Instala Ollama (si aún no): https://ollama.com/download
ollama pull bge-m3              # multilingüe, recomendado
# o:
ollama pull mxbai-embed-large   # alta calidad, inglés
ollama pull nomic-embed-text    # ligero, inglés

# Verifica que responde:
curl -X POST http://localhost:11434/api/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"model":"bge-m3","prompt":"hola"}' | head -c 200
# Debe imprimir un JSON con un array {"embedding":[...]}
```

Si esto no funciona, no sigas — el resto fallará con `401`/`404`.

---

## Modo A — Docker

### Requisitos

- **Docker** ≥ 24 con Compose v2.
- Un endpoint de Ollama disponible:
  - Ollama Cloud → API key.
  - Ollama local en tu Mac → `host.docker.internal` (Docker Desktop lo resuelve).
  - Ollama remoto → URL pública.
- Puertos libres: `8765` (MCP), `6333` (Qdrant).

### Pasos

```bash
git clone https://github.com/GermaniU/mcp-memory.git
cd mcp-memory
cp .env.example .env
# Edita .env (ver tabla abajo)
docker compose up -d
docker compose logs -f mcp-memory
```

### Variables (`.env`)

| Variable             | Default               | Descripción |
|----------------------|-----------------------|-------------|
| `OLLAMA_URL`         | `http://host.docker.internal:11434` | Endpoint Ollama. **Cloud NO sirve para embeddings** — usa local o remoto. |
| `OLLAMA_API_KEY`     | _vacío_               | Solo si tu endpoint requiere `Authorization: Bearer …`. |
| `EMBEDDING_MODEL`    | `bge-m3`              | Modelo Ollama. Debe estar `ollama pull`-ed en tu Ollama. |
| `EMBEDDING_DIM`      | `1024`                | **Debe coincidir EXACTO** con el modelo: bge-m3=1024, mxbai-embed-large=1024, nomic-embed-text=768. |
| `MCP_PORT`           | `8765`                | Puerto del MCP en el host. |
| `QDRANT_COLLECTION`  | `mcp_memory`     | Nombre interno de la colección Qdrant. |
| `DEFAULT_NAMESPACE`  | `default`             | Namespace cuando el cliente no especifica uno. |

Tras editar `.env`: `docker compose up -d` (recrea solo lo necesario).

---

## Modo B — Sin Docker (proceso Python)

### Requisitos

- Python 3.11+.
- Qdrant disponible — local (`docker run -p 6333:6333 qdrant/qdrant`), Qdrant Cloud, o uno tuyo.
- Endpoint Ollama (cloud, local o remoto).

### Pasos

```bash
git clone https://github.com/GermaniU/mcp-memory.git
cd mcp-memory/server
python -m venv .venv && source .venv/bin/activate
pip install -e .

export OLLAMA_URL=https://ollama.com
export OLLAMA_API_KEY=...
export QDRANT_URL=http://localhost:6333
export EMBEDDING_MODEL=bge-m3
export EMBEDDING_DIM=1024

python -m mcp_memory
```

> Tip: pon esas variables en un `.env` y carga con `direnv` o `dotenv` en lugar de `export` manual.

---

## Cambiar de modelo de embedding

```bash
# 1. Ajusta EMBEDDING_MODEL y EMBEDDING_DIM
# 2. Borra la colección (los vectores viejos no son compatibles con otra dim)
curl -X DELETE http://localhost:6333/collections/mcp_memory
# 3. Recrea
docker compose up -d --force-recreate mcp-memory
```

---

## Backups

Toda la memoria vive en el volumen `qdrant-data`:

```bash
docker run --rm \
  -v mcp-memory_qdrant-data:/data \
  -v "$PWD":/backup \
  alpine tar czf /backup/qdrant-$(date +%Y%m%d).tar.gz -C /data .
```

---

## Apagar / desinstalar

```bash
docker compose down              # apaga, conserva datos
docker compose down -v           # ↑ y borra los volúmenes (¡pierdes la memoria!)
```

---

## Troubleshooting

**`mcp-memory` reinicia en bucle**
- `docker compose logs mcp-memory`. Causas frecuentes:
  - `OLLAMA_API_KEY` mal o ausente cuando tu endpoint la pide.
  - Modelo `EMBEDDING_MODEL` no disponible en tu Ollama (`ollama list` debería mostrarlo).
  - Qdrant aún no levantó — espera unos segundos.

**Mi Ollama corre en mi Mac, no me conecta desde el contenedor**
- En `.env`: `OLLAMA_URL=http://host.docker.internal:11434` y deja `OLLAMA_API_KEY` vacío.
- En Linux nativo (no Docker Desktop): añade `--add-host=host.docker.internal:host-gateway` (ya está en el compose).

**Quiero ver Qdrant**
- UI web: <http://localhost:6333/dashboard>. Solo lectura recomendada.

**Puerto 8765 ocupado**
- Cambia `MCP_PORT` en `.env` y reinicia.

**`memory_search` devuelve vacío**
- Verifica el namespace: si guardaste sin namespace y buscas con `namespace: "x"`, no coincide.
- Baja `min_score` a 0.0 para diagnosticar (luego súbelo a 0.5–0.7 en producción).
