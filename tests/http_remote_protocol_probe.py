#!/usr/bin/env python3

import argparse
import json
import struct
from pathlib import Path


TARGET_REF = b"refs/heads/main"
ZERO_OBJECT_HEX = "00" * 32
OBJECT_KIND_COMMIT = 0


def encode_varuint(value: int) -> bytes:
    if value < 0:
        raise ValueError("varuint must be non-negative")
    out = bytearray()
    current = value
    while current >= 0x80:
        out.append((current & 0x7F) | 0x80)
        current >>= 7
    out.append(current)
    return bytes(out)


def decode_varuint(data: bytes, offset: int) -> tuple[int, int]:
    shift = 0
    value = 0
    start = offset
    while True:
        if offset >= len(data):
            raise ValueError("unexpected eof while decoding varuint")
        byte = data[offset]
        offset += 1
        payload = byte & 0x7F
        if shift >= 64 or (shift == 63 and payload > 1):
            raise ValueError("non-canonical varuint")
        value |= payload << shift
        if (byte & 0x80) == 0:
            break
        shift += 7
        if shift > 63:
            raise ValueError("non-canonical varuint")
    if len(encode_varuint(value)) != offset - start:
        raise ValueError("non-canonical varuint")
    return value, offset


def encode_bytes(value: bytes) -> bytes:
    return encode_varuint(len(value)) + value


def decode_bytes(data: bytes, offset: int) -> tuple[bytes, int]:
    size, offset = decode_varuint(data, offset)
    end = offset + size
    if end > len(data):
        raise ValueError("unexpected eof while decoding bytes")
    return data[offset:end], end


def read_head_hex(repo_root: Path) -> str:
    return (repo_root / ".hgit/refs/heads/main").read_text(encoding="utf-8").strip()


def object_path(repo_root: Path, object_hex: str) -> Path:
    return repo_root / ".hgit/objects/loose" / object_hex[:2] / object_hex[2:]


def ensure_hex_id(value: str) -> bytes:
    raw = bytes.fromhex(value)
    if len(raw) != 32:
        raise ValueError(f"expected 32-byte hex id, got {value}")
    return raw


def cmd_capabilities_check(args: argparse.Namespace) -> int:
    payload = json.loads(Path(args.json_path).read_text(encoding="utf-8"))
    assert payload["service"] == "hypergit-http-remote"
    assert payload["version"] == 1
    assert payload["default_branch"] == "main"
    assert payload["auth_required"] is True
    assert payload["max_body_bytes"] == args.expected_max_body_bytes
    assert payload["routes"] == {
        "capabilities": "/capabilities",
        "object_batch": "/objects/batch",
        "manifest_query": "/manifest/query",
        "fetch": "/fetch",
        "push": "/push",
    }
    return 0


def cmd_batch_request(args: argparse.Namespace) -> int:
    object_ids = [ensure_hex_id(value) for value in args.object_ids]
    body = bytearray()
    body.extend(encode_varuint(len(object_ids)))
    for object_id in object_ids:
        body.extend(object_id)
    Path(args.output_path).write_bytes(body)
    return 0


def cmd_batch_check(args: argparse.Namespace) -> int:
    data = Path(args.response_path).read_bytes()
    repo_root = Path(args.repo_root)
    expected_present_hex = args.expected_present_hex
    expected_missing_hex = args.expected_missing_hex
    expected_bytes = object_path(repo_root, expected_present_hex).read_bytes()

    offset = 0
    count, offset = decode_varuint(data, offset)
    assert count == 2

    object_id = data[offset:offset + 32].hex()
    offset += 32
    present = data[offset]
    offset += 1
    assert object_id == expected_present_hex
    assert present == 1
    kind = int.from_bytes(data[offset:offset + 2], "little")
    offset += 2
    assert kind == OBJECT_KIND_COMMIT
    object_bytes, offset = decode_bytes(data, offset)
    assert object_bytes == expected_bytes

    object_id = data[offset:offset + 32].hex()
    offset += 32
    present = data[offset]
    offset += 1
    assert object_id == expected_missing_hex
    assert present == 0
    assert offset == len(data)
    return 0


