#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path('/NOIZY/raw_stems')


def main() -> None:
    files = 0
    bytes_total = 0
    exts: dict[str, int] = {}

    if ROOT.exists():
        for path in ROOT.rglob('*'):
            if not path.is_file():
                continue
            files += 1
            try:
                size = path.stat().st_size
            except OSError:
                size = 0
            bytes_total += size
            ext = path.suffix.lower() or '[none]'
            exts[ext] = exts.get(ext, 0) + 1

    print(
        json.dumps(
            {
                'root': str(ROOT),
                'files': files,
                'bytes_total': bytes_total,
                'top_extensions': sorted(exts.items(), key=lambda x: x[1], reverse=True)[:20],
            },
            indent=2,
        )
    )


if __name__ == '__main__':
    main()
