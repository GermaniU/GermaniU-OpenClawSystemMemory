# Arquitectura

## Decisiones de diseño

### Vertical slice

```
server/src/openclaw_memory/
├── server.py                 # composition root: wiring FastMCP + dependencias
├── shared/                   # solo lo verdaderamente compartido
│   ├── config.py             # pydantic-settings, .env
│   ├── embeddings.py         # OllamaEmbeddings (httpx)
│   ├── store.py              # QdrantStore (qdrant-client async)
│   └── types.py              # Memory + Protocols (EmbeddingsClient, MemoryStore)
└── tools/                    # 1 carpeta = 1 slice MCP
    ├── save/handler.py       # SaveInput + async save(...)
    ├── search/handler.py
    ├── delete/handler.py
    ├── list_/handler.py
    ├── update/handler.py
    ├── recent/handler.py
    └── stats/handler.py
```

Cada slice es **una función pura** que recibe sus dependencias por keyword arguments. Esto significa:

- **Test unitario sin Docker**: `pytest tests/unit` corre con un `FakeStore` y `FakeEmbeddings` in-memory. 16 tests, <0.3s.
- **Añadir una tool nueva**: una carpeta nueva en `tools/`, un decorador `@mcp.tool` en `server.py`. Cero acoplamiento con las existentes (OCP).

### SOLID, sin sobreingeniería

- **SRP**: cada handler hace una cosa. `EmbeddingsClient` solo embebe. `MemoryStore` solo persiste.
- **DIP**: handlers dependen de `Protocol` (`EmbeddingsClient`, `MemoryStore`), no de `OllamaEmbeddings`/`QdrantStore`. Por eso los fakes son triviales — no requieren herencia.
- **OCP**: `tools/` es abierto a extensión, cerrado a modificación. Añadir una tool ≠ tocar otras.
- **Sin** factories, builders, registries dinámicos. Wiring explícito en `server.build_app`.

### KISS + YAGNI

- Una sola colección Qdrant; namespaces se filtran por payload con índice keyword. Sin colecciones por namespace ni por usuario. Suficiente hasta los millones de vectores.
- `recent` y `stats` no usan agregaciones nativas de Qdrant — un `scroll` + sort en Python es legible y rápido para volúmenes humanos. Se puede optimizar el día que importe (no antes).
- El servidor expone solo `streamable-http`. stdio se añade cuando un usuario real lo pida.
- Modelo de embeddings inyectable vía `.env`, dimensión también. No hay "registry de modelos".

### Tests

- **Unit (16)**: `tests/unit/tools/` — 1 archivo por slice, cubre happy path + 1-2 edge cases. Usan `FakeStore` y `FakeEmbeddings` (cosine sobre vector determinista de SHA-256, 16 dims).
- **Integration (futuro)**: `tests/integration/test_e2e.py` — levanta `docker compose`, hace MCP requests, verifica round-trip. Marcado `@pytest.mark.integration`, no corre por defecto.

### Datos

```
Memory {
  id: UUID
  content: str
  namespace: str
  tags: list[str]
  metadata: dict
  created_at, updated_at: datetime UTC
  score: float | None  # solo en respuestas de search
}
```

En Qdrant: vector + payload con todos los campos excepto `id` (que es el id del point) y `score` (calculado al buscar). `created_at`/`updated_at` se serializan como floats (epoch seconds) para indexar fácilmente.

### Flujo `memory_save`

1. Cliente MCP llama `memory_save(content, namespace?, tags?, metadata?)`.
2. Handler valida (Pydantic) y rechaza contenido vacío.
3. Genera UUID v4 y timestamps.
4. Llama `embeddings.embed(content)` → vector de `EMBEDDING_DIM` floats.
5. `store.save(memory, vector)` hace `upsert` en Qdrant.
6. Devuelve la `Memory` resultante al cliente.

### Flujo `memory_search`

1. Cliente llama `memory_search(query, namespace?, limit, min_score)`.
2. `embeddings.embed(query)` → vector.
3. `store.search(...)` ejecuta `query_points` con `score_threshold` y filtro por `namespace` (índice keyword).
4. Devuelve `[Memory]` ordenadas por similitud descendente, cada una con `score`.

## No-goals (por ahora)

- **Multi-usuario / multi-tenant**: el repo asume "una persona, una máquina". Aislamiento entre proyectos = namespaces.
- **Auth/ACL**: solo escucha en `localhost`. Si publicas el puerto a internet, eres responsable de poner un proxy con auth.
- **Soporte multimodal** (imágenes, PDF como blobs).
- **Sync entre máquinas**. Backup manual con `tar` del volumen Qdrant es suficiente para 99% de casos.

Si alguno de estos se vuelve necesario, abre un issue con caso de uso real (no especulativo).
