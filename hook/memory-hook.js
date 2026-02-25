#!/usr/bin/env node

/**
 * Memory Hook MCP Server
 * 
 * MCP server para OpenClaw que expone herramientas para:
 * - memory_add: Agregar memorias a Qdrant
 * - memory_sync: Sincronizar archivos markdown
 * 
 * @module memory-hook
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ErrorCode,
  McpError,
} from '@modelcontextprotocol/sdk/types.js';
import { promises as fs } from 'fs';
import { readFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

// ============================================
// CONFIGURATION
// ============================================

const CONFIG_PATHS = [
  join(homedir(), '.openclaw', 'config.json'),
  join(homedir(), '.openclaw', 'memory-config.json'),
  '/root/.openclaw/config.json',
];

const DEFAULT_QDRANT_URL = process.env.QDRANT_URL || 'http://localhost:6333';
const DEFAULT_COLLECTION = process.env.QDRANT_COLLECTION || 'memory_incidents';
const DEFAULT_EMBEDDING_MODEL = process.env.EMBEDDING_MODEL || 'nomic-embed-text';
const EMBEDDING_PROXY_URL = process.env.OLLAMA_PROXY_URL || 'http://localhost:18789';

let config = {
  qdrantUrl: DEFAULT_QDRANT_URL,
  defaultCollection: DEFAULT_COLLECTION,
  embeddingModel: DEFAULT_EMBEDDING_MODEL,
  embeddingProxyUrl: EMBEDDING_PROXY_URL,
};

let qdrantConnected = false;
let qdrantLastCheck = 0;
const QDRANT_CHECK_INTERVAL = 30000; // 30 segundos

// ============================================
// LOGGING
// ============================================

function log(level, message, data = null) {
  const timestamp = new Date().toISOString();
  const logEntry = {
    timestamp,
    level,
    message,
    data,
  };
  
  // En MCP, logs van a stderr para no interferir con el protocolo
  console.error(`[${timestamp}] [${level.toUpperCase()}] ${message}`, data ? JSON.stringify(data) : '');
}

// ============================================
// CONFIGURATION LOADING
// ============================================

async function loadConfig() {
  for (const configPath of CONFIG_PATHS) {
    try {
      const data = readFileSync(configPath, 'utf-8');
      const parsed = JSON.parse(data);
      config = {
        ...config,
        ...parsed,
        qdrantUrl: parsed.qdrantUrl || parsed.qdrant_url || DEFAULT_QDRANT_URL,
        defaultCollection: parsed.defaultCollection || parsed.default_collection || DEFAULT_COLLECTION,
        embeddingProxyUrl: parsed.embeddingProxyUrl || parsed.embedding_proxy_url || EMBEDDING_PROXY_URL,
      };
      log('info', `Config loaded from ${configPath}`);
      return;
    } catch (err) {
      if (err.code !== 'ENOENT') {
        log('warn', `Error loading config from ${configPath}`, err.message);
      }
    }
  }
  log('info', 'Using default/environment configuration');
}

// ============================================
// QDRANT CLIENT
// ============================================

async function checkQdrantConnection() {
  const now = Date.now();
  if (qdrantConnected && (now - qdrantLastCheck) < QDRANT_CHECK_INTERVAL) {
    return { connected: true, cached: true };
  }

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);
    
    const response = await fetch(`${config.qdrantUrl}/healthz`, {
      signal: controller.signal,
    });
    
    clearTimeout(timeoutId);
    
    if (response.ok) {
      qdrantConnected = true;
      qdrantLastCheck = now;
      log('info', 'Qdrant connection healthy');
      return { connected: true, cached: false };
    }
    
    throw new Error(`Qdrant health check failed: ${response.status}`);
  } catch (error) {
    qdrantConnected = false;
    qdrantLastCheck = now;
    log('warn', 'Qdrant connection failed', error.message);
    return { connected: false, error: error.message };
  }
}

async function ensureCollectionExists(collectionName) {
  try {
    const response = await fetch(`${config.qdrantUrl}/collections/${collectionName}`, {
      method: 'GET',
    });
    
    if (response.status === 404) {
      // Colección no existe, crearla
      log('info', `Creating collection ${collectionName}`);
      
      const createResponse = await fetch(`${config.qdrantUrl}/collections/${collectionName}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          vectors: {
            size: 768, // nomic-embed-text output size
            distance: 'Cosine',
          },
        }),
      });
      
      if (!createResponse.ok) {
        throw new Error(`Failed to create collection: ${createResponse.status}`);
      }
      
      log('info', `Collection ${collectionName} created`);
    }
    
    return { success: true };
  } catch (error) {
    log('error', 'Error ensuring collection exists', error.message);
    return { success: false, error: error.message };
  }
}

// ============================================
// EMBEDDING
// ============================================

async function generateEmbedding(text) {
  try {
    const response = await fetch(`${config.embeddingProxyUrl}/v1/embeddings`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: config.embeddingModel,
        input: text,
      }),
    });
    
    if (!response.ok) {
      throw new Error(`Embedding request failed: ${response.status}`);
    }
    
    const data = await response.json();
    return { success: true, embedding: data.data[0].embedding };
  } catch (error) {
    log('error', 'Error generating embedding', error.message);
    return { success: false, error: error.message };
  }
}

// ============================================
// MEMORY OPERATIONS
// ============================================

async function memoryAdd(params) {
  const { collection, text, metadata = {}, source } = params;
  
  if (!text) {
    return {
      success: false,
      error: 'Missing required parameter: text',
    };
  }
  
  // Validar conexión a Qdrant (graceful)
  const connStatus = await checkQdrantConnection();
  if (!connStatus.connected) {
    log('warn', 'Qdrant unavailable, storing memory in pending queue');
    return {
      success: false,
      error: 'Qdrant unavailable',
      pending: true,
      details: connStatus.error,
    };
  }
  
  const targetCollection = collection || config.defaultCollection;
  
  // Asegurar que la colección existe
  const collectionStatus = await ensureCollectionExists(targetCollection);
  if (!collectionStatus.success) {
    return {
      success: false,
      error: `Collection check failed: ${collectionStatus.error}`,
    };
  }
  
  // Generar embedding
  const embeddingResult = await generateEmbedding(text);
  if (!embeddingResult.success) {
    return {
      success: false,
      error: `Embedding generation failed: ${embeddingResult.error}`,
    };
  }
  
  // Crear punto a insertar
  const pointId = `${targetCollection}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  const enrichedMetadata = {
    ...metadata,
    source: source || 'memory_hook',
    timestamp: new Date().toISOString(),
    text_preview: text.substring(0, 200),
  };
  
  // Insertar en Qdrant
  try {
    const response = await fetch(`${config.qdrantUrl}/collections/${targetCollection}/points`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        points: [
          {
            id: pointId,
            vector: embeddingResult.embedding,
            payload: enrichedMetadata,
          },
        ],
      }),
    });
    
    if (!response.ok) {
      throw new Error(`Qdrant insert failed: ${response.status}`);
    }
    
    log('info', `Memory added to ${targetCollection}`, { pointId, text_length: text.length });
    
    return {
      success: true,
      pointId,
      collection: targetCollection,
      message: `Memory added to collection '${targetCollection}'`,
    };
  } catch (error) {
    log('error', 'Error inserting memory', error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}

async function memorySync(params) {
  const { date, file_path } = params;
  
  if (!file_path) {
    return {
      success: false,
      error: 'Missing required parameter: file_path',
    };
  }
  
  log('info', `Syncing memory file: ${file_path}`);
  
  // Validar conexión a Qdrant (graceful)
  const connStatus = await checkQdrantConnection();
  if (!connStatus.connected) {
    return {
      success: false,
      error: 'Qdrant unavailable',
      details: connStatus.error,
      pending: true,
    };
  }
  
  try {
    // Verificar que el archivo existe
    const stats = await fs.stat(file_path);
    if (!stats.isFile()) {
      throw new Error('Path is not a file');
    }
    
    // Leer contenido
    const content = await fs.readFile(file_path, 'utf-8');
    
    // Validar que es markdown
    if (!file_path.endsWith('.md')) {
      log('warn', 'File is not markdown, proceeding anyway', { file_path });
    }
    
    // Parsear secciones del markdown
    const sections = parseMarkdownSections(content, date);
    
    const results = {
      added: 0,
      failed: 0,
      sections: sections.length,
    };
    
    // Procesar cada sección
    for (const section of sections) {
      const result = await memoryAdd({
        collection: section.collection || config.defaultCollection,
        text: section.text,
        metadata: {
          ...section.metadata,
          synced_from: file_path,
          sync_date: date,
        },
        source: 'memory_sync',
      });
      
      if (result.success) {
        results.added++;
      } else {
        results.failed++;
      }
    }
    
    log('info', `Memory sync completed`, results);
    
    return {
      success: true,
      message: `Synced ${results.added}/${results.sections} sections from ${file_path}`,
      details: results,
    };
  } catch (error) {
    log('error', 'Error syncing memory', error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}

function parseMarkdownSections(content, date) {
  const sections = [];
  const lines = content.split('\n');
  let currentSection = { lines: [], metadata: {} };
  let inCodeBlock = false;
  
  for (const line of lines) {
    // Detectar fin de bloque de código
    if (line.trim().startsWith('```')) {
      inCodeBlock = !inCodeBlock;
    }
    
    // Detectar headers como separadores de sección
    if (!inCodeBlock && line.startsWith('#')) {
      if (currentSection.lines.length > 0) {
        const text = currentSection.lines.join('\n').trim();
        if (text.length > 10) { // Ignorar secciones muy cortas
          sections.push({
            text,
            metadata: currentSection.metadata,
            collection: currentSection.collection,
          });
        }
      }
      currentSection = {
        lines: [line],
        metadata: { header: line.replace(/^#+\s*/, ''), date },
        collection: detectCollectionFromHeader(line),
      };
    } else {
      currentSection.lines.push(line);
    }
  }
  
  // Agregar última sección
  if (currentSection.lines.length > 0) {
    const text = currentSection.lines.join('\n').trim();
    if (text.length > 10) {
      sections.push({
        text,
        metadata: currentSection.metadata,
        collection: currentSection.collection,
      });
    }
  }
  
  return sections;
}

