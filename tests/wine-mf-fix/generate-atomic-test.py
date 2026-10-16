#!/usr/bin/env python3
"""Extract actual candidate function body for a synthetic native-only fixture.
The fixture models only the fields this function accesses, not full Wine ABI.
"""
import hashlib, json, sys
from pathlib import Path
source, output = Path(sys.argv[1]), Path(sys.argv[2])
s = source.read_text()
a = s.index('static NTSTATUS wg_parser_stream_try_read(void *args)')
b = s.index('\nstatic NTSTATUS wg_parser_stream_copy_buffer', a)
body = s[a:b]
output.mkdir(parents=True, exist_ok=True)
(output / 'atomic-body.h').write_text(body)
(output / 'body-provenance.json').write_text(json.dumps({
    'source': str(source), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'body_sha256': hashlib.sha256(body.encode()).hexdigest(),
    'scope': 'actual function body; synthetic parser layout/GstBuffer; not full runtime ABI or MF scheduling'
}, indent=2))
