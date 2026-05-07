from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from qdrant_client import AsyncQdrantClient
from qdrant_client.http import models as qm

from openclaw_memory.shared.types import Memory


class QdrantStore:
    """MemoryStore backed by a single Qdrant collection. Namespaces live in payload."""

    def __init__(self, *, url: str, collection: str, dim: int) -> None:
        self._client = AsyncQdrantClient(url=url)
        self._collection = collection
        self._dim = dim

    async def ensure_collection(self) -> None:
        existing = await self._client.get_collections()
        if any(c.name == self._collection for c in existing.collections):
            return
        await self._client.create_collection(
            collection_name=self._collection,
            vectors_config=qm.VectorParams(size=self._dim, distance=qm.Distance.COSINE),
        )
        await self._client.create_payload_index(
            collection_name=self._collection,
            field_name="namespace",
            field_schema=qm.PayloadSchemaType.KEYWORD,
        )
        await self._client.create_payload_index(
            collection_name=self._collection,
            field_name="updated_at",
            field_schema=qm.PayloadSchemaType.FLOAT,
        )

    async def save(self, memory: Memory, vector: list[float]) -> Memory:
        await self._client.upsert(
            collection_name=self._collection,
            points=[
                qm.PointStruct(
                    id=memory.id,
                    vector=vector,
                    payload=_to_payload(memory),
                )
            ],
        )
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
        existing = await self._fetch(memory_id)
        if existing is None:
            return None
        updated = existing.model_copy(
            update={
                "content": content if content is not None else existing.content,
                "tags": tags if tags is not None else existing.tags,
                "metadata": metadata if metadata is not None else existing.metadata,
                "updated_at": datetime.now(UTC),
            }
        )
        if vector is not None:
            await self._client.upsert(
                collection_name=self._collection,
                points=[qm.PointStruct(id=updated.id, vector=vector, payload=_to_payload(updated))],
            )
        else:
            await self._client.set_payload(
                collection_name=self._collection,
                payload=_to_payload(updated),
                points=[updated.id],
            )
        return updated

    async def delete(self, memory_id: str) -> bool:
        if await self._fetch(memory_id) is None:
            return False
        await self._client.delete(
            collection_name=self._collection,
            points_selector=qm.PointIdsList(points=[memory_id]),
        )
        return True

    async def search(
        self,
        vector: list[float],
        *,
        namespace: str | None,
        limit: int,
        min_score: float,
    ) -> list[Memory]:
        result = await self._client.query_points(
            collection_name=self._collection,
            query=vector,
            limit=limit,
            score_threshold=min_score or None,
            query_filter=_namespace_filter(namespace),
            with_payload=True,
        )
        return [_from_payload(p.payload, point_id=str(p.id), score=p.score) for p in result.points]

    async def list_(
        self,
        *,
        namespace: str | None,
        limit: int,
        offset: int,
    ) -> list[Memory]:
        points, _ = await self._client.scroll(
            collection_name=self._collection,
            scroll_filter=_namespace_filter(namespace),
            limit=limit + offset,
            with_payload=True,
        )
        sliced = points[offset : offset + limit]
        return [_from_payload(p.payload, point_id=str(p.id)) for p in sliced]

    async def recent(self, *, namespace: str | None, limit: int) -> list[Memory]:
        points, _ = await self._client.scroll(
            collection_name=self._collection,
            scroll_filter=_namespace_filter(namespace),
            limit=10_000,
            with_payload=True,
        )
        memories = [_from_payload(p.payload, point_id=str(p.id)) for p in points]
        memories.sort(key=lambda m: m.updated_at, reverse=True)
        return memories[:limit]

    async def stats(self, *, namespace: str | None) -> dict[str, Any]:
        points, _ = await self._client.scroll(
            collection_name=self._collection,
            scroll_filter=_namespace_filter(namespace),
            limit=10_000,
            with_payload=True,
        )
        if not points:
            return {"count": 0, "namespaces": [], "oldest": None, "newest": None}
        memories = [_from_payload(p.payload, point_id=str(p.id)) for p in points]
        return {
            "count": len(memories),
            "namespaces": sorted({m.namespace for m in memories}),
            "oldest": min(m.created_at for m in memories).isoformat(),
            "newest": max(m.updated_at for m in memories).isoformat(),
        }

    async def _fetch(self, memory_id: str) -> Memory | None:
        points = await self._client.retrieve(
            collection_name=self._collection,
            ids=[memory_id],
            with_payload=True,
        )
        if not points:
            return None
        return _from_payload(points[0].payload, point_id=str(points[0].id))

    async def aclose(self) -> None:
        await self._client.close()


def _namespace_filter(namespace: str | None) -> qm.Filter | None:
    if namespace is None:
        return None
    return qm.Filter(
        must=[qm.FieldCondition(key="namespace", match=qm.MatchValue(value=namespace))]
    )


def _to_payload(memory: Memory) -> dict[str, Any]:
    return {
        "content": memory.content,
        "namespace": memory.namespace,
        "tags": memory.tags,
        "metadata": memory.metadata,
        "created_at": memory.created_at.timestamp(),
        "updated_at": memory.updated_at.timestamp(),
    }


def _from_payload(
    payload: dict[str, Any] | None, *, point_id: str, score: float | None = None
) -> Memory:
    p = payload or {}
    return Memory(
        id=point_id,
        content=p.get("content", ""),
        namespace=p.get("namespace", ""),
        tags=list(p.get("tags") or []),
        metadata=dict(p.get("metadata") or {}),
        created_at=datetime.fromtimestamp(p.get("created_at", 0), tz=UTC),
        updated_at=datetime.fromtimestamp(p.get("updated_at", 0), tz=UTC),
        score=score,
    )
