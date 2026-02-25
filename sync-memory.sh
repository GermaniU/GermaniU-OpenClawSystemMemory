#!/bin/bash
#
# sync-memory.sh - Sincroniza archivos Markdown a Qdrant como embeddings
# 
# Proceso:
# 1. Lee todos los archivos .md en /root/workspace/memory/
# 2. Extrae headers (## y ###)
# 3. Genera embeddings via Ollama API
# 4. Upsert a colección Qdrant memory_facts
#

set -euo pipefail

# Configuración
MEMORY_DIR="/root/workspace/memory"
QDRANT_URL="http://localhost:6333"
EMBEDDING_URL="http://localhost:11436/v1/embeddings"
COLLECTION_NAME="memory_facts"
BATCH_SIZE=10
LOG_FILE="sync.log"

# Namespace UUID para v5 (generado una vez)
NAMESPACE_UUID="6ba7b810-9dad-11d1-80b4-00c04fd430c8"

# Funciones
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Verificar dependencias
command -v curl >/dev/null 2>&1 || error_exit "curl no está instalado"
command -v python3 >/dev/null 2>&1 || error_exit "python3 no está instalado"

# Crear directorio de trabajo si no existe
mkdir -p "$(dirname "$LOG_FILE")"

log "=== Iniciando sincronización de memoria ==="
log "Directorio: $MEMORY_DIR"

# Verificar colección Qdrant existe
check_collection() {
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/qdrant_check.json "$QDRANT_URL/collections/$COLLECTION_NAME" 2>/dev/null || echo "000")
    if [[ "$response" != "200" ]]; then
        log "Creando colección $COLLECTION_NAME..."
        curl -s -X PUT "$QDRANT_URL/collections/$COLLECTION_NAME" \
            -H "Content-Type: application/json" \
            -d '{
                "vectors": {
                    "size": 4096,
                    "distance": "Cosine"
                }
            }' -o /tmp/qdrant_create.json
        log "Colección creada"
    else
        log "Colección $COLLECTION_NAME ya existe"
    fi
}

check_collection

# Generar embedding para texto
generate_embedding() {
    local text="$1"
    local escaped_text
    escaped_text=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$text" 2>/dev/null || echo "null")
    
    if [[ "$escaped_text" == "null" ]]; then
        echo ""
        return
    fi
    
    local payload
    payload="{\"model\": \"llava:7b\", \"input\": $escaped_text}"
    
    local response
    response=$(curl -s -X POST "$EMBEDDING_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)
    
    if [[ -z "$response" ]] || [[ "$response" == *"error"* ]]; then
        echo ""
        return
    fi
    
    # Extraer el array de embeddings
    echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'data' in data and len(data['data']) > 0:
        embedding = data['data'][0].get('embedding', [])
        print(json.dumps(embedding))
    else:
        print('[]')
except:
    print('[]')
" 2>/dev/null || echo "[]"
}

# Generar UUID v5 basado en content hash
generate_uuid() {
    local content="$1"
    local source="$2"
    local header="$3"
    
    # Calcular hash del contenido
    local content_hash
    content_hash=$(echo -n "$content" | sha256sum | cut -d' ' -f1)
    
    # Generar UUID v5: namespace + source + header + hash
    local uuid_input="$source:$header:$content_hash"
    local uuid
    uuid=$(python3 -c "
import hashlib
import uuid

namespace = uuid.UUID('$NAMESPACE_UUID')
name = '''$uuid_input'''

# UUID v5 usa SHA1, pero calculamos hash propio
data = namespace.bytes + name.encode('utf-8')
hash_obj = hashlib.sha1(data).digest()

# Construir UUID v5
uuid_bytes = hash_obj[:16]
# Version 5: 0101 en bits 12-15
versioned = (uuid_bytes[6] & 0x0f) | 0x50
variant = 0x80  # RFC 4122 variant
uuid_final = uuid_bytes[:6] + bytes([versioned, variant | (uuid_bytes[7] & 0x3f)]) + uuid_bytes[8:]

print(str(uuid.UUID(bytes=uuid_final)))
" 2>/dev/null)
    
    echo "$uuid:$content_hash"
}

# Upsert a Qdrant
upsert_to_qdrant() {
    local uuid="$1"
    local vector="$2"
    local source="$3"
    local header="$4"
    local content="$5"
    local content_hash="$6"
    
    # Escapar caracteres especiales para JSON
    local escaped_source
    local escaped_header
    local escaped_content
    escaped_source=$(python3 -c "import json; print(json.dumps('$source'))")
    escaped_header=$(python3 -c "import json; print(json.dumps('$header'))")
    escaped_content=$(python3 -c "import json; print(json.dumps('$content'))")
    
    local payload
    payload="{
        \"points\": [{
            \"id\": \"$uuid\",
            \"vector\": $vector,
            \"payload\": {
                \"source\": $escaped_source,
                \"header\": $escaped_header,
                \"content\": $escaped_content,
                \"content_hash\": \"$content_hash\",
                \"synced_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }
        }]
    }"
    
    local response
    response=$(curl -s -X PUT "$QDRANT_URL/collections/$COLLECTION_NAME/points" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)
    
    if [[ "$response" == *"error"* ]] || [[ -z "$response" ]]; then
        echo "FAILED"
    else
        echo "OK"
    fi
}

