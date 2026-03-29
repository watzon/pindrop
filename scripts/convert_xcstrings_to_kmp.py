#!/usr/bin/env python3
"""
convert_xcstrings_to_kmp.py

Converts Apple's .xcstrings localization catalogs to Kotlin Multiplatform
Resources format (per-locale values/strings.xml files).

Reads:
  - Pindrop/Localization/Localizable.xcstrings (607 keys, 11 locales)
  - Pindrop/Localization/InfoPlist.xcstrings (permission strings)

Generates:
  - shared/ui-localization/src/commonMain/resources/values/strings.xml
  - shared/ui-localization/src/commonMain/resources/values-{locale}/strings.xml
  - Key mapping JSON for Swift bridge lookup

Usage:
  python3 scripts/convert_xcstrings_to_kmp.py
  python3 scripts/convert_xcstrings_to_kmp.py --verify
"""

import json
import os
import re
import sys
import hashlib
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

# --- Configuration ---

PROJECT_ROOT = Path(__file__).resolve().parent.parent
XCSTRINGS_PATH = PROJECT_ROOT / "Pindrop" / "Localization" / "Localizable.xcstrings"
INFOPLIST_XCSTRINGS_PATH = (
    PROJECT_ROOT / "Pindrop" / "Localization" / "InfoPlist.xcstrings"
)
OUTPUT_DIR = (
    PROJECT_ROOT / "shared" / "ui-localization" / "src" / "commonMain" / "resources"
)
KEY_MAPPING_OUTPUT = (
    PROJECT_ROOT
    / "shared"
    / "ui-localization"
    / "src"
    / "commonMain"
    / "resources"
    / "key_mapping.json"
)
KOTLIN_PACKAGE_DIR = (
    PROJECT_ROOT
    / "shared"
    / "ui-localization"
    / "src"
    / "commonMain"
    / "kotlin"
    / "tech"
    / "watzon"
    / "pindrop"
    / "shared"
    / "uilocalization"
)

# Locale directory mapping (Apple locale → Android/KMP resource directory)
LOCALE_DIR_MAP = {
    "en": "values",
    "de": "values-de",
    "es": "values-es",
    "fr": "values-fr",
    "it": "values-it",
    "ja": "values-ja",
    "ko": "values-ko",
    "nl": "values-nl",
    "pt-BR": "values-pt-rBR",
    "tr": "values-tr",
    "zh-Hans": "values-zh-rHans",
}

ALL_LOCALES = list(LOCALE_DIR_MAP.keys())


def xml_attr_escape(s: str) -> str:
    """Escape a string for use as XML attribute value (strings.xml <string> body)."""
    # Must escape: & < > ' "
    s = s.replace("&", "&amp;")
    s = s.replace("<", "&lt;")
    s = s.replace(">", "&gt;")
    s = s.replace("'", "\\'")
    s = s.replace('"', '\\"')
    return s


def convert_format_specifiers(value: str) -> str:
    """
    Convert Apple format specifiers to Kotlin/JVM format.

    Apple:     %@      → Kotlin: %s
    Apple:     %lld    → Kotlin: %d
    Apple:     %d      → Kotlin: %d
    Apple:     %%      → stays %%

    Multi-parameter strings get positional args: %1$s, %2$s, %3$s
    """
    # Count format specifiers (excluding %%)
    # Pattern: %[number]$[flags][width][.precision][length]type
    # Apple uses: %@, %lld, %d, %f, %ld

    # First, handle %lld → %d
    value = value.replace("%lld", "%d")

    # Now count actual format specifiers
    # We need to find all %X patterns that aren't %%
    spec_pattern = re.compile(r"%(?!%)\d*\$?[l]{0,2}[difs@u]")

    matches = list(spec_pattern.finditer(value))
    if len(matches) <= 1:
        # Single or no format spec: just do simple conversion
        value = re.sub(r"%(?!%)\d*\$?@", "%s", value)
        return value

    # Multiple format specifiers → use positional
    # Replace from right to left to preserve positions
    result = value
    for i in range(len(matches) - 1, -1, -1):
        match = matches[i]
        original = match.group()
        pos = i + 1

        # Determine type
        if "@" in original:
            replacement = f"%{pos}$s"
        elif "d" in original or "i" in original or "u" in original:
            replacement = f"%{pos}$d"
        elif "f" in original:
            replacement = f"%{pos}$f"
        else:
            replacement = f"%{pos}$s"

        result = result[: match.start()] + replacement + result[match.end() :]

    return result