def cmd_fetch_request(args: argparse.Namespace) -> int:
    body = bytearray()
    body.extend(encode_varuint(0))
    body.extend(encode_bytes(TARGET_REF))
    body.extend(encode_bytes(b""))
    body.extend(encode_varuint(0))
    body.append(1)
    Path(args.output_path).write_bytes(body)
    return 0


def cmd_fetch_check(args: argparse.Namespace) -> int:
    data = Path(args.response_path).read_bytes()
    repo_root = Path(args.repo_root)
    expected_head = ensure_hex_id(args.expected_head_hex)
    assert len(data) == 152

    offset = 0
    view_id = data[offset:offset + 32]
    offset += 32
    head_commit = data[offset:offset + 32]
    offset += 32
    manifest_root = data[offset:offset + 32]
    offset += 32
    serving_index_snapshot = data[offset:offset + 32]
    offset += 32
    lineage_watermark = int.from_bytes(data[offset:offset + 8], "little")
    offset += 8
    dependency_watermark = int.from_bytes(data[offset:offset + 8], "little")
    offset += 8
    created_at_ms = struct.unpack("<q", data[offset:offset + 8])[0]
    offset += 8

    assert offset == len(data)
    assert head_commit == expected_head
    assert manifest_root != bytes(32)
    assert serving_index_snapshot == bytes(32)
    assert lineage_watermark == 0
    assert dependency_watermark == 0
    assert created_at_ms > 0
    assert object_path(repo_root, view_id.hex()).is_file()
    return 0


def iter_repo_objects(repo_root: Path) -> list[tuple[str, bytes]]:
    root = repo_root / ".hgit/objects/loose"
    objects: list[tuple[str, bytes]] = []
    for directory in sorted(path for path in root.iterdir() if path.is_dir()):
        for path in sorted(file for file in directory.iterdir() if file.is_file()):
            object_hex = f"{directory.name}{path.name}"
            objects.append((object_hex, path.read_bytes()))
    return objects


def cmd_push_request(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root)
    objects = iter_repo_objects(repo_root)
    head_hex = read_head_hex(repo_root)

    body = bytearray()
    body.extend(encode_varuint(len(objects)))
    for object_hex, object_bytes in objects:
        body.extend(ensure_hex_id(object_hex))
        body.extend(encode_bytes(object_bytes))
    body.extend(encode_bytes(TARGET_REF))
    body.extend(ensure_hex_id(head_hex))

    Path(args.output_path).write_bytes(body)
    print(len(objects))
    return 0


def cmd_push_check(args: argparse.Namespace) -> int:
    data = Path(args.response_path).read_bytes()
    accepted, offset = decode_varuint(data, 0)
    assert accepted == args.expected_count
    assert offset == len(data)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    capabilities_check = subparsers.add_parser("capabilities-check")
    capabilities_check.add_argument("json_path")
    capabilities_check.add_argument("expected_max_body_bytes", type=int)
    capabilities_check.set_defaults(func=cmd_capabilities_check)

    batch_request = subparsers.add_parser("batch-request")
    batch_request.add_argument("output_path")
    batch_request.add_argument("object_ids", nargs="+")
    batch_request.set_defaults(func=cmd_batch_request)

    batch_check = subparsers.add_parser("batch-check")
    batch_check.add_argument("response_path")
    batch_check.add_argument("repo_root")
    batch_check.add_argument("expected_present_hex")
    batch_check.add_argument("expected_missing_hex")
    batch_check.set_defaults(func=cmd_batch_check)

    fetch_request = subparsers.add_parser("fetch-request")
    fetch_request.add_argument("output_path")
    fetch_request.set_defaults(func=cmd_fetch_request)

    fetch_check = subparsers.add_parser("fetch-check")
    fetch_check.add_argument("response_path")
    fetch_check.add_argument("repo_root")
    fetch_check.add_argument("expected_head_hex")
    fetch_check.set_defaults(func=cmd_fetch_check)

    push_request = subparsers.add_parser("push-request")
    push_request.add_argument("repo_root")
    push_request.add_argument("output_path")
    push_request.set_defaults(func=cmd_push_request)

    push_check = subparsers.add_parser("push-check")
    push_check.add_argument("response_path")
    push_check.add_argument("expected_count", type=int)
    push_check.set_defaults(func=cmd_push_check)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
