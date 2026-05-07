from __future__ import annotations

import hashlib
from datetime import UTC, datetime
from typing import Any

import pytest

from mcp_memory.shared.types import EmbeddingsClient, Memory, MemoryStore


class FakeEmbeddings(EmbeddingsClient):
    """Deterministic 16-dim vector from a SHA-256 of the text — enough for unit tests."""

    dim = 16

    async def embed(self, text: str) -> list[float]:
        digest = hashlib.sha256(text.encode("utf-8")).digest()
        chunk = max(1, len(digest) // self.dim)
        return [b / 255.0 for b in digest[: self.dim * chunk : chunk]][: self.dim]


class FakeStore(MemoryStore):
    """In-memory store. Uses cosine on stored vectors. Order: insertion."""

    def __init__(self) -> None:
        self._items: dict[str, tuple[Memory, list[float]]] = {}

    async def save(self, memory: Memory, vector: list[float]) -> Memory:
        self._items[memory.id] = (memory, vector)
        return memory

    async def update(
        self,
        memory_id: str,
        *,
        content: str | None,
        tags: list[str] | None,
        metadata: dict | None,
        vector: list[float] | None,
    ) -> Memory | None:
        if memory_id not in self._items:
            return None
        existing, existing_vec = self._items[memory_id]
        updated = existing.model_copy(
            update={
                "content": content if content is not None else existing.content,
                "tags": tags if tags is not None else existing.tags,
                "metadata": metadata if metadata is not None else existing.metadata,
                "updated_at": datetime.now(UTC),
            }
        )
        self._items[memory_id] = (updated, vector or existing_vec)
        return updated

    async def delete(self, memory_id: str) -> bool:
        return self._items.pop(memory_id, None) is not None

    async def search(
        self,
        vector: list[float],
        *,
        namespace: str | None,
        limit: int,
        min_score: float,
    ) -> list[Memory]:
        scored: list[tuple[float, Memory]] = []
        for mem, vec in self._items.values():
            if namespace and mem.namespace != namespace:
                continue
            score = _cosine(vector, vec)
            if score < min_score:
                continue
            scored.append((score, mem.model_copy(update={"score": score})))
        scored.sort(key=lambda s: s[0], reverse=True)
        return [m for _, m in scored[:limit]]

    async def list_(
        self,
        *,
        namespace: str | None,
        limit: int,
        offset: int,
    ) -> list[Memory]:
        items = [m for m, _ in self._items.values() if not namespace or m.namespace == namespace]
        return items[offset : offset + limit]

    async def recent(self, *, namespace: str | None, limit: int) -> list[Memory]:
        items = [m for m, _ in self._items.values() if not namespace or m.namespace == namespace]
        items.sort(key=lambda m: m.updated_at, reverse=True)
        return items[:limit]

    async def stats(self, *, namespace: str | None) -> dict[str, Any]:
        items = [m for m, _ in self._items.values() if not namespace or m.namespace == namespace]
        if not items:
            return {"count": 0, "namespaces": [], "oldest": None, "newest": None}
        return {
            "count": len(items),
            "namespaces": sorted({m.namespace for m in items}),
            "oldest": min(m.created_at for m in items).isoformat(),
            "newest": max(m.updated_at for m in items).isoformat(),
        }


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b, strict=False))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(y * y for y in b) ** 0.5
    return dot / (na * nb) if na and nb else 0.0


@pytest.fixture
def embeddings() -> FakeEmbeddings:
    return FakeEmbeddings()


@pytest.fixture
def store() -> FakeStore:
    return FakeStore()
