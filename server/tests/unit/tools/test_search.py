from mcp_memory.tools.save.handler import SaveInput, save
from mcp_memory.tools.search.handler import SearchInput, search


async def test_search_returns_most_similar_first(embeddings, store):
    for txt in ["el gato come pescado", "la receta de la abuela", "el perro ladra fuerte"]:
        await save(
            SaveInput(content=txt),
            embeddings=embeddings,
            store=store,
            default_namespace="default",
        )

    out = await search(
        SearchInput(query="el gato come pescado", limit=2),
        embeddings=embeddings,
        store=store,
    )
    assert len(out) == 2
    assert out[0].content == "el gato come pescado"
    assert out[0].score is not None and out[0].score >= (out[1].score or 0)


async def test_search_filters_by_namespace(embeddings, store):
    await save(
        SaveInput(content="a", namespace="ns1"),
        embeddings=embeddings,
        store=store,
        default_namespace="default",
    )
    await save(
        SaveInput(content="a", namespace="ns2"),
        embeddings=embeddings,
        store=store,
        default_namespace="default",
    )

    out = await search(SearchInput(query="a", namespace="ns1"), embeddings=embeddings, store=store)
    assert len(out) == 1
    assert out[0].namespace == "ns1"


async def test_search_returns_empty_when_no_matches_above_min_score(embeddings, store):
    await save(
        SaveInput(content="hola"), embeddings=embeddings, store=store, default_namespace="default"
    )
    out = await search(
        SearchInput(query="completamente otra cosa", min_score=0.99),
        embeddings=embeddings,
        store=store,
    )
    assert out == []
