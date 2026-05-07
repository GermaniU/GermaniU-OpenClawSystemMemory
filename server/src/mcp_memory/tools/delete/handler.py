from __future__ import annotations

from pydantic import BaseModel, Field

from mcp_memory.shared.types import MemoryStore


class DeleteInput(BaseModel):
    id: str = Field(..., description="Memory id (UUID) returned by memory_save.")


class DeleteResult(BaseModel):
    id: str
    deleted: bool


async def delete(inp: DeleteInput, *, store: MemoryStore) -> DeleteResult:
    deleted = await store.delete(inp.id)
    return DeleteResult(id=inp.id, deleted=deleted)
