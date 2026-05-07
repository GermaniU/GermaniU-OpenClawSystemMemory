# Contribuir a MCP Memory

¡Gracias por interesarte! Este documento define **cómo se construye** y **cómo se contribuye** al proyecto. Léelo antes de mandar un PR — los detalles aquí son la diferencia entre un PR que se mergea rápido y uno que pide cambios.

---

## 🎯 Filosofía

> **Software pequeño, bien hecho, fácil de mantener.**

MCP Memory es deliberadamente reducido. Hace **una cosa** (memoria semántica de texto plano vía MCP) y la hace bien. No vamos a añadir features especulativas. Cada línea de código que entra al repo tiene que justificar su mantenimiento.

---

## 📐 Disciplinas (no negociables)

### Clean Code
- Nombres claros en inglés. Si necesitas un comentario para explicar qué hace una función, primero intenta renombrar la función.
- Funciones cortas, una responsabilidad. Una función no debe pedir más de 4-5 parámetros — si los necesita, probablemente debería ser una clase.
- Sin código muerto. Si está comentado o no se usa, se borra.

### SOLID (sin sobreingeniería)
- **SRP**: cada handler hace una cosa. `EmbeddingsClient` solo embebe. `MemoryStore` solo persiste.
- **DIP**: handlers dependen de `Protocol` (`EmbeddingsClient`, `MemoryStore`), no de `OllamaEmbeddings`/`QdrantStore`. Esto permite tests sin Docker.
- **OCP**: añadir una tool nueva = una carpeta nueva. **No se modifican slices existentes** salvo bug fix.
- **No** factories, **no** builders, **no** registries dinámicos. Wiring explícito en `server.build_app`.

### KISS · YAGNI
- Si solo hay una implementación, **no hay interfaz**. La interfaz aparece cuando aparece la segunda implementación o cuando la necesita un test.
- No se añaden features "por si acaso". Tres líneas similares es mejor que una abstracción prematura.
- No se añade error handling para escenarios que no pueden pasar. Confía en el framework. Valida solo en los bordes (entrada del usuario, APIs externas).

### Vertical slice architecture
```
server/src/mcp_memory/
├── server.py                 # composition root: wiring FastMCP + dependencias
├── shared/                   # solo lo verdaderamente compartido entre slices
│   ├── config.py · embeddings.py · store.py · types.py
└── tools/                    # 1 carpeta = 1 slice MCP
    ├── save/handler.py · search/handler.py · …
```
**Cada slice es independiente.** Si tocas `save/`, no tocas `search/`. Tests de cada slice viven aparte.

### Tests primero (TDD bienvenido)
- **Lógica con reglas** → escribe el test antes que el handler.
- **Wiring/glue** (server.py, factories) → tests de integración cubren esto, no hace falta TDD.
- Cada PR con código nuevo trae sus tests. **No se acepta lógica sin tests.**
- Los tests usan `FakeStore` y `FakeEmbeddings` (in-memory, deterministas). No requieren Docker ni Ollama.

### Comentarios
- **Por defecto, no escribas comentarios.** Un nombre bien elegido y una función pequeña ya cuentan el "qué".
- Solo añade comentarios cuando expliquen el **WHY** (decisión, restricción no obvia, workaround). Nunca el "what" (eso lo dice el código).
- Sin comentarios tipo `# bug fix de issue #42` o `# usado por X` — eso pertenece al PR, no al código.

---

## 📝 Convenciones

### Idioma
- **Identifiers (clases, funciones, variables, files)**: inglés.
- **Comentarios y docstrings**: español si aportan, inglés si más natural — el criterio es claridad.
- **Commits, PRs, issues**: español.
- **Documentación (`docs/`, README)**: español.

### Conventional Commits (en español)
```
feat: añadir tool memory_export
fix: corregir filtro de namespace en search
docs: aclarar el setup de Ollama remoto
refactor: extraer payload mapping a helpers
test: cubrir caso de namespace vacío en list
chore: actualizar dependencias
```

Mensaje en imperativo, primera línea ≤ 72 chars, cuerpo opcional explicando el **WHY**.

### Pull Request
- **1 PR = 1 propósito.** No mezclar feature + refactor + bumps de deps.
- Título en formato Conventional Commit.
- Cuerpo del PR responde: **qué cambia, por qué, cómo lo probaste**.
- CI verde (tests + ruff). Local: `pytest -q && ruff check src tests`.

---

