#!/usr/bin/env python3
"""Localization pipeline for Pindrop.

The source of truth is the top-level `Localization/` tree.
This script can bootstrap that tree from the committed `.xcstrings`
files, synchronize the catalogs back out, lint for drift, and add locales.

The source-tree files are real YAML, but the parser/writer stay deliberately
small and dependency-free.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_CATALOG_DIR = ROOT / "Pindrop" / "Localization"
SOURCE_TREE_DIR = ROOT / "Localization"
GENERATED_DIR = ROOT / "Pindrop" / "Generated"

APP_CATALOG = SOURCE_CATALOG_DIR / "Localizable.xcstrings"
INFO_CATALOG = SOURCE_CATALOG_DIR / "InfoPlist.xcstrings"

APP_YAML_DIR = SOURCE_TREE_DIR / "app"
INFO_YAML_DIR = SOURCE_TREE_DIR / "infoplist"
KEYMAP_PATH = SOURCE_TREE_DIR / "keymap.yml"
LOCALES_PATH = SOURCE_TREE_DIR / "locales.yml"


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def split_yaml_key_value(line: str) -> tuple[str, str]:
    in_double = False
    in_single = False
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\" and in_double:
            escaped = True
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            continue
        if char == ":" and not in_double and not in_single:
            return line[:index], line[index + 1 :].lstrip()
    raise ValueError(f"Invalid YAML mapping line: {line!r}")


def parse_yaml_scalar(token: str) -> str:
    token = token.strip()
    if not token:
        return ""
    if token.startswith('"'):
        return str(json.loads(token))
    if token.startswith("'") and token.endswith("'") and len(token) >= 2:
        return token[1:-1].replace("''", "'")
    return token


def parse_yaml_block(lines: list[str], start_index: int, indent: int) -> tuple[Any, int]:
    mapping: dict[str, Any] = {}
    list_values: list[Any] | None = None
    index = start_index

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            index += 1
            continue

        line_indent = len(line) - len(line.lstrip(" "))
        if line_indent < indent:
            break
        if line_indent > indent:
            raise ValueError(f"Unexpected indentation in YAML block: {line!r}")

        if stripped.startswith("- "):
            if mapping:
                raise ValueError(f"Mixed mapping and list content: {line!r}")
            if list_values is None:
                list_values = []
            list_values.append(parse_yaml_scalar(stripped[2:]))
            index += 1
            continue

        if list_values is not None:
            break

        raw_key, raw_value = split_yaml_key_value(stripped)
        key = parse_yaml_scalar(raw_key)

        if raw_value.startswith("|"):
            chomp = raw_value
            index += 1
            block_lines: list[str] = []
            block_indent: int | None = None
            while index < len(lines):
                block_line = lines[index]
                if not block_line.strip():
                    block_lines.append("")
                    index += 1
                    continue

                block_line_indent = len(block_line) - len(block_line.lstrip(" "))
                if block_line_indent <= indent:
                    break

                if block_indent is None:
                    block_indent = block_line_indent

                block_lines.append(block_line[block_indent:])
                index += 1

            value = "\n".join(block_lines)
            if chomp == "|":
                value += "\n"
            mapping[key] = value
            continue

        if raw_value:
            mapping[key] = parse_yaml_scalar(raw_value)
            index += 1
            continue

        child_index = index + 1
        while child_index < len(lines):
            child_line = lines[child_index]
            child_stripped = child_line.strip()
            if not child_stripped or child_stripped.startswith("#"):
                child_index += 1
                continue
            child_indent = len(child_line) - len(child_line.lstrip(" "))
            if child_indent <= indent:
                mapping[key] = ""
                index += 1
                break
            child_value, next_index = parse_yaml_block(lines, child_index, child_indent)
            mapping[key] = child_value
            index = next_index
            break
        else:
            mapping[key] = ""
            index = child_index

    return (list_values if list_values is not None else mapping), index


def parse_yaml_locales(text: str) -> dict[str, Any]:
    result: dict[str, Any] = {}
    lines = text.splitlines()
    index = 0

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            index += 1
            continue

        indent = len(line) - len(line.lstrip(" "))
        if indent != 0:
            raise ValueError(f"Unexpected indentation in locales file: {line!r}")

        raw_key, raw_value = split_yaml_key_value(stripped)
        key = parse_yaml_scalar(raw_key)

        if key == "locales" and raw_value == "":
            child, index = parse_yaml_block(lines, index + 1, indent + 2)
            if not isinstance(child, list):
                raise ValueError("locales must be a YAML list")
            result[key] = child
            continue

        result[key] = parse_yaml_scalar(raw_value)
        index += 1

    return result


def read_yaml(path: Path) -> Any:
    text = path.read_text(encoding="utf-8")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        if path.name == "locales.yml":
            return parse_yaml_locales(text)
        parsed, index = parse_yaml_block(text.splitlines(), 0, 0)
        if not isinstance(parsed, dict):
            raise ValueError(f"Expected a YAML mapping in {path}")
        return parsed


def dump_yaml_scalar(value: str, indent: int = 0) -> str:
    if "\n" in value:
        block_indent = " " * (indent + 2)
        return "|-\n" + "\n".join(f"{block_indent}{line}" for line in value.splitlines())
    return json.dumps(value, ensure_ascii=False)


def dump_yaml_key(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_-]+", value):
        return value
    return json.dumps(value, ensure_ascii=False)


def flatten_yaml_mapping(data: Any, prefix: str = "") -> dict[str, str]:
    if isinstance(data, dict):
        flat: dict[str, str] = {}
        self_value = data.get("_self")
        if self_value is not None:
            if not prefix:
                raise ValueError("_self is only valid inside a nested mapping")
            flat[prefix] = str(self_value)

        for key, value in data.items():
            if key == "_self":
                continue
            next_prefix = f"{prefix}_{key}" if prefix else str(key)
            flat.update(flatten_yaml_mapping(value, next_prefix))
        return flat

    if prefix == "":
        raise ValueError("Expected a YAML mapping")
    return {prefix: str(data)}


def nest_flat_mapping(data: dict[str, str]) -> dict[str, Any]:
    nested: dict[str, Any] = {}
    for key, value in data.items():
        parts = key.split("_", 1)
        if len(parts) == 1:
            bucket = nested.setdefault(key, {})
            if not isinstance(bucket, dict):
                raise ValueError(f"Key collision for {key!r}")
            bucket["_self"] = value
            continue

        head, tail = parts
        bucket = nested.setdefault(head, {})
        if not isinstance(bucket, dict):
            raise ValueError(f"Key collision for {head!r}")
        bucket[tail] = value
    return nested


def dump_yaml_node(path: Path, data: dict[str, Any]) -> None:
    def render_mapping(mapping: dict[str, Any], indent: int = 0) -> list[str]:
        lines: list[str] = []
        indent_str = " " * indent
        for key, value in mapping.items():
            key_text = dump_yaml_key(str(key))
            if isinstance(value, dict):
                lines.append(f"{indent_str}{key_text}:")
                self_value = value.get("_self")
                child_items = [(child_key, child_value) for child_key, child_value in value.items() if child_key != "_self"]
                if self_value is not None:
                    lines.append(f"{indent_str}  _self: {dump_yaml_scalar(str(self_value), indent + 2)}")
                if child_items:
                    lines.extend(render_mapping(dict(child_items), indent + 2))
            else:
                lines.append(f"{indent_str}{key_text}: {dump_yaml_scalar(str(value), indent)}")
        return lines

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(render_mapping(data)) + "\n", encoding="utf-8")


def dump_yaml_flat_mapping(path: Path, data: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{dump_yaml_key(key)}: {dump_yaml_scalar(value, 0)}" for key, value in data.items()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def dump_yaml_locales(path: Path, locales: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["sourceLanguage: \"en\"", "locales:"]
    lines.extend(f"  - {json.dumps(locale, ensure_ascii=False)}" for locale in locales)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def normalize_locale(locale: str) -> str:
    return locale.replace("_", "-")


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return slug or "key"


def stable_id_for(source_key: str, used: set[str]) -> str:
    base = slugify(source_key)
    if len(base) > 48:
        base = base[:48].rstrip("_")

    candidate = base
    if candidate not in used:
        used.add(candidate)
        return candidate

    digest = hashlib.sha1(source_key.encode("utf-8")).hexdigest()[:8]
    candidate = f"{base}_{digest}"
    suffix = 1
    while candidate in used:
        suffix += 1
        candidate = f"{base}_{digest}_{suffix}"

    used.add(candidate)
    return candidate


SWIFT_KEYWORDS = {
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
    "func", "import", "init", "inout", "internal", "let", "operator",
    "private", "protocol", "public", "rethrows", "static", "struct", "subscript",
    "typealias", "var", "break", "case", "continue", "default", "defer",
    "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat",
    "return", "switch", "where", "while", "as", "Any", "catch", "false",
    "is", "nil", "super", "self", "Self", "throw", "throws", "true", "try",
}


def catalog_locales(catalog: dict[str, Any]) -> list[str]:
    locales = set()
    for entry in catalog.get("strings", {}).values():
        for locale in entry.get("localizations", {}):
            locales.add(normalize_locale(locale))
    if catalog.get("sourceLanguage"):
        locales.add(normalize_locale(catalog["sourceLanguage"]))
    return sorted(locales)


def catalog_entries(catalog: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    return [
        (key, entry)
        for key, entry in catalog.get("strings", {}).items()
        if key
    ]


def extract_translation(entry: dict[str, Any], locale: str, fallback: str) -> str:
    unit = entry.get("localizations", {}).get(locale, {}).get("stringUnit", {})
    return str(unit.get("value", fallback))


def import_catalog(source_path: Path, target_dir: Path, keymap: dict[str, str], used_ids: set[str]) -> None:
    catalog = read_json(source_path)
    source_lang = normalize_locale(catalog.get("sourceLanguage", "en"))
    locales = catalog_locales(catalog)

    source_file = target_dir / f"{source_lang}.yml"
    locale_files = {locale: target_dir / f"{locale}.yml" for locale in locales if locale != source_lang}

    source_payload: dict[str, str] = {}
    locale_payloads: dict[str, dict[str, str]] = {locale: {} for locale in locale_files}

    for source_key, entry in catalog_entries(catalog):
        stable_id = keymap.get(source_key)
        if stable_id is None:
            stable_id = stable_id_for(source_key, used_ids)
            keymap[source_key] = stable_id

        source_value = extract_translation(entry, source_lang, source_key)
        source_payload[stable_id] = source_value

        for locale in locale_files:
            locale_payloads[locale][stable_id] = extract_translation(entry, locale, source_value)

    dump_yaml_node(source_file, nest_flat_mapping(source_payload))
    for locale, payload in locale_payloads.items():
        dump_yaml_node(locale_files[locale], nest_flat_mapping(payload))


def load_keymap() -> dict[str, str]:
    if KEYMAP_PATH.exists():
        return read_yaml(KEYMAP_PATH)
    return {}


def load_locales() -> list[str]:
    if not LOCALES_PATH.exists():
        return []
    data = read_yaml(LOCALES_PATH)
    return [normalize_locale(locale) for locale in data.get("locales", [])]


def write_locales(locales: list[str]) -> None:
    dump_yaml_locales(LOCALES_PATH, locales)


def read_domain_files(domain_dir: Path) -> dict[str, dict[str, str]]:
    files: dict[str, dict[str, str]] = {}
    for path in sorted(domain_dir.glob("*.yml")):
        files[normalize_locale(path.stem)] = flatten_yaml_mapping(read_yaml(path))
    return files


def sync_catalog(domain_name: str, output_path: Path, domain_files: dict[str, dict[str, str]], locales: list[str], keymap: dict[str, str]) -> None:
    source_lang = "en"
    source_payload = domain_files.get(source_lang)
    if source_payload is None:
        raise SystemExit(f"Missing {domain_name} source file: {source_lang}.yml")

    all_ids = set(source_payload.keys())
    for locale in locales:
        all_ids.update(domain_files.get(locale, {}).keys())

    reverse_keymap = {stable: source for source, stable in keymap.items()}
    catalog = {"sourceLanguage": source_lang, "version": "1.0", "strings": {}}

    for stable_id in sorted(all_ids):
        source_value = source_payload.get(stable_id, stable_id)
        entry: dict[str, Any] = {
            "comment": reverse_keymap.get(stable_id, source_value),
            "extractionState": "manual",
            "localizations": {},
        }

        for locale in locales:
            locale_value = domain_files.get(locale, {}).get(stable_id, source_value)
            entry["localizations"][locale] = {
                "stringUnit": {
                    "state": "translated" if locale_value else "new",
                    "value": locale_value,
                }
            }

        catalog["strings"][stable_id] = entry

    write_json(output_path, catalog)


def build_source_key_map(domain_files: list[dict[str, dict[str, str]]]) -> dict[str, str]:
    source_key_map: dict[str, str] = {}
    for files in domain_files:
        source_payload = files.get("en", {})
        for stable_id, source_value in source_payload.items():
            source_key_map.setdefault(source_value, stable_id)
    return source_key_map


def emit_generated_swift(keymap: dict[str, str], source_key_map: dict[str, str], locales: list[str]) -> None:
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)

    metadata_lines = [
        "//",
        "//  LocalizationMetadata.swift",
        "//  Pindrop",
        "//",
        "//  Generated by scripts/localization.py.",
        "//",
        "",
        "import Foundation",
        "import CryptoKit",
        "",
        "enum LocalizationMetadata {",
        "    static let supportedLocales: [String] = [",
    ]
    for locale in locales:
        metadata_lines.append(f'        "{locale}",')
    metadata_lines.extend([
        "    ]",
        "",
        "    static let stableKeyMap: [String: String] = [",
    ])
    for source_key in sorted(keymap):
        stable_id = keymap[source_key]
        escaped_source = json.dumps(source_key, ensure_ascii=False)
        escaped_stable = json.dumps(stable_id, ensure_ascii=False)
        metadata_lines.append(f"        {escaped_source}: {escaped_stable},")
    metadata_lines.extend([
        "    ]",
        "",
        "    static let sourceKeyMap: [String: String] = [",
    ])
    for source_text in sorted(source_key_map):
        stable_id = source_key_map[source_text]
        escaped_source = json.dumps(source_text, ensure_ascii=False)
        escaped_stable = json.dumps(stable_id, ensure_ascii=False)
        metadata_lines.append(f"        {escaped_source}: {escaped_stable},")
    metadata_lines.extend([
        "    ]",
        "",
        "    static func stableKey(for key: String) -> String {",
        "        if let mapped = stableKeyMap[key] {",
        "            return mapped",
        "        }",
        "",
        "        if let mapped = sourceKeyMap[key] {",
        "            return mapped",
        "        }",
        "",
        "        for candidate in stableKeyCandidates(for: key) {",
        "            if let mapped = stableKeyMap[candidate] ?? sourceKeyMap[candidate] {",
        "                return mapped",
        "            }",
        "        }",
        "",
        "        return key",
        "    }",
        "",
        "    private static func stableKeyCandidates(for key: String) -> [String] {",
        "        let normalized = normalizedSourceKey(for: key)",
        "        let hashed = hashedSourceKey(for: key, normalized: normalized)",
        "        let candidates = [key, normalized, hashed]",
        "        var seen = Set<String>()",
        "        return candidates.filter { seen.insert($0).inserted }",
        "    }",
        "",
        "    private static func normalizedSourceKey(for key: String) -> String {",
        "        let lowered = key.lowercased()",
        "        let slugged = lowered.replacingOccurrences(of: \"[^a-z0-9]+\", with: \"_\", options: .regularExpression)",
        "        let trimmed = slugged.trimmingCharacters(in: CharacterSet(charactersIn: \"_\"))",
        "        let truncated = trimmed.count > 48 ? String(trimmed.prefix(48)).trimmingCharacters(in: CharacterSet(charactersIn: \"_\")) : trimmed",
        "        return truncated.isEmpty ? \"key\" : truncated",
        "    }",
        "",
        "    private static func hashedSourceKey(for key: String, normalized: String) -> String {",
        "        let digest = Insecure.SHA1.hash(data: Data(key.utf8))",
        "        let digestString = digest.map { String(format: \"%02x\", $0) }.joined()",
        "        return \"\\(normalized)_\\(digestString.prefix(8))\"",
        "    }",
        "}",
        "",
    ])
    (GENERATED_DIR / "LocalizationMetadata.swift").write_text("\n".join(metadata_lines), encoding="utf-8")

    keys_lines = [
        "//",
        "//  L10nKeys.swift",
        "//  Pindrop",
        "//",
        "//  Generated by scripts/localization.py.",
        "//",
        "",
        "enum L10nKeys {",
    ]
    for source_key in sorted(keymap):
        stable_id = keymap[source_key]
        name = re.sub(r"[^A-Za-z0-9]+", " ", stable_id).strip().split()
        if not name:
            continue
        camel = name[0].lower() + "".join(part.capitalize() for part in name[1:])
        camel = re.sub(r"^([0-9])", r"_\1", camel)
        if camel in SWIFT_KEYWORDS:
            camel = f"_{camel}"
        keys_lines.append(f'    static let {camel} = "{stable_id}"')
    keys_lines.extend(["}", ""])
    (GENERATED_DIR / "L10nKeys.swift").write_text("\n".join(keys_lines), encoding="utf-8")


def import_current() -> None:
    keymap: dict[str, str] = {}
    used_ids: set[str] = set()

    import_catalog(APP_CATALOG, APP_YAML_DIR, keymap, used_ids)
    import_catalog(INFO_CATALOG, INFO_YAML_DIR, keymap, used_ids)

    locales = sorted({*catalog_locales(read_json(APP_CATALOG)), *catalog_locales(read_json(INFO_CATALOG))})
    write_locales(locales)
    dump_yaml_flat_mapping(KEYMAP_PATH, keymap)


def sync() -> None:
    keymap = load_keymap()
    locales = load_locales()
    if not locales:
        locales = ["en"]

    app_files = read_domain_files(APP_YAML_DIR)
    info_files = read_domain_files(INFO_YAML_DIR)

    sync_catalog("app", APP_CATALOG, app_files, locales, keymap)
    sync_catalog("infoplist", INFO_CATALOG, info_files, locales, keymap)
    source_key_map = build_source_key_map([app_files, info_files])
    emit_generated_swift(keymap, source_key_map, locales)


def lint() -> int:
    keymap = load_keymap()
    locales = load_locales()
    problems: list[str] = []

    if not keymap:
        problems.append("keymap.yml is missing or empty")
    if not locales:
        problems.append("locales.yml is missing or empty")

    for domain_name, domain_dir in (("app", APP_YAML_DIR), ("infoplist", INFO_YAML_DIR)):
        files = read_domain_files(domain_dir)
        if "en" not in files:
            problems.append(f"{domain_name}: missing en.yml")
            continue

        source_ids = set(files["en"].keys())
        for locale in locales:
            locale_ids = set(files.get(locale, {}).keys())
            missing = sorted(source_ids - locale_ids)
            if missing:
                problems.append(f"{domain_name}: {locale}.yml is missing {len(missing)} keys")

    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1

    print("Localization files look consistent.")
    return 0


def add_locale(locale: str) -> None:
    locale = normalize_locale(locale)
    locales = load_locales()
    if locale not in locales:
        locales.append(locale)
        locales.sort()
        write_locales(locales)

    for domain_dir in (APP_YAML_DIR, INFO_YAML_DIR):
        source_file = domain_dir / "en.yml"
        if not source_file.exists():
            continue
        source_payload = read_yaml(source_file)
        target_file = domain_dir / f"{locale}.yml"
        if not target_file.exists():
            dump_yaml_node(target_file, nest_flat_mapping(source_payload))


def main() -> int:
    parser = argparse.ArgumentParser(description="Pindrop localization pipeline")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("import-current", help="Bootstrap YAML from committed xcstrings")
    subparsers.add_parser("sync", help="Regenerate xcstrings and generated Swift")
    subparsers.add_parser("lint", help="Validate localization tree")
    add_locale_parser = subparsers.add_parser("add-locale", help="Add a locale to the source tree")
    add_locale_parser.add_argument("locale", help="Locale identifier, e.g. ja or pt-BR")

    args = parser.parse_args()

    if args.command == "import-current":
        import_current()
        return 0
    if args.command == "sync":
        sync()
        return 0
    if args.command == "lint":
        return lint()
    if args.command == "add-locale":
        add_locale(args.locale)
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