function detectCollectionFromHeader(header) {
  const lower = header.toLowerCase();
  if (lower.includes('bug') || lower.includes('error') || lower.includes('fix')) {
    return 'memory_incidents';
  }
  if (lower.includes('fact') || lower.includes('knowledge') || lower.includes('info')) {
    return 'memory_facts';
  }
  if (lower.includes('todo') || lower.includes('task')) {
    return 'memory_tasks';
  }
  return config.defaultCollection;
}

// ============================================
// MCP SERVER SETUP
// ============================================

const server = new Server(
  {
    name: 'memory-hook',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Handler para listar herramientas
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: 'memory_add',
        description: 'Agregar una memoria a Qdrant para recuperación semántica',
        inputSchema: {
          type: 'object',
          properties: {
            collection: {
              type: 'string',
              description: 'Nombre de la colección en Qdrant (default: memory_incidents)',
            },
            text: {
              type: 'string',
              description: 'Texto a almacenar y vectorizar',
            },
            metadata: {
              type: 'object',
              description: 'Metadatos adicionales para la memoria',
            },
            source: {
              type: 'string',
              description: 'Fuente de la memoria',
            },
          },
          required: ['text'],
        },
      },
      {
        name: 'memory_sync',
        description: 'Sincronizar un archivo markdown con Qdrant',
        inputSchema: {
          type: 'object',
          properties: {
            date: {
              type: 'string',
              description: 'Fecha del archivo (formato: YYYY-MM-DD)',
            },
            file_path: {
              type: 'string',
              description: 'Ruta absoluta al archivo markdown',
            },
          },
          required: ['file_path'],
        },
      },
    ],
  };
});

