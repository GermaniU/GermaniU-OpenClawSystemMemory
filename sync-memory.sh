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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_DIR="/root/workspace/memory"
QDRANT_URL="http://localhost:6333"
EMBEDDING_URL="http://localhost:11436/v1/embeddings"
EMBEDDING_MODEL="nomic-embed-text:latest"
EMBEDDING_PROXY_URL="http://localhost:11436"
COLLECTION_NAME="memory_facts"
LOG_FILE="$SCRIPT_DIR/sync.log"
VECTOR_SIZE=768

# Archivos temporales
TMP_DIR="$SCRIPT_DIR/.tmp"
mkdir -p "$TMP_DIR"

# Contadores
declare -i TOTAL_FILES=0
declare -i TOTAL_SECTIONS=0
declare -i SUCCESS_COUNT=0
declare -i FAILED_COUNT=0

# Funciones
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

error_exit() {
    log "FATAL: $1"
    exit 1
}

# Verificar dependencias
check_deps() {
    command -v curl >/dev/null 2>&1 || error_exit "curl no está instalado"
    command -v python3 >/dev/null 2>&1 || error_exit "python3 no está instalado"
}

# Crear colección Qdrant si no existe
check_collection() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        "$QDRANT_URL/collections/$COLLECTION_NAME" 2>/dev/null || echo "000")
    
    if [[ "$response" != "200" ]]; then
        log "Creando colección $COLLECTION_NAME (vector_size=$VECTOR_SIZE)..."
        
        curl -s -X PUT "$QDRANT_URL/collections/$COLLECTION_NAME" \
            -H "Content-Type: application/json" \
            -d "{\"vectors\": {\"size\": $VECTOR_SIZE, \"distance\": \"Cosine\"}}" \
            >/dev/null
        
        log "Colección creada"
    else
        log "Colección $COLLECTION_NAME ya existe"
    fi
}

# Generar embedding
generate_embedding() {
    local text="${1:0:4000}"  # Limitar a 4000 chars
    
    local escaped_text
    escaped_text=$(python3 -c "import json; print(json.dumps('$text'))" 2>/dev/null || echo '""')
    
    [[ "$escaped_text" == '""' ]] && { echo ""; return; }
    
    local payload="{\"model\": \"$EMBEDDING_MODEL\", \"input\": $escaped_text}"
    
    local response
    response=$(curl -s -X POST "$EMBEDDING_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)
    
    [[ -z "$response" ]] || [[ "$response" == *"error"* ]] && { echo ""; return; }
    
    echo "$response" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps(d["data"][0].get("embedding",[])) if "data" in d and d["data"] else "[]")' 2>/dev/null
}

# Upsert a Qdrant
upsert_point() {
    local uuid="$1"
    local vector="$2"
    local source="$3"
    local header="$4"
    local content="$5"
    local content_hash="$6"
    
    local synced_at
    synced_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Crear payload JSON
    python3 >/tmp/qdrant_payload.json <<'PYEOF'
import json, sys

data = {
    "points": [{
        "id": "$uuid",
        "vector": $vector,
        "payload": {
            "source": "$source",
            "header": """$header""",
            "content": """$content""",
            "content_hash": "$content_hash",
            "synced_at": "$synced_at"
        }
    }]
}
print(json.dumps(data))
PYEOF
    
    local response
    response=$(curl -s -X PUT "$QDRANT_URL/collections/$COLLECTION_NAME/points" \
        -H "Content-Type: application/json" \
        -d @/tmp/qdrant_payload.json 2>/dev/null)
    
    [[ "$response" != *"error"* ]] && [[ -n "$response" ]] && echo "OK" || echo "FAILED"
}

# Procesar archivo
process_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    
    log "Procesando: $filename"
    
    # Extraer secciones usando Python
    local sections_file="$TMP_DIR/${filename}.json"
    python3 -c "
import re
import json

with open('$filepath', 'r', encoding='utf-8') as f:
    content = f.read()

header_pattern = r'^(#{1,3})\\s+(.+)\$'
lines = content.split('\n')
sections = []
current_section = None
section_lines = []
section_level = 0

for line in lines:
    header_match = re.match(header_pattern, line)
    if header_match:
        if current_section and section_lines:
            section_text = '\\n'.join(section_lines).strip()
            if section_text:
                sections.append({
                    'file': '$filename',
                    'header': current_section,
                    'level': section_level,
                    'content': section_text
                })
        section_level = len(header_match.group(1))
        current_section = header_match.group(2).strip()
        section_lines = [line]
    elif current_section:
        section_lines.append(line)

if current_section and section_lines:
    section_text = '\\n'.join(section_lines).strip()
    if section_text:
        sections.append({
            'file': '$filename',
            'header': current_section,
            'level': section_level,
            'content': section_text
        })

if not sections:
    sections.append({
        'file': '$filename',
        'header': '(document)',
        'level': 0,
        'content': content.strip()
    })

print(json.dumps(sections))
" > "$sections_file"
    
    local file_sections=0
    local file_success=0
    local sections_data
    sections_data=$(cat "$sections_file")
    
    # Procesar cada sección - guardar JSON en archivo temporal
    local processed_file="$TMP_DIR/${filename}.processed.json"
    echo "$sections_data" > "$processed_file"
    
    python3 - "$processed_file" "$filename" "$filepath" "$COLLECTION_NAME" "$EMBEDDING_MODEL" "$EMBEDDING_PROXY_URL" "$QDRANT_URL" 2>&1 <<'PY2EOF'
