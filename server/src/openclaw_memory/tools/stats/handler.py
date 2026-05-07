from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

from openclaw_memory.shared.types import MemoryStore


class StatsInput(BaseModel):
    namespace: str | None = Field(None)


async def stats(inp: StatsInput, *, store: MemoryStore) -> dict[str, Any]:
    return await store.stats(namespace=inp.namespace)
