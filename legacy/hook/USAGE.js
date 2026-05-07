#!/usr/bin/env node

/**
 * Uso del Memory Hook MCP Server
 * 
 * Este archivo muestra cómo usar las herramientas disponibles.
 */

// ============================================
// Ejemplo: memory_add
// ============================================

const memoryAddExample = {
  name: "memory_add",
  arguments: {
    // Opcional: nombre de la colección (default: memory_incidents)
    collection: "memory_facts",
    
    // Requerido: texto a almacenar
    text: "La base de datos debe reiniciarse cada 24 horas para evitar memory leaks",
    
    // Opcional: metadatos adicionales
    metadata: {
      priority: "high",
      component: "database",
      tags: ["maintenance", "memory-leak"],
      author: "system"
    },
    
    // Opcional: fuente de la memoria
    source: "incident-response-2026-02-25"
  }
};

// ============================================
// Ejemplo: memory_sync
// ============================================

const memorySyncExample = {
  name: "memory_sync",
  arguments: {
    // Requerido: fecha en formato YYYY-MM-DD
    date: "2026-02-25",
    
    // Requerido: ruta absoluta al archivo markdown
    file_path: "/root/.openclaw/workspace/memory/2026-02-25.md"
  }
};

// ============================================
// Ejemplo: Configuración MCP
// ============================================

const mcpConfig = {
  "mcpServers": {
    "memory": {
      "command": "node",
      "args": [
        "/root/workspace/scratch/2026-02-25/memory-auto-sync/hook/memory-hook.js"
      ],
      "env": {
        "QDRANT_URL": "http://localhost:6333",
        "QDRANT_COLLECTION": "memory_incidents",
        "EMBEDDING_MODEL": "nomic-embed-text",
        "OLLAMA_PROXY_URL": "http://localhost:18789"
      }
    }
  }
};

// ============================================
// Configuración en ~/.openclaw/config.json
// ============================================

const openclawConfig = {
  qdrantUrl: "http://localhost:6333",
  defaultCollection: "memory_incidents",
  embeddingModel: "nomic-embed-text",
  embeddingProxyUrl: "http://localhost:18789",
  collections: {
    memory_incidents: {
      description: "Incidentes y bugs resueltos"
    },
    memory_facts: {
      description: "Hechos y conocimientos"
    }
  }
};

console.log("=== Memory Hook MCP Server - Ejemplos de Uso ===\n");
console.log("1. Configuración MCP:");
console.log(JSON.stringify(mcpConfig, null, 2));
console.log("\n2. Ejemplo memory_add:");
console.log(JSON.stringify(memoryAddExample, null, 2));
console.log("\n3. Ejemplo memory_sync:");
console.log(JSON.stringify(memorySyncExample, null, 2));