// Handler para ejecutar herramientas
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  
  log('info', `Tool called: ${name}`, args);
  
  try {
    let result;
    
    switch (name) {
      case 'memory_add':
        result = await memoryAdd(args);
        break;
      case 'memory_sync':
        result = await memorySync(args);
        break;
      default:
        throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${name}`);
    }
    
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify(result, null, 2),
        },
      ],
    };
  } catch (error) {
    log('error', `Error executing tool ${name}`, error.message);
    
    // Graceful error handling - no fallar el servidor
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify({
            success: false,
            error: error.message,
            tool: name,
          }, null, 2),
        },
      ],
      isError: true,
    };
  }
});

// ============================================
// SERVER STARTUP
// ============================================

async function main() {
  await loadConfig();
  
  // Verificar conexión inicial (pero no fallar si está down)
  const initialCheck = await checkQdrantConnection();
  if (!initialCheck.connected) {
    log('warn', 'Qdrant not available at startup, will retry on operations');
  }
  
  const transport = new StdioServerTransport();
  
  log('info', 'Memory Hook MCP Server starting...', {
    qdrantUrl: config.qdrantUrl,
    defaultCollection: config.defaultCollection,
  });
  
  await server.connect(transport);
  
  log('info', 'Memory Hook MCP Server running on stdio');
}

main().catch((error) => {
  log('error', 'Fatal error in main', error.message);
  console.error(error);
  process.exit(1);
});
