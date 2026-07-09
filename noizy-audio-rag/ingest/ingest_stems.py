#!/usr/bin/env python3
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = Path('/NOIZY/raw_stems')


def run(input_dir: Path) -> dict:
    count = 0
    for path in input_dir.rglob('*'):
        if path.is_file():
            count += 1
    return {'stage': 'ingest', 'input': str(input_dir), 'files_seen': count}


if __name__ == '__main__':
    print(json.dumps(run(DEFAULT_INPUT), indent=2))