def generate_kmp_identifier(key: str, existing_ids: set, index: int) -> str:
    """
    Generate a valid KMP resource identifier from an xcstrings key.

    Rules:
    - Short keys (≤60 chars, no format specifiers or special chars) → snake_case of the key
    - Keys with format specifiers → snake_case with _fmt suffix
    - Long keys → abbreviated identifier
    - All identifiers must be unique, lowercase, snake_case, start with letter
    """
    # Empty key
    if not key or key.strip() == "":
        return f"empty_{index}"

    # Strip surrounding quotes and whitespace
    cleaned = key.strip()
    if cleaned.startswith('"') and cleaned.endswith('"'):
        cleaned = cleaned[1:-1].strip()

    # Remove surrounding escaped quotes pattern
    if cleaned.startswith('""') and cleaned.endswith('""'):
        cleaned = cleaned[2:-2].strip()

    # Check if it's a short, simple key (no newlines, no special formatting)
    is_short = len(cleaned) <= 80 and "\n" not in cleaned and "\\n" not in cleaned
    has_format = "%@" in key or "%lld" in key or "%d" in key

    if is_short and not has_format:
        # Simple key → snake_case
        identifier = cleaned.lower()
        # Replace non-alphanumeric with underscore
        identifier = re.sub(r"[^a-z0-9]", "_", identifier)
        # Collapse multiple underscores
        identifier = re.sub(r"_+", "_", identifier)
        # Strip leading/trailing underscores
        identifier = identifier.strip("_")
        # Ensure starts with letter
        if identifier and identifier[0].isdigit():
            identifier = f"n_{identifier}"
        if not identifier:
            identifier = f"key_{index}"

        # Ensure uniqueness
        base = identifier
        counter = 2
        while identifier in existing_ids:
            identifier = f"{base}_{counter}"
            counter += 1
        return identifier

    elif is_short and has_format:
        # Format key → snake_case with descriptive name
        identifier = cleaned.lower()
        # Remove format specifiers for the identifier name
        temp = re.sub(r"%\d*\$?[l]{0,2}[diufs@]", "", identifier)
        temp = re.sub(r"%%", "pct", temp)
        identifier = temp.strip()
        identifier = re.sub(r"[^a-z0-9]", "_", identifier)
        identifier = re.sub(r"_+", "_", identifier)
        identifier = identifier.strip("_")

        if not identifier:
            identifier = f"fmt_{index}"
        # Add _fmt suffix to indicate format string
        if not identifier.endswith("_fmt"):
            identifier = f"{identifier}_fmt"

        if identifier[0].isdigit():
            identifier = f"n_{identifier}"

        base = identifier
        counter = 2
        while identifier in existing_ids:
            identifier = f"{base}_{counter}"
            counter += 1
        return identifier

    else:
        # Long key → generate abbreviated identifier from content
        # Take first meaningful words
        words = re.split(r"[\s\n\\n]+", cleaned)
        # Filter out empty and short words
        meaningful = [
            w
            for w in words
            if len(w) > 2
            and w
            not in (
                "the",
                "and",
                "for",
                "your",
                "this",
                "that",
                "with",
                "has",
                "was",
                "are",
                "not",
                "can",
                "but",
                "all",
                "its",
                "our",
            )
        ]

        if meaningful:
            # Take first 3-4 words
            parts = meaningful[:4]
            identifier = "_".join(w.lower() for w in parts)
        else:
            # Fallback to hash
            h = hashlib.md5(key.encode()).hexdigest()[:8]
            identifier = f"long_{h}"

        identifier = re.sub(r"[^a-z0-9]", "_", identifier)
        identifier = re.sub(r"_+", "_", identifier)
        identifier = identifier.strip("_")

        if has_format and not identifier.endswith("_fmt"):
            identifier = f"{identifier}_fmt"

        if not identifier or identifier[0].isdigit():
            identifier = f"msg_{index}"

        base = identifier
        counter = 2
        while identifier in existing_ids:
            identifier = f"{base}_{counter}"
            counter += 1
        return identifier


