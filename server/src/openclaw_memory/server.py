from __future__ import annotations

from typing import Any

import anyio
from fastmcp import FastMCP

from openclaw_memory.shared.config import Settings, get_settings
from openclaw_memory.shared.embeddings import OllamaEmbeddings
from openclaw_memory.shared.store import QdrantStore
from openclaw_memory.shared.types import EmbeddingsClient, Memory, MemoryStore
from openclaw_memory.tools.delete.handler import DeleteInput, DeleteResult, delete
from openclaw_memory.tools.list_.handler import ListInput, list_memories
from openclaw_memory.tools.recent.handler import RecentInput, recent
from openclaw_memory.tools.save.handler import SaveInput, save
from openclaw_memory.tools.search.handler import SearchInput, search
from openclaw_memory.tools.stats.handler import StatsInput, stats
from openclaw_memory.tools.update.handler import UpdateInput, update


def build_app(
    *,
    settings: Settings,
    embeddings: EmbeddingsClient,
    store: MemoryStore,
) -> FastMCP:
    """Compose the FastMCP app. Pure wiring — no business logic here."""
    mcp = FastMCP("openclaw-memory")

    @mcp.tool(name="memory_save", description="Persist a new memory. Returns the saved entry.")
    async def _save(inp: SaveInput) -> Memory:
        return await save(
            inp, embeddings=embeddings, store=store, default_namespace=settings.default_namespace
        )

    @mcp.tool(name="memory_search", description="Semantic search across stored memories.")
    async def _search(inp: SearchInput) -> list[Memory]:
        return await search(inp, embeddings=embeddings, store=store)

    @mcp.tool(name="memory_delete", description="Delete a memory by id.")
    async def _delete(inp: DeleteInput) -> DeleteResult:
        return await delete(inp, store=store)

    @mcp.tool(name="memory_list", description="List memories with pagination.")
    async def _list(inp: ListInput) -> list[Memory]:
        return await list_memories(inp, store=store)

    @mcp.tool(
        name="memory_update", description="Update content/tags/metadata of an existing memory."
    )
    async def _update(inp: UpdateInput) -> Memory | None:
        return await update(inp, embeddings=embeddings, store=store)

    @mcp.tool(name="memory_recent", description="Most recently updated memories.")
    async def _recent(inp: RecentInput) -> list[Memory]:
        return await recent(inp, store=store)

    @mcp.tool(name="memory_stats", description="Counts and namespace summary.")
    async def _stats(inp: StatsInput) -> dict[str, Any]:
        return await stats(inp, store=store)

    return mcp


async def _serve(settings: Settings) -> None:
    store = QdrantStore(
        url=settings.qdrant_url,
        collection=settings.qdrant_collection,
        dim=settings.embedding_dim,
    )
    await store.ensure_collection()
    embeddings = OllamaEmbeddings(
        base_url=settings.ollama_url,
        model=settings.embedding_model,
        api_key=settings.ollama_api_key,
    )
    try:
        app = build_app(settings=settings, embeddings=embeddings, store=store)
        await app.run_async(transport="http", host=settings.mcp_host, port=settings.mcp_port)
    finally:
        await embeddings.aclose()
        await store.aclose()


def main() -> None:
    anyio.run(_serve, get_settings())


if __name__ == "__main__":
    main()
