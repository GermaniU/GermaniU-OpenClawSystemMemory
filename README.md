# Auto-Sync Pipeline: Memory Episódica → Semántica

## Objetivo
Automatizar el flujo de memoria desde archivos `/memory/*.md` hacia Qdrant.

## Componentes
1. **sync-memory.sh**: Script bash de sincronización
2. **memory-hook.js**: Hook post-sesión para OpenClaw
3. **validate.sh**: Tests de integración
4. **docs/**: Documentación de uso

## Integración C+ Architecture
- Simple sync → switch_mode (rol devops-infra)
- Hook development → sessions_spawn (rol backend-coder)

## Estatus
- [ ] Script de sync
- [ ] Hook MCP
- [ ] Tests
- [ ] Validación completa
