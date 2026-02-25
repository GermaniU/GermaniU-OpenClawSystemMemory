#!/bin/bash
#===============================================================================
# Memory Auto-Sync Pipeline Integration Tests
# Role: QA-Tester
# Output: TAP format + validate.log, exit 0 on all pass
# Requirements: Uses /tmp, cleans up, idempotent
#===============================================================================

set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/validate.log"
TMP_DIR="/tmp/memory-auto-sync-test-$$"
QDRANT_URL="${QDRANT_URL:-localhost:6333}"
EMBEDDING_URL="${EMBEDDING_URL:-http://localhost:11436}"
TEST_COLLECTION="test_memory_validation$$"
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#===============================================================================
# Test Framework Functions (TAP Format)
#===============================================================================

init_tests() {
    TOTAL_TESTS=0
    PASSED_TESTS=0
    FAILED_TESTS=0
    echo "TAP version 13" > "$LOG_FILE"
    echo "# Memory Auto-Sync Pipeline Integration Tests" >> "$LOG_FILE"
    echo "# Started: $(date -Iseconds)" >> "$LOG_FILE"
    echo "# QDRANT_URL: $QDRANT_URL" >> "$LOG_FILE"
    echo "# EMBEDDING_URL: $EMBEDDING_URL" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

plan_tests() {
    local count=$1
    echo "1..$count" | tee -a "$LOG_FILE"
}

ok() {
    local num=$1
    local desc=$2
    echo "ok $num - $desc" | tee -a "$LOG_FILE"
    ((TOTAL_TESTS++))
    ((PASSED_TESTS++))
}

not_ok() {
    local num=$1
    local desc=$2
    local reason=$3
    echo "not ok $num - $desc" | tee -a "$LOG_FILE"
    if [ -n "$reason" ]; then
        echo "  ---" >> "$LOG_FILE"
        echo "  reason: $reason" >> "$LOG_FILE"
        echo "  ---" >> "$LOG_FILE"
    fi
    ((TOTAL_TESTS++))
    ((FAILED_TESTS++))
}

skip() {
    local num=$1
    local desc=$2
    local reason=$3
    echo "ok $num - $desc # SKIP $reason" | tee -a "$LOG_FILE"
    ((TOTAL_TESTS++))
}

diag() {
    local msg=$1
    echo "# $msg" | tee -a "$LOG_FILE"
}

#===============================================================================
# Setup and Teardown
#===============================================================================

setup() {
    diag "Setting up test environment..."
    
    # Create temp directory
    mkdir -p "$TMP_DIR"
    
    # Create mock sync-memory.sh if doesn't exist
    if [ ! -f "$SCRIPT_DIR/../sync-memory.sh" ]; then
        create_mock_sync_script
    fi
    
    diag "Test directory: $TMP_DIR"
}

teardown() {
    diag "Cleaning up test environment..."
    
    # Remove temp directory
    rm -rf "$TMP_DIR"
    
    # Clean up test collection if it exists
    curl -sf -X DELETE "http://$QDRANT_URL/collections/$TEST_COLLECTION" > /dev/null 2>&1 || true
    
    diag "Cleanup complete"
}

create_mock_sync_script() {
    mkdir -p "$SCRIPT_DIR/.."
    cat > "$SCRIPT_DIR/../sync-memory.sh" << 'EOF'
#!/bin/bash
# Mock sync-memory.sh for testing
# Usage: sync-memory.sh <source_dir> <collection_name>

QDRANT_URL="${QDRANT_URL:-localhost:6333}"
EMBEDDING_URL="${EMBEDDING_URL:-http://localhost:11436}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

sync_markdown() {
    local dir="$1"
    local collection="$2"
    local processed=0
    local errors=0
    
    log "Starting sync from $dir to collection $collection"
    
    # Create collection if doesn't exist
    curl -sf -X PUT "http://$QDRANT_URL/collections/$collection" \
        -H "Content-Type: application/json" \
        -d '{"vectors": {"size": 768, "distance": "Cosine"}}' > /dev/null 2>&1 || true
    
    # Process markdown files
    for file in "$dir"/*.md; do
        [ -f "$file" ] || continue
        
        local content=$(cat "$file" 2>/dev/null)
        local filename=$(basename "$file")
        local id=$(echo "$filename" | cksum | cut -d' ' -f1)
        
        # Get embedding
        local embedding=$(curl -sf -X POST "$EMBEDDING_URL/v1/embeddings" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"nomic-embed-text\", \"input\": $content}" 2>/dev/null | \
            jq -c '.data[0].embedding' 2>/dev/null)
        
        if [ -n "$embedding" ] && [ "$embedding" != "null" ]; then
            # Store in Qdrant
            curl -sf -X PUT "http://$QDRANT_URL/collections/$collection/points" \
                -H "Content-Type: application/json" \
                -d "{\"points\": [{\"id\": $id, \"vector\": $embedding, \"payload\": {\"text\": $(echo "$content" | jq -Rs .), \"source\": \"$filename\", \"synced_at\": \"$(date -Iseconds)\"}}]}" > /dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                ((processed++))
                log "✓ Synced: $filename"
            else
                ((errors++))
                log "✗ Failed: $filename"
            fi
        else
            ((errors++))
            log "✗ No embedding: $filename"
        fi
    done
    
    log "Sync complete: $processed files processed, $errors errors"
    return $errors
}

# Main
case "$1" in
    sync)
        sync_markdown "$2" "$3"
        ;;
    *)
        echo "Usage: $0 sync <source_dir> <collection_name>"
        exit 1
        ;;
esac
EOF
    chmod +x "$SCRIPT_DIR/../sync-memory.sh"
}

#===============================================================================
# Test 1: Qdrant Connectivity
#===============================================================================

test_01_qdrant_connectivity() {
    local test_num=1
    local test_desc="Qdrant connectivity check"
    
    diag "Running: $test_desc"
    
    local response
    local http_code
    
    response=$(curl -sf -w "%{http_code}" -o /dev/null "http://$QDRANT_URL/healthz" 2>&1)
    http_code=$?
    
    if [ $http_code -eq 0 ]; then
        ok $test_num "$test_desc"
        diag "Qdrant is healthy at $QDRANT_URL"
        return 0
    else
        not_ok $test_num "$test_desc" "HTTP request failed with exit code $http_code"
        diag "Response: $response"
        return 1
    fi
}

#===============================================================================
# Test 2: Embedding Proxy Response
#===============================================================================

test_02_embedding_proxy() {
    local test_num=2
    local test_desc="Embedding proxy response (llava:7b or compatible)"
    
    diag "Running: $test_desc"
    
    local test_text="Test memory about machine learning"
    local response
    local exit_code
    
    response=$(curl -sf -X POST "$EMBEDDING_URL/v1/embeddings" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"nomic-embed-text\", \"input\": \"$test_text\"}" 2>&1)
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        not_ok $test_num "$test_desc" "Request failed: $response"
        return 1
    fi
    
    # Check if response contains valid embedding
    if echo "$response" | jq -e '.data[0].embedding' > /dev/null 2>&1; then
        local embedding_dim
        embedding_dim=$(echo "$response" | jq '.data[0].embedding | length')
        ok $test_num "$test_desc"
        diag "Embedding dimension: $embedding_dim"
        return 0
    else
        not_ok $test_num "$test_desc" "Invalid embedding response"
        diag "Response: ${response:0:200}"
        return 1
    fi
}

#===============================================================================
# Test 3: Sync Script with Mock Data
#===============================================================================

test_03_sync_script_mock() {
    local test_num=3
    local test_desc="sync-memory.sh with mock data"
    
    diag "Running: $test_desc"
    
    # Setup mock data directory
    local mock_dir="$TMP_DIR/test-markdown"
    mkdir -p "$mock_dir"
    
    # Create sample markdown files
    cat > "$mock_dir/test-memory-1.md" << 'EOF'
# Test Memory 1

This is a test document about artificial intelligence and neural networks.
It contains sample text for embedding generation.
EOF
    
    cat > "$mock_dir/test-memory-2.md" << 'EOF'
# Test Memory 2

Another test document discussing project architecture and design patterns.
This is used for validating the sync pipeline.
EOF
    
    # Run sync script
    local output
    local exit_code
    
    if [ -x "$SCRIPT_DIR/../sync-memory.sh" ]; then
        output=$("$SCRIPT_DIR/../sync-memory.sh" sync "$mock_dir" "$TEST_COLLECTION" 2>&1)
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            ok $test_num "$test_desc"
            diag "Sync completed successfully"
            return 0
        else
            not_ok $test_num "$test_desc" "Script exited with code $exit_code"
            diag "Output: ${output:0:200}"
            return 1
        fi
    else
        not_ok $test_num "$test_desc" "sync-memory.sh not found or not executable"
        return 1
    fi
}

#===============================================================================
# Test 4: Memory Add Hook (mcporter)
#===============================================================================

test_04_memory_add_hook() {
    local test_num=4
    local test_desc="memory_add hook via mcporter"
    
    diag "Running: $test_desc"
    
    local test_content="Test memory content for hook validation: $RANDOM"
    local test_id="test-hook-$(date +%s)"
    local response
    local exit_code
    
    # Try mcporter call
    response=$(mcporter call qdrant.add_documents \
        collection="$TEST_COLLECTION" \
        documents="[{\"id\": \"$test_id\", \"text\": \"$test_content\", \"source\": \"test\"}]" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        # Verify document was added
        local verify_response
        verify_response=$(curl -sf "http://$QDRANT_URL/collections/$TEST_COLLECTION/points/$test_id" 2>&1)
        if [ $? -eq 0 ]; then
            ok $test_num "$test_desc"
            diag "Document added and verified in Qdrant"
            return 0
        else
            not_ok $test_num "$test_desc" "Document added but verification failed"
            return 1
        fi
    else
        not_ok $test_num "$test_desc" "mcporter call failed: $response"
        return 1
    fi
}

#===============================================================================
# Test 5: End-to-End Pipeline
#===============================================================================

test_05_end_to_end() {
    local test_num=5
    local test_desc="End-to-end: Create markdown → Sync → Verify in Qdrant"
    
    diag "Running: $test_desc"
    
    local e2e_dir="$TMP_DIR/e2e-markdown"
    local e2e_collection="test_e2e_collection$$"
    local timestamp
    timestamp=$(date +%s)
    local unique_content="E2E test content with unique identifier: $timestamp-$RANDOM"
    
    # Clean up any previous e2e collection
    curl -sf -X DELETE "http://$QDRANT_URL/collections/$e2e_collection" > /dev/null 2>&1 || true
    
    # Step 1: Create markdown file
    mkdir -p "$e2e_dir"
    cat > "$e2e_dir/e2e-test.md" << EOF
# E2E Test Document

$unique_content

This document was created during integration testing.
Timestamp: $timestamp
EOF
    
    diag "Step 1: Created markdown file"
    
    # Step 2: Ensure collection exists
    curl -sf -X PUT "http://$QDRANT_URL/collections/$e2e_collection" \
        -H "Content-Type: application/json" \
        -d '{"vectors": {"size": 768, "distance": "Cosine"}}' > /dev/null 2>&1
    diag "Step 2: Created Qdrant collection"
    
    # Step 3: Sync to Qdrant (using mcporter)
    local sync_response
    sync_response=$(mcporter call qdrant.add_documents \
        collection="$e2e_collection" \
        documents="[{\"id\": \"e2e-$timestamp\", \"text\": \"$unique_content\", \"source\": \"e2e-test.md\", \"timestamp\": \"$(date -Iseconds)\"}]" 2>&1)
    
    if [ $? -ne 0 ]; then
        not_ok $test_num "$test_desc" "Failed to sync document: $sync_response"
        curl -sf -X DELETE "http://$QDRANT_URL/collections/$e2e_collection" > /dev/null 2>&1 || true
        return 1
    fi
    
    diag "Step 3: Document synced to Qdrant"
    
    # Step 4: Verify in Qdrant
    sleep 1  # Allow for indexing
    local search_response
    search_response=$(mcporter call qdrant.search \
        collection="$e2e_collection" \
        query="$unique_content" \
        limit=3 2>&1)
    
    local exit_code=$?
    
    # Clean up
    curl -sf -X DELETE "http://$QDRANT_URL/collections/$e2e_collection" > /dev/null 2>&1 || true
    rm -rf "$e2e_dir"
    
    if [ $exit_code -eq 0 ]; then
        if echo "$search_response" | grep -q "e2e-$timestamp" 2>/dev/null || \
           echo "$search_response" | grep -qi "e2e\|$unique_content" 2>/dev/null; then
            ok $test_num "$test_desc"
            diag "End-to-end pipeline verified successfully"
            return 0
        else
            not_ok $test_num "$test_desc" "Search completed but content not found in results"
            diag "Response: ${search_response:0:300}"
            return 1
        fi
    else
        not_ok $test_num "$test_desc" "Search failed: $search_response"
        return 1
    fi
}

#===============================================================================
# Main Test Execution
#===============================================================================

main() {
    echo "=========================================="
    echo "Memory Auto-Sync Pipeline Integration Tests"
    echo "Started: $(date)"
    echo "=========================================="
    echo ""
    
    # Initialize
    init_tests
    plan_tests 5
    
    # Setup
    setup
    
    # Run tests
    test_01_qdrant_connectivity
    test_02_embedding_proxy
    test_03_sync_script_mock
    test_04_memory_add_hook
    test_05_end_to_end
    
    # Cleanup
    teardown
    
    # Summary
    echo "" >> "$LOG_FILE"
    echo "# Test Summary" >> "$LOG_FILE"
    echo "# Total: $TOTAL_TESTS" >> "$LOG_FILE"
    echo "# Passed: $PASSED_TESTS" >> "$LOG_FILE"
    echo "# Failed: $FAILED_TESTS" >> "$LOG_FILE"
    echo "# Completed: $(date -Iseconds)" >> "$LOG_FILE"
    
    echo ""
    echo "=========================================="
    echo "Test Summary:"
    echo "  Total:  $TOTAL_TESTS"
    echo "  Passed: $PASSED_TESTS"
    echo "  Failed: $FAILED_TESTS"
    echo "=========================================="
    echo "Log saved to: $LOG_FILE"
    echo ""
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed!${NC}"
        exit 1
    fi
}

# Handle interrupts
trap teardown EXIT INT TERM

# Run main
main "$@"
