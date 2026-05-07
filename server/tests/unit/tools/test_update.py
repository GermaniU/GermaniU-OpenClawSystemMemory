import asyncio

from openclaw_memory.tools.save.handler import SaveInput, save
from openclaw_memory.tools.update.handler import UpdateInput, update


async def test_update_changes_content_and_bumps_updated_at(embeddings, store):
    saved = await save(
        SaveInput(content="v1"), embeddings=embeddings, store=store, default_namespace="default"
    )
    await asyncio.sleep(0.01)
    out = await update(
        UpdateInput(id=saved.id, content="v2"),
        embeddings=embeddings,
        store=store,
    )
    assert out is not None
    assert out.content == "v2"
    assert out.id == saved.id
    assert out.updated_at > saved.updated_at


async def test_update_only_tags_keeps_content(embeddings, store):
    saved = await save(
        SaveInput(content="v1", tags=["a"]),
        embeddings=embeddings,
        store=store,
        default_namespace="default",
    )
    out = await update(
        UpdateInput(id=saved.id, tags=["b", "c"]), embeddings=embeddings, store=store
    )
    assert out is not None
    assert out.content == "v1"
    assert out.tags == ["b", "c"]


async def test_update_missing_returns_none(embeddings, store):
    out = await update(
        UpdateInput(id="00000000-0000-0000-0000-000000000000", content="x"),
        embeddings=embeddings,
        store=store,
    )
    assert out is None
