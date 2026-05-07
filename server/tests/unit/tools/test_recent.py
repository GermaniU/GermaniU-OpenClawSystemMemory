import asyncio

from openclaw_memory.tools.recent.handler import RecentInput, recent
from openclaw_memory.tools.save.handler import SaveInput, save


async def test_recent_orders_by_updated_at_desc(embeddings, store):
    a = await save(
        SaveInput(content="a"), embeddings=embeddings, store=store, default_namespace="default"
    )
    await asyncio.sleep(0.01)
    b = await save(
        SaveInput(content="b"), embeddings=embeddings, store=store, default_namespace="default"
    )
    out = await recent(RecentInput(limit=2), store=store)
    assert [m.id for m in out] == [b.id, a.id]