import json
import hashlib
import uuid
import sys
import urllib.request
import urllib.error

sections_file = sys.argv[1]
filename = sys.argv[2]
source_file = sys.argv[3]
collection_name = sys.argv[4]
embedding_model = sys.argv[5]
embedding_proxy_url = sys.argv[6]
qdrant_url = sys.argv[7]

with open(sections_file, 'r') as f:
    sections = json.load(f)

NAMESPACE_UUID = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
file_sections = 0
file_success = 0

for section in sections:
    try:
        header = section['header']
        content = section['content']
        source = section['file']
        
        content_emb = content[:4000] if len(content) > 4000 else content
        content_hash = hashlib.sha256(content_emb.encode()).hexdigest()[:16]
        
        section_id = str(uuid.uuid5(NAMESPACE_UUID, f"{filename}-{header}-{content_hash}"))
        file_sections += 1
        
        # Generar embedding
        embedding_payload = json.dumps({"model": embedding_model, "input": content_emb}).encode()
        req = urllib.request.Request(
            f"{embedding_proxy_url}/v1/embeddings",
            data=embedding_payload,
            headers={"Content-Type": "application/json", "User-Agent": "curl/8.0.0"},
            method="POST"
        )
        
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                embedding_data = json.loads(response.read().decode())
                vector = embedding_data['data'][0]['embedding']
        except Exception as e:
            print(f"EMBEDDING_ERROR: {e}", file=sys.stderr)
            continue
        
        synced_at = "2026-02-25T05:25:00Z"
        
        # Upsert a Qdrant
        point_data = {
            "points": [{
                "id": section_id,
                "vector": vector,
                "payload": {
                    "source": source_file,
                    "header": header,
                    "content": content[:500],
                    "content_hash": content_hash,
                    "synced_at": synced_at
                }
            }]
        }
        
        qdrant_req = urllib.request.Request(
            f"{qdrant_url}/collections/{collection_name}/points?wait=true",
            data=json.dumps(point_data).encode(),
            headers={"Content-Type": "application/json"},
            method="PUT"
        )
        
        try:
            with urllib.request.urlopen(qdrant_req, timeout=10) as response:
                result = json.loads(response.read().decode())
                if result.get('status') == 'ok':
                    file_success += 1
                    print(f"SUCCESS: {section_id}")
                else:
                    print(f"FAILED: {section_id} - {result}", file=sys.stderr)
        except Exception as e:
            print(f"QDRANT_ERROR: {e}", file=sys.stderr)
            
    except Exception as e:
        print(f"SECTION_ERROR: {e}", file=sys.stderr)

print(f"SUMMARY: {file_success}/{file_sections}")
PY2EOF
    
    while IFS='|' read -r type uuid content_hash header source content; do
        [[ "$type" != "SECTION" ]] && continue
        [[ -z "$uuid" ]] && continue
        
        ((file_sections++))
        ((TOTAL_SECTIONS++))
        
        content="${content//\\n/$'\n'}"  # Restaurar newlines
        
        log "  Sección: $header (UUID: ${uuid:0:8}...)"
        
        # Generar embedding
        local embedding
        embedding=$(generate_embedding "$content")
        
        if [[ -z "$embedding" ]] || [[ "$embedding" == "[]" ]]; then
            log "    ERROR: Embedding fallido"
            ((FAILED_COUNT++))
            continue
        fi
        
        # Upsert
        local result
        result=$(upsert_point "$uuid" "$embedding" "$source" "$header" "$content" "$content_hash")
        
        if [[ "$result" == "OK" ]]; then
            ((file_success++))
            ((SUCCESS_COUNT++))
            log "    OK: Section upserted"
        else
            ((FAILED_COUNT++))
            log "    ERROR: Upsert fallido"
        fi
        
        sleep 0.05
        
    done < "$processed_file"
    
    log "  Resumen: $file_success/$file_sections sincronizadas"
    
    # Limpiar archivos temporales
    rm -f "$sections_file" "$processed_file"
}

# === MAIN ===

mkdir -p "$SCRIPT_DIR"
> "$LOG_FILE"

log "=== Iniciando sincronización de memoria ==="
log "Directorio: $MEMORY_DIR"
log "Colección: $COLLECTION_NAME"

check_deps

[[ -d "$MEMORY_DIR" ]] || error_exit "Directorio $MEMORY_DIR no existe"

check_collection

log "Buscando archivos .md en $MEMORY_DIR..."

file_count=0
while IFS= read -r -d '' file; do
    process_file "$file"
    ((file_count++))
done < <(find "$MEMORY_DIR" -type f -name "*.md" -print0 2>/dev/null)

log "=== Sincronización completada ==="
log "Archivos: $file_count"
log "Secciones: $TOTAL_SECTIONS"
log "Exitosos: $SUCCESS_COUNT"
log "Fallidos: $FAILED_COUNT"
log "Log: $LOG_FILE"

# Limpiar tmp
rm -rf "$TMP_DIR"

exit 0