# Procesar un archivo Markdown
process_file() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    
    log "Procesando: $filename"
    
    # Extraer headers usando Python
    local sections
    sections=$(python3 << 'PYTHON_SCRIPT'
import re
import sys

content = sys.stdin.read()

# Patrón para headers de nivel 2 y 3
header_pattern = r'^(#{2,3})\s+(.+)$'

lines = content.split('\n')
sections = []
current_section = None
section_lines = []
section_header = ""
section_level = 0
file_basename = """$filename"""

for line in lines:
    header_match = re.match(header_pattern, line, re.MULTILINE)
    
    if header_match:
        # Guardar sección anterior
        if current_section is not None and section_lines:
            section_text = '\n'.join(section_lines).strip()
            if section_text:
                sections.append({
                    'file': file_basename,
                    'header': current_section,
                    'level': section_level,
                    'content': section_text
                })
        
        # Iniciar nueva sección
        section_level = len(header_match.group(1))
        current_section = header_match.group(2).strip()
        section_lines = [line]
    elif current_section is not None:
        section_lines.append(line)

# Guardar última sección
if current_section is not None and section_lines:
    section_text = '\n'.join(section_lines).strip()
    if section_text:
        sections.append({
            'file': file_basename,
            'header': current_section,
            'level': section_level,
            'content': section_text
        })

# Si no hay headers, guardar todo el archivo como una sección
if not sections:
    sections.append({
        'file': file_basename,
        'header': '(no headers)',
        'level': 0,
        'content': content.strip()
    })

import json
print(json.dumps(sections, ensure_ascii=False))
PYTHON_SCRIPT
"$file"
)
    
    if [[ -z "$sections" ]] || [[ "$sections" == "[]" ]]; then
        log "  No se encontraron secciones en $filename"
        return
    fi
    
    # Procesar cada sección
    local total_added=0
    local total_skipped=0
    
    # Parsear JSON y procesar
    python3 << PROCESS_SECTIONS_EOF - "$sections" "$filename"
import json
import sys
import subprocess
import os

sections = json.loads(sys.argv[1])
source = sys.argv[2]

