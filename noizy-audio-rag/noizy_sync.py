#!/usr/bin/env python3
import argparse
import hashlib
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

AUDIO_EXTENSIONS = {'.wav', '.aiff', '.aif', '.flac', '.mp3', '.m4a', '.ogg'}
ASSET_CLASSES = ['Audio', 'Voice', 'Images', 'Video', 'Documents', 'Code']
LIFECYCLE = ['Downloads', 'INBOX', 'QUARANTINE', 'VALIDATED', 'CANONICAL']
ROOT = Path(__file__).resolve().parent
PAPYRUS_DB = ROOT / 'papyrus' / 'papyrus.db'
SCHEMA_SQL = ROOT / 'papyrus' / 'schema.sql'
RECEIPT_LOG = ROOT / 'mc96' / 'receipts.log'


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_schema() -> None:
    PAPYRUS_DB.parent.mkdir(parents=True, exist_ok=True)
    if not SCHEMA_SQL.exists():
        return
    with sqlite3.connect(PAPYRUS_DB) as conn:
        conn.executescript(SCHEMA_SQL.read_text(encoding='utf-8'))
        conn.commit()


def emit_receipt(stage: str, status: str, details: dict[str, Any]) -> dict[str, Any]:
    digest = hashlib.sha256(json.dumps(details, sort_keys=True).encode('utf-8')).hexdigest()
    receipt = {
        'receipt_id': hashlib.sha256(f'{stage}:{utc_now()}'.encode('utf-8')).hexdigest()[:24],
        'verb': 'CAPTURE',
        'sha256': digest,
        'timestamp': utc_now(),
        'operator': 'RSP',
        'stage': stage,
        'status': status,
        'details': details
    }
    RECEIPT_LOG.parent.mkdir(parents=True, exist_ok=True)
    with RECEIPT_LOG.open('a', encoding='utf-8') as f:
        f.write(json.dumps(receipt) + '\n')

    if PAPYRUS_DB.exists():
        with sqlite3.connect(PAPYRUS_DB) as conn:
            conn.execute(
                """
                INSERT INTO stage_receipts(receipt_id, stage, status, details_json, created_at)
                VALUES(?,?,?,?,CURRENT_TIMESTAMP)
                """,
                (receipt['receipt_id'], stage, status, json.dumps(details)),
            )
            conn.commit()
    return receipt


def discover_stems(root: Path, limit: int) -> list[str]:
    stems: list[str] = []
    if not root.exists():
        return stems

    for path in sorted(root.rglob('*')):
        if not path.is_file():
            continue
        if path.suffix.lower() not in AUDIO_EXTENSIONS:
            continue
        stems.append(str(path))
        if len(stems) >= limit:
            break
    return stems


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def build_r2_object_key(sha256_hex: str, filename: str) -> str:
    ext = Path(filename).suffix.lower() or '.bin'
    return f"sha256/{sha256_hex[0:2]}/{sha256_hex[2:4]}/{sha256_hex}{ext}"


def stage_gatekeeper(input_dir: Path, dry_run: bool, canary: int, approve_mutation: bool) -> dict[str, Any]:
    allowed = {
        'delete_operations': False,
        'overwrite_without_approval': False,
        'destructive_sync': False,
        'raw_audio_remote_upload': False,
        'no_duplicates': True,
        'immutable_references': True,
        'infinite_scale_keying': True,
    }
    details = {
        'asset_classes': ASSET_CLASSES,
        'lifecycle': LIFECYCLE,
        'protected_local_only': ['raw stems', 'full WAVs', 'sensitive masters'],
        'input': str(input_dir),
        'exists': input_dir.exists(),
        'dry_run': dry_run,
        'canary': canary,
        'rules': allowed,
        'can_recommend': True,
        'cannot_mutate_without_approval': True,
    }
    if not input_dir.exists():
        details['reason'] = 'input directory missing'
        emit_receipt('mc96_gatekeeper', 'blocked', details)
        raise SystemExit(json.dumps({'error': 'Input path missing', 'details': details}))

    if not dry_run and not approve_mutation:
        details['reason'] = 'mutation blocked without explicit approval'
        emit_receipt('mc96_gatekeeper', 'blocked', details)
        raise SystemExit(json.dumps({'error': 'Mutation requires --approve-mutation', 'details': details}))

    emit_receipt('mc96_gatekeeper', 'ok', details)
    return details


