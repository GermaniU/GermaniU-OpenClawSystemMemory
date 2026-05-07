from __future__ import annotations

import uuid
from datetime import UTC, datetime

from pydantic import BaseModel, Field

from mcp_memory.shared.types import EmbeddingsClient, Memory, MemoryStore


class SaveInput(BaseModel):
    content: str = Field(..., description="Memory content (free text).")
    namespace: str | None = Field(
        None, description="Logical bucket. Defaults to server's default_namespace."
    )
    tags: list[str] = Field(default_factory=list)
    metadata: dict = Field(default_factory=dict)


async def save(
    inp: SaveInput,
    *,
    embeddings: EmbeddingsClient,
    store: MemoryStore,
    default_namespace: str,
) -> Memory:
    content = inp.content.strip()
    if not content:
        raise ValueError("content must not be empty")

    now = datetime.now(UTC)
    memory = Memory(
        id=str(uuid.uuid4()),
        content=content,
        namespace=inp.namespace or default_namespace,
        tags=inp.tags,
        metadata=inp.metadata,
        created_at=now,
        updated_at=now,
    )
    vector = await embeddings.embed(content)
    return await store.save(memory, vector)