def get_localized_value(
    key_data: dict, locale: str, fallback_to_key: bool = True
) -> str | None:
    """Extract the localized string value for a given locale from key data."""
    localizations = key_data.get("localizations", {})

    if locale == "en":
        # English is the source — check en localization first, then use key
        en_loc = localizations.get("en", {}).get("stringUnit", {})
        if en_loc.get("state") in ("translated", "new"):
            return en_loc.get("value", None)
        # For English, the key IS often the value
        if fallback_to_key:
            return None  # Will use key as fallback
        return None

    loc_data = localizations.get(locale, {}).get("stringUnit", {})
    if loc_data.get("state") in ("translated", "new"):
        return loc_data.get("value", None)

    return None


def convert_xcstrings(xcstrings_path: Path, output_dir: Path) -> dict:
    """
    Convert an xcstrings file to KMP Multiplatform Resources format.

    Returns: dict mapping xcstrings_key → kmp_identifier
    """
    with open(xcstrings_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    strings = data.get("strings", {})

    # Phase 1: Generate all identifiers (pass 1 to determine uniqueness)
    key_to_id = {}
    existing_ids = set()
    skip_keys = {"": True}  # Skip empty key

    for index, (key, val) in enumerate(strings.items()):
        if key in skip_keys:
            continue

        # Skip keys with no localizations at all
        if not val or (
            not val.get("localizations")
            and val.get("extractionState") == "stale"
            and not val.get("localizations")
        ):
            continue

        identifier = generate_kmp_identifier(key, existing_ids, index)
        key_to_id[key] = identifier
        existing_ids.add(identifier)

    # Phase 2: Generate per-locale strings.xml files
    for locale in ALL_LOCALES:
        locale_dir_name = LOCALE_DIR_MAP[locale]
        locale_dir = output_dir / locale_dir_name
        locale_dir.mkdir(parents=True, exist_ok=True)

        strings_entries = []

        for key, val in strings.items():
            if key in skip_keys:
                continue
            if key not in key_to_id:
                continue

            identifier = key_to_id[key]

            # Get localized value
            value = get_localized_value(val, locale)

            if value is None:
                if locale == "en":
                    # For English, the key IS the value
                    value = key
                else:
                    # For other locales, fall back to English or key
                    value = get_localized_value(val, "en")
                    if value is None:
                        value = key

            # Convert format specifiers for KMP
            value = convert_format_specifiers(value)

            # Escape for XML
            value = xml_attr_escape(value)

            strings_entries.append(f'    <string name="{identifier}">{value}</string>')

        # Write strings.xml
        content = '<?xml version="1.0" encoding="utf-8"?>\n'
        content += "<resources>\n"
        content += "\n".join(strings_entries) + "\n"
        content += "</resources>\n"

        with open(locale_dir / "strings.xml", "w", encoding="utf-8") as f:
            f.write(content)

        print(
            f"  Generated {locale_dir_name}/strings.xml ({len(strings_entries)} keys)"
        )

    return key_to_id


def generate_strings_bundle(
    xcstrings_path: Path, key_mapping: dict, output_dir: Path
) -> dict:
    """
    Generate a JSON bundle with all localized strings for runtime access.
    Format: { "locale": { "kmp_identifier": "localized string" } }
    """
    with open(xcstrings_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    strings = data.get("strings", {})
    skip_keys = {"": True}

    bundle: dict[str, dict[str, str]] = {}

    for locale in ALL_LOCALES:
        locale_strings: dict[str, str] = {}

        for key, val in strings.items():
            if key in skip_keys or key not in key_mapping:
                continue

            identifier = key_mapping[key]

            # Get localized value
            value = get_localized_value(val, locale)
            if value is None:
                if locale == "en":
                    value = key
                else:
                    value = get_localized_value(val, "en")
                    if value is None:
                        value = key

            # Convert format specifiers to Kotlin format
            value = convert_format_specifiers(value)

            locale_strings[identifier] = value

        bundle[locale] = locale_strings

    # Write the bundle JSON
    bundle_path = output_dir / "strings_bundle.json"
    with open(bundle_path, "w", encoding="utf-8") as f:
        json.dump(bundle, f, ensure_ascii=False, indent=2)

    total_entries = sum(len(v) for v in bundle.values())
    print(
        f"  Generated strings_bundle.json ({total_entries} total entries across {len(bundle)} locales)"
    )
    return bundle


def _escape_kotlin_string(s: str) -> str:
    """Escape a string for use in a Kotlin string literal."""
    return (
        s.replace("\\", "\\\\")
        .replace("$", "\\$")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "")
    )


def generate_strings_kotlin(bundle: dict, key_mapping: dict, output_path: Path):
    """
    Generate SharedLocalization.kt with embedded key mapping and all localized strings.
    """
    # Build key mapping entries
    mapping_entries = []
    for xc_key, kmp_id in sorted(key_mapping.items()):
        escaped_key = _escape_kotlin_string(xc_key)
        escaped_id = _escape_kotlin_string(kmp_id)
        mapping_entries.append(f'        "{escaped_key}" to "{escaped_id}"')
    mapping_code = ",\n".join(mapping_entries)

    # Build locale string entries
    locale_entries = []
    for locale in sorted(bundle.keys()):
        string_entries = []
        for kmp_id, value in sorted(bundle[locale].items()):
            escaped_id = _escape_kotlin_string(kmp_id)
            escaped_value = _escape_kotlin_string(value)
            string_entries.append(
                f'                        "{escaped_id}" to "{escaped_value}"'
            )
        strings_code = ",\n".join(string_entries)
        locale_entries.append(
            f'            "{locale}" to mapOf(\n{strings_code}\n            )'
        )
    locale_map_code = ",\n".join(locale_entries)

    kotlin_code = f"""//
//  SharedLocalization.kt
//  Pindrop
//
//  Created on 2026-03-29.
//
//  AUTO-GENERATED by convert_xcstrings_to_kmp.py — do not edit manually.
//

package tech.watzon.pindrop.shared.uilocalization

/**
 * Shared localization authority.
 *
 * Provides runtime string lookup by xcstrings key and locale.
 * All strings are embedded from Localizable.xcstrings.
 * Swift calls [getString] to resolve localized text at runtime.
 */
object SharedLocalization {{

    /**
     * Mapping from xcstrings keys to KMP resource identifiers.
     */
    internal val _keyMapping: Map<String, String> = mapOf(
{mapping_code}
    )

    /**
     * Reverse mapping from KMP identifiers to xcstrings keys.
     */
    internal val _reverseMapping: Map<String, String> = _keyMapping.entries.associate {{ it.value to it.key }}

    /**
     * All localized strings: locale → (kmpId → localized value).
     */
    private val _strings: Map<String, Map<String, String>> = mapOf(
{locale_map_code}
    )

    /**
     * Returns all KMP resource string identifiers.
     */
    fun allKeys(): Set<String> {{
        return _keyMapping.values.toSet()
    }}

    /**
     * Check if a given KMP identifier exists.
     */
    fun hasKey(key: String): Boolean {{
        return _keyMapping.values.contains(key)
    }}

    /**
     * Returns the set of supported locale codes.
     */
    fun supportedLocales(): Set<String> {{
        return setOf(
            "en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "tr", "zh-Hans"
        )
    }}

    /**
     * Returns the bidirectional mapping from xcstrings keys to KMP resource identifiers.
     */
    fun keyMapping(): Map<String, String> {{
        return _keyMapping.toMap()
    }}

    /**
     * Look up a KMP identifier from an xcstrings key.
     */
    fun kmpIdentifierForXcKey(xcKey: String): String? {{
        return _keyMapping[xcKey]
    }}

    /**
     * Look up an xcstrings key from a KMP identifier.
     */
    fun xcKeyForKmpIdentifier(kmpId: String): String? {{
        return _reverseMapping[kmpId]
    }}

    /**
     * Resolve a localized string by its original xcstrings key and locale.
     *
     * This is the primary entry point for Swift consumers.
     * Falls back to English if the locale is not found,
     * then falls back to the key itself if no translation exists.
     */
    fun getString(xcKey: String, locale: String): String {{
        val kmpId = _keyMapping[xcKey] ?: return xcKey
        return getStringById(kmpId, locale)
    }}

    /**
     * Resolve a localized string by its KMP identifier and locale.
     */
    fun getStringById(kmpId: String, locale: String): String {{
        // Try exact locale match
        val localeStrings = _strings[locale]
        if (localeStrings != null) {{
            val value = localeStrings[kmpId]
            if (value != null) return value
        }}

        // Try language-only fallback (e.g., "pt" from "pt-BR")
        val langOnly = locale.split("-").firstOrNull()
        if (langOnly != null && langOnly != locale) {{
            for ((locKey, locStrings) in _strings) {{
                if (locKey.startsWith(langOnly)) {{
                    val value = locStrings[kmpId]
                    if (value != null) return value
                }}
            }}
        }}

        // Fall back to English
        val enStrings = _strings["en"]
        if (enStrings != null) {{
            val value = enStrings[kmpId]
            if (value != null) return value
        }}

        // Last resort: return the key
        return kmpId
    }}
}}
"""

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(kotlin_code)

    print(
        f"  Generated SharedLocalization.kt with {len(key_mapping)} key mappings and {len(bundle)} locales"
    )


def save_key_mapping_json(key_mapping: dict, output_path: Path):
    """Save the key mapping as JSON for reference/tooling."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(key_mapping, f, ensure_ascii=False, indent=2)
    print(f"  Generated key_mapping.json ({len(key_mapping)} entries)")


def verify(key_mapping: dict, output_dir: Path):
    """Verify the conversion output matches expectations."""
    errors = []

    # Check locale directories exist
    for locale in ALL_LOCALES:
        locale_dir = output_dir / LOCALE_DIR_MAP[locale]
        strings_file = locale_dir / "strings.xml"
        if not strings_file.exists():
            errors.append(f"Missing {locale_dir}/strings.xml")
        else:
            # Count entries
            with open(strings_file, "r") as f:
                content = f.read()
            count = content.count("<string name=")
            print(f"  {LOCALE_DIR_MAP[locale]}/strings.xml: {count} entries")

    # Check key count
    if len(key_mapping) < 500:
        errors.append(f"Only {len(key_mapping)} keys mapped, expected ~607")

    # Check format specifier conversion
    for locale in ALL_LOCALES:
        locale_dir = output_dir / LOCALE_DIR_MAP[locale]
        strings_file = locale_dir / "strings.xml"
        if not strings_file.exists():
            continue
        with open(strings_file, "r") as f:
            content = f.read()
        # Should not contain %@ or %lld (should be converted)
        if "%@" in content:
            # Count occurrences
            count = content.count("%@")
            if count > 0:
                errors.append(f"{locale}: Found {count} unconverted %@ specifiers")
        if "%lld" in content:
            count = content.count("%lld")
            if count > 0:
                errors.append(f"{locale}: Found {count} unconverted %lld specifiers")

    # Check total string files count
    xml_files = list(output_dir.glob("values*/strings.xml"))
    expected_count = len(ALL_LOCALES)  # en goes in values/ + 10 locale dirs = 11
    if len(xml_files) != expected_count:
        errors.append(
            f"Expected {expected_count} strings.xml files, found {len(xml_files)}"
        )

    if errors:
        print("\n❌ VERIFICATION FAILED:")
        for e in errors:
            print(f"  - {e}")
        return False
    else:
        print("\n✅ VERIFICATION PASSED")
        return True


def main():
    verify_only = "--verify" in sys.argv

    print("=== Converting xcstrings to KMP Multiplatform Resources ===\n")

    # Convert main Localizable.xcstrings
    print("Processing Localizable.xcstrings...")
    key_mapping = convert_xcstrings(XCSTRINGS_PATH, OUTPUT_DIR)
    print(f"  Total keys mapped: {len(key_mapping)}\n")

    # Save key mapping
    save_key_mapping_json(key_mapping, KEY_MAPPING_OUTPUT)

    # Generate strings bundle JSON and get the bundle data
    bundle = generate_strings_bundle(XCSTRINGS_PATH, key_mapping, OUTPUT_DIR)

    # Generate Kotlin code with embedded strings and key mapping
    generate_strings_kotlin(
        bundle, key_mapping, KOTLIN_PACKAGE_DIR / "SharedLocalization.kt"
    )

    # Verify
    print("\nVerification:")
    if not verify(key_mapping, OUTPUT_DIR):
        sys.exit(1)

    print(
        f"\nDone. {len(key_mapping)} keys converted across {len(ALL_LOCALES)} locales."
    )


if __name__ == "__main__":
    main()
