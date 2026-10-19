#!/usr/bin/env python3
"""Send an explicitly approved draft through the paired Xcode device connection."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

BUNDLE = 'personal.lensprompt.app'
BASE = 'Documents/LensPrompt'


def validate(data):
    if len(data) > 1_000_000:
        raise ValueError('Draft exceeds 1MB')
    value = json.loads(data.decode('utf-8'))
    if not isinstance(value, dict) or type(value.get('version')) is not int or value['version'] != 1:
        raise ValueError('Expected version 1')
    try:
        identifier = str(uuid.UUID(value['id']))
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        raise ValueError('Expected a UUID draft id') from error
    if value['id'].lower() != identifier:
        raise ValueError('Use a canonical UUID draft id')
    def text_ok(text, maximum):
        return isinstance(text, str) and bool(text.strip()) and '\x00' not in text and len(text.encode('utf-8')) <= maximum
    if not text_ok(value.get('title'), 1_000) or not text_ok(value.get('text'), 800_000):
        raise ValueError('Title and full text are required within size limits')
    points = value.get('points')
    if not isinstance(points, dict) or set(points) != {'opening', 'pain', 'solution', 'offer'} or not all(text_ok(v, 50_000) for v in points.values()):
        raise ValueError('Four nonempty speaking points are required')
    if value.get('mode') not in ('scrolling', 'talkingPoints'):
        raise ValueError('Expected scrolling or talkingPoints mode')
    return value, hashlib.sha256(data).hexdigest()


def run(arguments, timeout=30, required=True):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
    if required and result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip() or 'Device operation failed')
    return result


def receipt_matches(receipt, identifier, digest):
    return isinstance(receipt, dict) and type(receipt.get('version')) is int and receipt['version'] == 1 and str(receipt.get('id', '')).lower() == identifier.lower() and receipt.get('sha256') == digest and receipt.get('status') == 'imported'


def deliver(data, identifier, digest, *, device, simulator, wait):
    with tempfile.TemporaryDirectory(prefix='lensprompt-send-') as tmp:
        local = Path(tmp)
        payload = local / (identifier + '.json')
        marker = local / (identifier + '.ready')
        payload.write_bytes(data); marker.write_text(digest, encoding='ascii')
        if simulator:
            container = Path(run(['xcrun', 'simctl', 'get_app_container', simulator, BUNDLE, 'data']).stdout.strip())
            inbox = container / BASE / 'Inbox'
            if not inbox.is_dir():
                raise RuntimeError('Open the app once to initialize its inbox')
            for source in (payload, marker):
                # The ready file is published only after its complete payload; replace is atomic locally.
                staged = inbox / (source.name + '.upload')
                shutil.copyfile(source, staged); staged.replace(inbox / source.name)
            receipt_path = container / BASE / 'Receipts' / payload.name
        else:
            for source in (payload, marker):
                run(['xcrun', 'devicectl', 'device', 'copy', 'to', '--device', device,
                     '--source', str(source), '--destination', BASE + '/Inbox/' + source.name,
                     '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE, '--timeout', '30'], timeout=35)
            receipt_path = local / 'receipt.json'
        deadline = time.monotonic() + wait
        while True:
            if not simulator:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                seconds = max(1, min(5, int(remaining)))
                try:
                    result = run(['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', device,
                                  '--source', BASE + '/Receipts/' + payload.name, '--destination', str(receipt_path),
                                  '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE,
                                  '--timeout', str(seconds)], timeout=seconds + 2, required=False)
                except subprocess.TimeoutExpired:
                    result = None
                if result is None or result.returncode:
                    receipt_path.unlink(missing_ok=True)
            if receipt_path.exists():
                receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
                if not receipt_matches(receipt, identifier, digest):
                    raise ValueError('Receipt does not match the approved draft; do not resend with changed content under this id')
                return {'status': 'acknowledged', 'id': identifier, 'sha256': digest, 'message': 'האפליקציה אישרה את קבלת ההעברה'}
            if time.monotonic() >= deadline:
                break
            time.sleep(min(1, max(0, deadline - time.monotonic())))
        return {'status': 'queued', 'id': identifier, 'sha256': digest,
                'message': 'נשלח לתיבת הקליטה באייפון; הקליטה בספרייה טרם אומתה. פתח את מול העדשה.'}


def send(path, approved_sha256, *, device, simulator, wait):
    data = Path(path).read_bytes()
    value, digest = validate(data)
    if digest != approved_sha256:
        raise ValueError('Draft changed or approval hash is missing. Review and approve this exact draft before sending.')
    return deliver(data, str(uuid.UUID(value['id'])), digest, device=device, simulator=simulator, wait=wait)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    inspect = commands.add_parser('inspect', help='Validate without touching the phone; print the exact draft hash')
    inspect.add_argument('draft', type=Path)
    transfer = commands.add_parser('send', help='Send only after human approval of this exact draft')
    transfer.add_argument('draft', type=Path)
    transfer.add_argument('--approved-sha256', required=True)
    target = transfer.add_mutually_exclusive_group(required=True)
    target.add_argument('--device', help='Explicit paired physical device identifier')
    target.add_argument('--simulator', help='Explicit simulator UUID for development testing only')
    transfer.add_argument('--wait', type=int, choices=range(0, 61), default=12, metavar='0..60')
    args = parser.parse_args()
    try:
        if args.command == 'inspect':
            value, digest = validate(args.draft.read_bytes())
            result = {'id': value['id'], 'title': value['title'], 'sha256': digest, 'status': 'validated'}
        else:
            result = send(args.draft, args.approved_sha256, device=args.device, simulator=args.simulator, wait=args.wait)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'status': 'error', 'message': str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