## 🛠 Setup de desarrollo

```bash
git clone https://github.com/GermaniU/mcp-memory.git
cd mcp-memory/server
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

# Ejecutar tests (16, sin Docker ni Ollama, <1s)
pytest -q

# Lint + format
ruff check src tests
ruff format src tests
```

Para tests de integración (necesitan stack docker + Ollama con `bge-m3`):

```bash
docker compose up -d
pytest -m integration   # cuando existan
```

---

## 🆕 Cómo añadir una tool MCP

Pongamos que quieres añadir `memory_export`. Sigue este flujo y tu PR pasa rápido:

### 1. Crea la slice

```
server/src/mcp_memory/tools/export/
├── __init__.py    # vacío
└── handler.py     # ExportInput + async export(...)
```

`handler.py`:

```python
from __future__ import annotations
from pydantic import BaseModel, Field
from mcp_memory.shared.types import MemoryStore


class ExportInput(BaseModel):
    namespace: str | None = Field(None)
    format: str = Field("jsonl", pattern="^(jsonl|markdown)$")


async def export(inp: ExportInput, *, store: MemoryStore) -> str:
    items = await store.list_(namespace=inp.namespace, limit=10_000, offset=0)
    # … serializar al formato elegido
    return "..."
```

### 2. Escribe tests (antes que la implementación si haces TDD)

```
server/tests/unit/tools/test_export.py
```

Con `FakeStore` y `FakeEmbeddings` ya disponibles en `conftest.py`. Cubre:
- Happy path.
- Filtro por namespace.
- 1-2 edge cases (vacío, formato inválido).

### 3. Cablea en `server.py`

Añade el decorator junto a las otras tools — **no toques las existentes**:

```python
from mcp_memory.tools.export.handler import ExportInput, export

@mcp.tool(name="memory_export", description="Exportar memorias en JSONL o Markdown.")
async def _export(inp: ExportInput) -> str:
    return await export(inp, store=store)
```

### 4. Actualiza docs

- README: añade fila a la tabla de tools.
- `docs/CLIENTS.md`: ejemplo de invocación si tiene argumentos no obvios.

### 5. PR

Conventional commit, descripción clara, tests pasando.

---

## 🧪 Cómo añadir un EmbeddingsClient nuevo (ej: OpenAI, Voyage)

Casi igual al flujo de tool, pero el archivo va en `shared/embeddings_<provider>.py` y debe cumplir el `Protocol` `EmbeddingsClient` (`async def embed(text) -> list[float]`).

Cambia el wiring en `server.py` para elegir el provider según `.env`. **No toques `OllamaEmbeddings`** — añade el nuevo en paralelo.

---

## 🚫 Lo que NO va a entrar (sin issue + caso de uso real previo)

- Multi-tenant / multi-usuario.
- UI web propia.
- Sync entre máquinas.
- Auth / ACL (si lo expones a internet, pon un proxy).
- Soporte multimodal (imágenes, PDFs binarios, audio, gráficas).
- Plugins, marketplace, registries dinámicos.

Si crees que tu caso justifica una excepción, abre un issue **antes** del PR con el caso real (no especulativo).

---

## 🤔 Preguntas frecuentes

**¿Por qué Qdrant y no SQLite + sqlite-vec / ChromaDB / LanceDB?**
- Qdrant tiene la API filtros/payload-indexes más ergonómica para namespaces, escala muy bien y separa "almacenamiento" de "código". sqlite-vec es excelente pero acopla migration al cliente; lo evaluamos para una versión 0-deps en el futuro.

**¿Por qué Python y no Go/Rust/Node?**
- SDK MCP más maduro en Python (FastMCP). Stack ligero (~80MB imagen). Ecosistema rico de embedding clients. Si en el futuro queremos un binario único, se reescribirá.

**¿Por qué no hay UI?**
- KISS. Tu agente es la UI. Para inspección manual está el dashboard de Qdrant en `:6333/dashboard`.

**¿Puedo guardar PDFs / imágenes?**
- No directamente. Extrae el texto antes (OCR / parser) y guarda el texto. La memoria es **texto plano por diseño**.

---

## 📜 Código de conducta

Trato profesional, en cualquier idioma. Críticas a código, no a personas. Si algo del repo te molesta, abre un issue con propuesta concreta.

---

¡Gracias por contribuir! 🙏 Cada PR que hace este proyecto más útil para alguien más es la razón por la que es open source.