for section in sections:
    header = section['header']
    content = section['content']
    level = section['level']
    
    # Limitar tamaño del contenido para embedding
    content_for_embedding = content[:4000] if len(content) > 4000 else content
    
    # Generar UUID y hash
    uuid_cmd = f"bash -c 'source \"$0\"; generate_uuid \"{content_for_embedding}\" \"{source}\" \"{header}\"' \"$(dirname "$0")/sync-memory.sh\""
    
    # Usar directamente las funciones del script
    content_hash = os.popen(f"echo -n '{content_for_embedding}' | sha256sum | cut -d' ' -f1").read().strip()
    uuid_input = f"{source}:{header}:{content_hash}"
    
    uuid_result = os.popen(f"python3 -c \"
import hashlib
import uuid
namespace = uuid.UUID('{NAMESPACE_UUID}')
name = '''{uuid_input}'''
data = namespace.bytes + name.encode('utf-8')
hash_obj = hashlib.sha1(data).digest()
uuid_bytes = hash_obj[:16]
versioned = (uuid_bytes[6] & 0x0f) | 0x50
variant = 0x80
uuid_final = uuid_bytes[:6] + bytes([versioned, variant | (uuid_bytes[7] & 0x3f)]) + uuid_bytes[8:]
print(str(uuid.UUID(bytes=uuid_final)))
\"").read().strip()
    
    if uuid_result:
        print(f"SEC|{uuid_result}|{content_hash}|{header}|{content_for_embedding}")

PROCESS_SECTIONS_EOF
    
    while IFS='|' read -r type uuid content_hash header content; do
        [[ "$type" != "SEC" ]] && continue
        [[ -z "$uuid" ]] && continue
        
        log "  Procesando: $header (UUID: $uuid)"
        
        # Generar embedding
        local embedding
        embedding=$(generate_embedding "$content")
        
        if [[ -z "$embedding" ]] || [[ "$embedding" == "[]" ]]; then
            log "    ERROR: No se pudo generar embedding"
            continue
        fi
        
        # Upsert a Qdrant
        local result
        result=$(upsert_to_qdrant "$uuid" "$embedding" "$filename" "$header" "$content" "$content_hash")
        
        if [[ "$result" == "OK" ]]; then
            ((total_added++))
            log "    OK: Section upserted"
        else
            log "    ERROR: Failed to upsert"
        fi
        
        # Pequeña pausa para no saturar la API
        sleep 0.1
        
    done < <(python3 << PROCESS_SECTIONS_EOF - "$sections"
import json
import sys
import hashlib

NAMESPACE_UUID = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

sections = json.loads(sys.argv[1])

for section in sections:
    header = section['header']
    content = section['content']
    source = section['file']
    
    # Limitar contenido
    content_for_embedding = content[:4000] if len(content) > 4000 else content
    
    # Calcular hash
    content_hash = hashlib.sha256(content_for_embedding.encode()).hexdigest()
    
    # Generar UUID v5
    uuid_input = f"{source}:{header}:{content_hash}"
    
    namespace = __import__('uuid').UUID(NAMESPACE_UUID)
    name = uuid_input
    data = namespace.bytes + name.encode('utf-8')
    hash_obj = hashlib.sha1(data).digest()
    uuid_bytes = hash_obj[:16]
    versioned = (uuid_bytes[6] & 0x0f) | 0x50
    variant = 0x80
    uuid_final = uuid_bytes[:6] + bytes([versioned, variant | (uuid_bytes[7] & 0x3f)]) + uuid_bytes[8:]
    uuid_result = str(__import__('uuid').UUID(bytes=uuid_final))
    
    # Escapar para pipe
    safe_header = header.replace('|', '\\|')
    safe_content = content_for_embedding.replace('|', '\\|')
    print(f"SEC|{uuid_result}|{content_hash}|{safe_header}|{safe_content}")
PROCESS_SECTIONS_EOF
)
    
    log "  Resumen $filename: $total_added agregados, $total_skipped saltados"
}

# Procesar todos los archivos .md
log "Buscando archivos .md en $MEMORY_DIR..."

file_count=0
total_sections=0

while IFS= read -r -d '' file; do
    process_file "$file"
    ((file_count++))
done < <(find "$MEMORY_DIR" -type f -name "*.md" -print0 2>/dev/null)

log "=== Sincronización completada ==="
log "Total archivos procesados: $file_count"
log "Log guardado en: $LOG_FILE"
