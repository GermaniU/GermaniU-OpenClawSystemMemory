from __future__ import annotations

import httpx


class OllamaEmbeddings:
    """Thin async client for Ollama's /api/embeddings endpoint.

    Works for both local Ollama (http://host:11434) and Ollama Cloud
    (https://ollama.com) — the only difference is whether api_key is set.
    """

    def __init__(
        self,
        *,
        base_url: str,
        model: str,
        api_key: str | None = None,
        timeout: float = 60.0,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._model = model
        headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        self._client = httpx.AsyncClient(timeout=timeout, headers=headers)

    async def embed(self, text: str) -> list[float]:
        resp = await self._client.post(
            f"{self._base_url}/api/embeddings",
            json={"model": self._model, "prompt": text},
        )
        resp.raise_for_status()
        data = resp.json()
        embedding = data.get("embedding")
        if not embedding:
            raise RuntimeError(f"Ollama returned no embedding: {data}")
        return embedding

    async def aclose(self) -> None:
        await self._client.aclose()