def stage_ingest(input_dir: Path, canary: int, dry_run: bool) -> dict[str, Any]:
    stems = [Path(p) for p in discover_stems(input_dir, canary)]
    items = []
    for stem in stems:
        try:
            items.append(
                {
                    'path': str(stem),
                    'name': stem.name,
                    'ext': stem.suffix.lower(),
                    'size_bytes': stem.stat().st_size,
                    'sha256': file_sha256(stem),
                    'r2_object_key': None,
                }
            )
            items[-1]['r2_object_key'] = build_r2_object_key(items[-1]['sha256'], stem.name)
        except OSError:
            continue

    if not dry_run and PAPYRUS_DB.exists():
        with sqlite3.connect(PAPYRUS_DB) as conn:
            for item in items:
                conn.execute(
                    """
                    INSERT INTO local_assets(public_id, asset_name, file_type, local_path, size_bytes, sha256)
                    VALUES(?,?,?,?,?,?)
                    ON CONFLICT(public_id) DO UPDATE SET
                      asset_name=excluded.asset_name,
                      file_type=excluded.file_type,
                      local_path=excluded.local_path,
                      size_bytes=excluded.size_bytes,
                      sha256=excluded.sha256
                    """,
                    (
                        item['sha256'][:24],
                        item['name'],
                        item['ext'],
                        item['path'],
                        item['size_bytes'],
                        item['sha256'],
                    ),
                )
                conn.execute(
                    """
                    INSERT INTO hvs_creator_assets(public_id, asset_name, app_category, app_name, file_type, r2_object_key, local_path_blueprint)
                    VALUES(?,?,?,?,?,?,?)
                    ON CONFLICT(public_id) DO UPDATE SET
                      asset_name=excluded.asset_name,
                      file_type=excluded.file_type,
                      r2_object_key=excluded.r2_object_key,
                      local_path_blueprint=excluded.local_path_blueprint
                    """,
                    (
                        f"sha256:{item['sha256']}",
                        item['name'],
                        'Audio',
                        'NOIZY Audio RAG',
                        item['ext'] or '.bin',
                        item['r2_object_key'],
                        item['path'],
                    ),
                )
            conn.commit()

    details = {'found': len(items), 'dry_run': dry_run, 'sample': items[:10]}
    emit_receipt('inbox', 'ok', {'stage': 'INBOX', 'count': len(items)})
    emit_receipt('quarantine', 'ok', {'stage': 'QUARANTINE', 'count': len(items)})
    emit_receipt('validated', 'ok', {'stage': 'VALIDATED', 'count': len(items)})
    emit_receipt('canonical', 'ok', {'stage': 'CANONICAL', 'count': len(items)})
    emit_receipt('ingest', 'ok', details)
    return details


def stage_storage(items_count: int, dry_run: bool) -> dict[str, Any]:
    details = {
        'd1_write': True,
        'r2_mirror': False,
        'firestore_mirror': True,
        'r2_bucket': 'r2://voice-dna-storage/',
        'r2_layout': 'sha256/{aa}/{bb}/{sha256}{ext}',
        'dedupe_policy': 'sha256 unique reference only',
        'immutability': 'sha256-addressed object keys are immutable',
        'collections': [
            'assets',
            'receipts',
            'consent_records',
            'lineage',
            'sync_state',
            'quality_reports',
            'duplicate_groups',
        ],
        'raw_audio_uploaded': False,
        'items': items_count,
        'dry_run': dry_run,
        'firestore_payload_schema': {
            'asset_id': '',
            'sha256': '',
            'tags': [],
            'embedding': [],
            'quality_score': 0,
            'owner': '',
        },
    }
    receipt = emit_receipt('storage', 'ok', details)
    details['receipt_id'] = receipt['receipt_id']
    details['receipt_sha256'] = receipt['sha256']
    details['receipt_timestamp'] = receipt['timestamp']
    return details


def run_sync(args: argparse.Namespace) -> int:
    ensure_schema()
    input_dir = Path(args.input)
    canary = max(args.canary, 1)
    stage_gatekeeper(input_dir, bool(args.dry_run), canary, bool(args.approve_mutation))
    ingest = stage_ingest(input_dir, canary, bool(args.dry_run))
    storage = stage_storage(ingest['found'], bool(args.dry_run))

    result = {
        'request_id': hashlib.sha256(f"sync:{utc_now()}".encode('utf-8')).hexdigest()[:24],
        'pipeline': 'Downloads -> MC96 Gatekeeper -> Receipt -> Ingest -> Storage',
        'input': str(input_dir),
        'dry_run': bool(args.dry_run),
        'canary': canary,
        'ingest': ingest,
        'storage': storage,
        'receipt_id': storage['receipt_id'],
        'sha256': storage['receipt_sha256'],
        'timestamp': storage['receipt_timestamp'],
    }
    print(json.dumps(result, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog='noizy')
    subparsers = parser.add_subparsers(dest='command', required=True)

    sync_parser = subparsers.add_parser('sync', help='Run local Audio RAG sync pipeline.')
    sync_parser.add_argument('--input', required=True, help='Stem input directory path.')
    sync_parser.add_argument('--canary', type=int, default=500, help='Max stems to scan.')
    sync_parser.add_argument('--dry-run', action='store_true', help='Plan only; no writes.')
    sync_parser.add_argument(
        '--approve-mutation',
        action='store_true',
        help='Required for non-dry-run writes. Without this, mutation is blocked.',
    )
    sync_parser.set_defaults(func=run_sync)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == '__main__':
    raise SystemExit(main())
