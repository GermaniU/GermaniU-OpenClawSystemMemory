from __future__ import annotations

from pydantic import BaseModel, Field

from mcp_memory.shared.types import Memory, MemoryStore


class RecentInput(BaseModel):
    namespace: str | None = Field(None)
    limit: int = Field(10, ge=1, le=100)


async def recent(inp: RecentInput, *, store: MemoryStore) -> list[Memory]:
    return await store.recent(namespace=inp.namespace, limit=inp.limit)
