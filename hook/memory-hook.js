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
const EMBEDDING_PROXY_URL = process.env.EMBEDDING_PROXY_URL || process.env.OLLAMA_PROXY_URL || 'http://localhost:11436';

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
  function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  const pointId = generateUUID();
  const enrichedMetadata = {
    ...metadata,
    source: source || 'memory_hook',
    timestamp: new Date().toISOString(),
    text_preview: text.substring(0, 200),
  };
  
  // Insertar en Qdrant
  try {
    const requestBody = {
      points: [
        {
          id: pointId,
          vector: embeddingResult.embedding,
          payload: enrichedMetadata,
        },
      ],
    };

    log('debug', 'Sending to Qdrant', {
      url: `${config.qdrantUrl}/collections/${targetCollection}/points`,
      pointId,
      vectorSize: embeddingResult.embedding.length,
      payloadKeys: Object.keys(enrichedMetadata),
    });

    const response = await fetch(`${config.qdrantUrl}/collections/${targetCollection}/points`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log('error', 'Qdrant insert failed', { status: response.status, errorText });
      throw new Error(`Qdrant insert failed: ${response.status} - ${errorText}`);
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

async function memorySearch(params) {
  const { collection, text, limit = 3, score_threshold = 0.5, filter = null } = params;

  if (!text) {
    return {
      success: false,
      error: 'Missing required parameter: text',
    };
  }

  // Validar conexión a Qdrant (graceful)
  const connStatus = await checkQdrantConnection();
  if (!connStatus.connected) {
    log('warn', 'Qdrant unavailable, cannot search');
    return {
      success: false,
      error: 'Qdrant unavailable',
      details: connStatus.error,
    };
  }

  const targetCollection = collection || config.defaultCollection;

  // Generar embedding de la query
  const embeddingResult = await generateEmbedding(text);
  if (!embeddingResult.success) {
    return {
      success: false,
      error: `Embedding generation failed: ${embeddingResult.error}`,
    };
  }

  try {
    const requestBody = {
      vector: embeddingResult.embedding,
      limit: limit,
      score_threshold: score_threshold,
      with_payload: true,
    };

    // Agregar filtro si está presente
    if (filter) {
      requestBody.filter = filter;
    }

    const response = await fetch(`${config.qdrantUrl}/collections/${targetCollection}/points/search`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log('error', 'Qdrant search failed', { status: response.status, errorText });
      throw new Error(`Qdrant search failed: ${response.status} - ${errorText}`);
    }

    const data = await response.json();

    const results = data.result.map((point) => ({
      id: point.id,
      score: point.score,
      text: point.payload?.text || point.payload?.text_preview || '',
      metadata: point.payload || {},
    }));

    log('info', `Memory search completed`, { collection: targetCollection, count: results.length, filter });

    return {
      success: true,
      collection: targetCollection,
      query: text,
      count: results.length,
      results,
    };
  } catch (error) {
    log('error', 'Error searching memory', error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}

async function memoryDelete(params) {
  const { collection, point_id, query, limit = 1, score_threshold = 0.7 } = params;

  // Validar conexión a Qdrant (graceful)
  const connStatus = await checkQdrantConnection();
  if (!connStatus.connected) {
    log('warn', 'Qdrant unavailable, cannot delete');
    return {
      success: false,
      error: 'Qdrant unavailable',
      details: connStatus.error,
    };
  }

  const targetCollection = collection || config.defaultCollection;

  try {
    // Caso 1: Eliminar por ID directo
    if (point_id) {
      const requestBody = {
        points: [point_id],
      };

      log('debug', 'Deleting point by ID', {
        url: `${config.qdrantUrl}/collections/${targetCollection}/points/delete`,
        point_id,
      });

      const response = await fetch(`${config.qdrantUrl}/collections/${targetCollection}/points/delete`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestBody),
      });

      if (!response.ok) {
        const errorText = await response.text();
        log('error', 'Qdrant delete failed', { status: response.status, errorText });
        throw new Error(`Qdrant delete failed: ${response.status} - ${errorText}`);
      }

      const data = await response.json();
      if (data.status === 'ok') {
        log('info', 'Memory deleted by ID', { point_id });
        return {
          success: true,
          pointId: point_id,
          collection: targetCollection,
          message: `Memory deleted from collection '${targetCollection}'`,
        };
      }

      throw new Error('Delete operation failed: status !== ok');
    }

    // Caso 2: Eliminar por query semántica (busca primero, luego elimina)
    if (query) {
      // Buscar puntos que coincidan
      const embeddingResult = await generateEmbedding(query);
      if (!embeddingResult.success) {
        return {
          success: false,
          error: `Embedding generation failed: ${embeddingResult.error}`,
        };
      }

      const searchResponse = await fetch(`${config.qdrantUrl}/collections/${targetCollection}/points/search`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          vector: embeddingResult.embedding,
          limit: limit,
          score_threshold: score_threshold,
          with_payload: true,
        }),
      });

      if (!searchResponse.ok) {
        throw new Error(`Qdrant search failed: ${searchResponse.status}`);
      }

      const searchData = await searchResponse.json();

      if (searchData.result.length === 0) {
        return {
          success: true,
          collection: targetCollection,
          query,
          deleted: 0,
          message: 'No points matched the query',
        };
      }

      // Extraer IDs de puntos a eliminar
      const pointsToDelete = searchData.result.map((p) => p.id);

      // Eliminar los puntos encontrados
      const deleteResponse = await fetch(`${config.qdrantUrl}/collections/${targetCollection}/points/delete`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          points: pointsToDelete,
        }),
      });

      if (!deleteResponse.ok) {
        const errorText = await deleteResponse.text();
        throw new Error(`Qdrant delete failed: ${deleteResponse.status} - ${errorText}`);
      }

      const deleteData = await deleteResponse.json();
      if (deleteData.status !== 'ok') {
        throw new Error('Delete operation failed: status !== ok');
      }

      log('info', 'Memory deleted by query', {
        collection: targetCollection,
        query,
        deleted: pointsToDelete.length,
        pointIds: pointsToDelete,
      });

      return {
        success: true,
        collection: targetCollection,
        query,
        deleted: pointsToDelete.length,
        pointIds: pointsToDelete,
        message: `Deleted ${pointsToDelete.length} memories from collection '${targetCollection}'`,
      };
    }

    // Ningún parámetro válido
    return {
      success: false,
      error: 'Missing required parameter: point_id or query',
    };
  } catch (error) {
    log('error', 'Error deleting memory', error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}

async function memoryStats(params) {
  const { collection } = params;

  // Validar conexión a Qdrant (graceful)
  const connStatus = await checkQdrantConnection();
  if (!connStatus.connected) {
    log('warn', 'Qdrant unavailable, cannot get stats');
    return {
      success: false,
      error: 'Qdrant unavailable',
      details: connStatus.error,
    };
  }

  const targetCollection = collection || config.defaultCollection;

  try {
    // Obtener información de la colección
    const response = await fetch(`${config.qdrantUrl}/collections/${targetCollection}`);

    if (response.status === 404) {
      return {
        success: true,
        collection: targetCollection,
        exists: false,
        message: `Collection '${targetCollection}' does not exist`,
      };
    }

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Qdrant stats failed: ${response.status} - ${errorText}`);
    }

    const data = await response.json();

    const result = {
      success: true,
      collection: targetCollection,
      exists: true,
      points_count: data.result.points_count,
      segments_count: data.result.segments_count,
      status: data.result.status,
      optimizer_status: data.result.optimizer_status,
      config: {
        vector_size: data.result.config.params.vectors.size,
        distance: data.result.config.params.vectors.distance,
      },
    };

    log('info', `Memory stats retrieved`, { collection: targetCollection, points_count: result.points_count });

    return result;
  } catch (error) {
    log('error', 'Error getting memory stats', error.message);
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
      {
        name: 'memory_search',
        description: 'Buscar memorias en Qdrant usando búsqueda semántica',
        inputSchema: {
          type: 'object',
          properties: {
            collection: {
              type: 'string',
              description: 'Nombre de la colección en Qdrant (default: memory_incidents)',
            },
            text: {
              type: 'string',
              description: 'Texto de búsqueda',
            },
            limit: {
              type: 'number',
              description: 'Número máximo de resultados (default: 3)',
            },
            score_threshold: {
              type: 'number',
              description: 'Umbral mínimo de similitud (default: 0.5)',
            },
            filter: {
              type: 'object',
              description: 'Filtro Qdrant en formato {must: [{key: "field", match: {value: "xyz"}}]}',
            },
          },
          required: ['text'],
        },
      },
      {
        name: 'memory_delete',
        description: 'Eliminar memorias por ID o búsqueda semántica',
        inputSchema: {
          type: 'object',
          properties: {
            collection: {
              type: 'string',
              description: 'Nombre de la colección en Qdrant (default: memory_incidents)',
            },
            point_id: {
              type: 'string',
              description: 'ID del punto a eliminar (UUID)',
            },
            query: {
              type: 'string',
              description: 'Texto de búsqueda para eliminar múltiples puntos coincidentes',
            },
            limit: {
              type: 'number',
              description: 'Máximo de puntos a eliminar por query (default: 1)',
            },
            score_threshold: {
              type: 'number',
              description: 'Umbral mínimo de similitud para query (default: 0.7)',
            },
          },
        },
      },
      {
        name: 'memory_stats',
        description: 'Obtener estadísticas de una colección de memoria',
        inputSchema: {
          type: 'object',
          properties: {
            collection: {
              type: 'string',
              description: 'Nombre de la colección en Qdrant (default: memory_incidents)',
            },
          },
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
      case 'memory_search':
        result = await memorySearch(args);
        break;
      case 'memory_delete':
        result = await memoryDelete(args);
        break;
      case 'memory_stats':
        result = await memoryStats(args);
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
