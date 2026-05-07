from openclaw_memory.tools.delete.handler import DeleteInput, delete
from openclaw_memory.tools.save.handler import SaveInput, save


async def test_delete_existing_returns_true(embeddings, store):
    saved = await save(
        SaveInput(content="x"),
        embeddings=embeddings,
        store=store,
        default_namespace="default",
    )
    out = await delete(DeleteInput(id=saved.id), store=store)
    assert out.deleted is True
    assert out.id == saved.id


async def test_delete_missing_returns_false(store):
    out = await delete(DeleteInput(id="00000000-0000-0000-0000-000000000000"), store=store)
    assert out.deleted is False
