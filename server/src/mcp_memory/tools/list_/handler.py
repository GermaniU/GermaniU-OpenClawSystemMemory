from __future__ import annotations

from pydantic import BaseModel, Field

from mcp_memory.shared.types import Memory, MemoryStore


class ListInput(BaseModel):
    namespace: str | None = Field(None)
    limit: int = Field(50, ge=1, le=500)
    offset: int = Field(0, ge=0)


async def list_memories(inp: ListInput, *, store: MemoryStore) -> list[Memory]:
    return await store.list_(
        namespace=inp.namespace,
        limit=inp.limit,
        offset=inp.offset,
    )
