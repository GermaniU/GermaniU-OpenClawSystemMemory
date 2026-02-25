#!/usr/bin/env python3
"""
Extract sections from Markdown files.
Outputs JSON with file, header, level, and content for each section.
"""

import json
import re
import sys

def extract_sections(filepath, filename):
    """Extract ## and ### headers with their content from markdown file."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        return []
    
    # Pattern for headers level 2 and 3
    header_pattern = r'^(#{2,3})\s+(.+)$'
    
    lines = content.split('\n')
    sections = []
    current_section = None
    section_lines = []
    section_level = 0
    
    for line in lines:
        header_match = re.match(header_pattern, line)
        
        if header_match:
            # Save previous section
            if current_section is not None and section_lines:
                section_text = '\n'.join(section_lines).strip()
                if section_text:
                    sections.append({
                        'file': filename,
                        'header': current_section,
                        'level': section_level,
                        'content': section_text
                    })
            
            # Start new section
            section_level = len(header_match.group(1))
            current_section = header_match.group(2).strip()
            section_lines = [line]
        elif current_section is not None:
            section_lines.append(line)
    
    # Save last section
    if current_section is not None and section_lines:
        section_text = '\n'.join(section_lines).strip()
        if section_text:
            sections.append({
                'file': filename,
                'header': current_section,
                'level': section_level,
                'content': section_text
            })
    
    # If no headers found, treat entire file as one section
    if not sections:
        sections.append({
            'file': filename,
            'header': '(document)',
            'level': 0,
            'content': content.strip()
        })
    
    return sections

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: extract_sections.py <filepath> <filename>"}), file=sys.stderr)
        sys.exit(1)
    
    filepath = sys.argv[1]
    filename = sys.argv[2]
    
    sections = extract_sections(filepath, filename)
    print(json.dumps(sections, ensure_ascii=False))
