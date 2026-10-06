#!/usr/bin/env python3
import re
import sys
import ast
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
SOURCE = ROOT_DIR / "TokenStepSwift/Sources/TokenStepSwift/Support/Localization.swift"
LANGUAGES = [".en", ".zhHant"]
FORMAT_PATTERN = re.compile(r"%(?:\d+\$)?(?:[+\-0 #]*)?(?:\d+|\*)?(?:\.\d+)?[@df]")


def extract_block(source: str, language: str) -> str:
    marker = f"{language}: ["
    start = source.find(marker)
    if start < 0:
        raise ValueError(f"Missing translation block: {language}")

    bracket = source.find("[", start)
    depth = 0
    in_string = False
    escaped = False
    for index in range(bracket, len(source)):
        character = source[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue

        if character == '"':
            in_string = True
        elif character == "[":
            depth += 1
        elif character == "]":
            depth -= 1
            if depth == 0:
                return source[bracket:index + 1]

    raise ValueError(f"Unclosed translation block: {language}")


def swift_unescape(value: str) -> str:
    return ast.literal_eval(f'"{value}"')


def translations(block: str) -> list[tuple[str, str]]:
    pairs = []
    pair_pattern = re.compile(
        r'"((?:\\.|[^"\\])*)"\s*:\s*"((?:\\.|[^"\\])*)"\s*,?'
    )
    for match in pair_pattern.finditer(block):
        pairs.append((swift_unescape(match.group(1)), swift_unescape(match.group(2))))
    return pairs


def placeholders(text: str) -> list[str]:
    return FORMAT_PATTERN.findall(text)


def main() -> int:
    source = SOURCE.read_text(encoding="utf-8")
    failed = False

    for language in LANGUAGES:
        block = extract_block(source, language)
        pairs = translations(block)
        seen = {}
        for index, (key, value) in enumerate(pairs, 1):
            if key in seen:
                print(f"{language}: duplicate key {key!r} at entries {seen[key]} and {index}")
                failed = True
            else:
                seen[key] = index

            key_formats = placeholders(key)
            value_formats = placeholders(value)
            if key_formats != value_formats:
                print(
                    f"{language}: placeholder mismatch for {key!r}: "
                    f"{key_formats!r} -> {value_formats!r}"
                )
                failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
