from __future__ import annotations

from pydantic import BaseModel, Field

from openclaw_memory.shared.types import EmbeddingsClient, Memory, MemoryStore


class UpdateInput(BaseModel):
    id: str = Field(...)
    content: str | None = Field(None)
    tags: list[str] | None = Field(None)
    metadata: dict | None = Field(None)


async def update(
    inp: UpdateInput,
    *,
    embeddings: EmbeddingsClient,
    store: MemoryStore,
) -> Memory | None:
    new_vector = await embeddings.embed(inp.content) if inp.content else None
    return await store.update(
        inp.id,
        content=inp.content,
        tags=inp.tags,
        metadata=inp.metadata,
        vector=new_vector,
    )
