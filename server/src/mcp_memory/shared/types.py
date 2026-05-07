from __future__ import annotations

from datetime import datetime
from typing import Protocol

from pydantic import BaseModel, Field


class Memory(BaseModel):
    """A single memory entry as returned to MCP clients."""

    id: str
    content: str
    namespace: str
    tags: list[str] = Field(default_factory=list)
    metadata: dict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime
    score: float | None = None


class EmbeddingsClient(Protocol):
    async def embed(self, text: str) -> list[float]: ...


class MemoryStore(Protocol):
    async def save(self, memory: Memory, vector: list[float]) -> Memory: ...
    async def update(
        self,
        memory_id: str,
        *,
        content: str | None,
        tags: list[str] | None,
        metadata: dict | None,
        vector: list[float] | None,
    ) -> Memory | None: ...
    async def delete(self, memory_id: str) -> bool: ...
    async def search(
        self,
        vector: list[float],
        *,
        namespace: str | None,
        limit: int,
        min_score: float,
    ) -> list[Memory]: ...
    async def list_(
        self,
        *,
        namespace: str | None,
        limit: int,
        offset: int,
    ) -> list[Memory]: ...
    async def recent(self, *, namespace: str | None, limit: int) -> list[Memory]: ...
    async def stats(self, *, namespace: str | None) -> dict: ...
