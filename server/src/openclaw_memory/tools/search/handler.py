from __future__ import annotations

from pydantic import BaseModel, Field

from openclaw_memory.shared.types import EmbeddingsClient, Memory, MemoryStore


class SearchInput(BaseModel):
    query: str = Field(
        ..., description="Free-text query, embedded and matched by cosine similarity."
    )
    namespace: str | None = Field(None, description="Restrict to a single namespace.")
    limit: int = Field(10, ge=1, le=100)
    min_score: float = Field(0.0, ge=0.0, le=1.0)


async def search(
    inp: SearchInput,
    *,
    embeddings: EmbeddingsClient,
    store: MemoryStore,
) -> list[Memory]:
    vector = await embeddings.embed(inp.query)
    return await store.search(
        vector,
        namespace=inp.namespace,
        limit=inp.limit,
        min_score=inp.min_score,
    )
