#!/usr/bin/env python3
"""
Generate UUID v5 for content deduplication.
Uses hash of source, header, and content for stable IDs.
"""

import hashlib
import sys
import uuid

# DNS namespace UUID (standard)
NAMESPACE_UUID = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

def generate_uuid(source: str, header: str, content: str) -> tuple:
    """
    Generate UUID v5 and content hash.
    Returns (uuid, content_hash)
    """
    # Calculate content hash for deduplication
    content_hash = hashlib.sha256(content.encode('utf-8')).hexdigest()
    
    # Generate UUID v5 based on source:header:hash
    name = f"{source}:{header}:{content_hash}"
    uid = uuid.uuid5(NAMESPACE_UUID, name)
    
    return str(uid), content_hash

if __name__ == '__main__':
    if len(sys.argv) < 4:
        source = sys.argv[1] if len(sys.argv) > 1 else ""
        header = sys.argv[2] if len(sys.argv) > 2 else ""
        content = sys.argv[3] if len(sys.argv) > 3 else ""
        
        # Read content from stdin if not provided
        if len(sys.argv) == 4 and sys.argv[3] == "-":
            content = sys.stdin.read()
    else:
        source = sys.argv[1]
        header = sys.argv[2]
        content = sys.argv[3]
    
    uid, chash = generate_uuid(source, header, content)
    print(f"{uid}|{chash}")
