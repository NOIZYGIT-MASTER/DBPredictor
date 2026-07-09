#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path


def fingerprint(path: Path) -> dict:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return {'path': str(path), 'sha256': h.hexdigest(), 'size_bytes': path.stat().st_size}


if __name__ == '__main__':
    target = Path('/NOIZY/raw_stems')
    rows = []
    if target.exists():
        for p in sorted(target.rglob('*')):
            if p.is_file():
                rows.append(fingerprint(p))
                if len(rows) >= 20:
                    break
    print(json.dumps(rows, indent=2))
