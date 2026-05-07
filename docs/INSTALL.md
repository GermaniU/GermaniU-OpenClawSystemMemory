# Instalación detallada

Hay dos modos: **con Docker** (recomendado para no pelearse con Python) y **sin Docker** (proceso Python directo).

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
git clone https://github.com/GermaniU/GermaniU-OpenClawSystemMemory.git
cd GermaniU-OpenClawSystemMemory
cp .env.example .env
# Edita .env (ver tabla abajo)
docker compose up -d
docker compose logs -f mcp-memory
```

### Variables (`.env`)

| Variable             | Default               | Descripción |
|----------------------|-----------------------|-------------|
| `OLLAMA_URL`         | `https://ollama.com`  | Endpoint Ollama. Cloud, local o remoto. |
| `OLLAMA_API_KEY`     | _vacío_               | Solo si tu endpoint requiere `Authorization: Bearer …`. |
| `EMBEDDING_MODEL`    | `bge-m3`              | Modelo Ollama. Debe estar disponible en `OLLAMA_URL`. |
| `EMBEDDING_DIM`      | `1024`                | Dimensión del modelo (bge-m3=1024, nomic-embed-text=768). |
| `MCP_PORT`           | `8765`                | Puerto del MCP en el host. |
| `QDRANT_COLLECTION`  | `openclaw_memory`     | Nombre interno de la colección Qdrant. |
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
git clone https://github.com/GermaniU/GermaniU-OpenClawSystemMemory.git
cd GermaniU-OpenClawSystemMemory/server
python -m venv .venv && source .venv/bin/activate
pip install -e .

export OLLAMA_URL=https://ollama.com
export OLLAMA_API_KEY=...
export QDRANT_URL=http://localhost:6333
export EMBEDDING_MODEL=bge-m3
export EMBEDDING_DIM=1024

python -m openclaw_memory
```

> Tip: pon esas variables en un `.env` y carga con `direnv` o `dotenv` en lugar de `export` manual.

---

## Cambiar de modelo de embedding

```bash
# 1. Ajusta EMBEDDING_MODEL y EMBEDDING_DIM
# 2. Borra la colección (los vectores viejos no son compatibles con otra dim)
curl -X DELETE http://localhost:6333/collections/openclaw_memory
# 3. Recrea
docker compose up -d --force-recreate mcp-memory
```

---

## Backups

Toda la memoria vive en el volumen `qdrant-data`:

```bash
docker run --rm \
  -v openclawsystemmemory_qdrant-data:/data \
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
