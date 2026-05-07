from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    embedding_model: str = "bge-m3"
    embedding_dim: int = 1024

    ollama_url: str = "http://host.docker.internal:11434"
    ollama_api_key: str | None = None

    qdrant_url: str = "http://qdrant:6333"
    qdrant_collection: str = "mcp_memory"

    mcp_host: str = "0.0.0.0"
    mcp_port: int = 8765

    default_namespace: str = "default"


def get_settings() -> Settings:
    return Settings()
