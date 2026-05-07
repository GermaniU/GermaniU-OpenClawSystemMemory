from mcp_memory.tools.save.handler import SaveInput, save
from mcp_memory.tools.stats.handler import StatsInput, stats


async def test_stats_empty_store_returns_zero(store):
    out = await stats(StatsInput(), store=store)
    assert out["count"] == 0
    assert out["namespaces"] == []


async def test_stats_counts_and_collects_namespaces(embeddings, store):
    await save(
        SaveInput(content="a", namespace="ns1"),
        embeddings=embeddings,
        store=store,
        default_namespace="default",
    )
    await save(
        SaveInput(content="b", namespace="ns2"),
        embeddings=embeddings,
        store=store,
        default_namespace="default",
    )
    out = await stats(StatsInput(), store=store)
    assert out["count"] == 2
    assert out["namespaces"] == ["ns1", "ns2"]
