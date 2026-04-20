#!/usr/bin/env python3

import argparse
import html
import re
from pathlib import Path


def render_inline_markdown(text: str) -> str:
    escaped = html.escape(text)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(
        r"\[([^\]]+)\]\((https?://[^\s)]+)\)",
        r'<a href="\2">\1</a>',
        escaped,
    )
    escaped = re.sub(
        r'(?<!["=])(https?://[^\s<]+)',
        r'<a href="\1">\1</a>',
        escaped,
    )
    return escaped


def render_markdown(markdown: str) -> str:
    lines = markdown.splitlines()
    blocks: list[str] = []
    paragraph: list[str] = []
    list_items: list[str] = []

    def flush_paragraph() -> None:
        nonlocal paragraph
        if not paragraph:
            return
        text = " ".join(line.strip() for line in paragraph)
        blocks.append(f"<p>{render_inline_markdown(text)}</p>")
        paragraph = []

    def flush_list() -> None:
        nonlocal list_items
        if not list_items:
            return
        items = "".join(f"<li>{render_inline_markdown(item)}</li>" for item in list_items)
        blocks.append(f"<ul>{items}</ul>")
        list_items = []

    for raw_line in lines:
        line = raw_line.rstrip()
        stripped = line.strip()

        if not stripped:
            flush_paragraph()
            flush_list()
            continue

        heading_match = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading_match:
            flush_paragraph()
            flush_list()
            level = len(heading_match.group(1))
            content = render_inline_markdown(heading_match.group(2).strip())
            blocks.append(f"<h{level}>{content}</h{level}>")
            continue

        bullet_match = re.match(r"^-\s+(.*)$", stripped)
        if bullet_match:
            flush_paragraph()
            list_items.append(bullet_match.group(1).strip())
            continue

        flush_list()
        paragraph.append(stripped)

    flush_paragraph()
    flush_list()
    return "\n".join(blocks)


def build_document(body_html: str, version: str, app_name: str) -> str:
    title = html.escape(f"{app_name} {version} Release Notes")
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <title>{title}</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #ffffff;
      --surface: #f6f7fb;
      --text: #1b1c1f;
      --muted: #5d6470;
      --border: #d8dde6;
      --code-bg: #eef2f7;
      --link: #175cd3;
    }}

    @media (prefers-color-scheme: dark) {{
      :root {{
        --bg: #111318;
        --surface: #171a21;
        --text: #f2f4f8;
        --muted: #a7b0bd;
        --border: #2a3140;
        --code-bg: #1e2633;
        --link: #7cb3ff;
      }}
    }}

    html, body {{
      margin: 0;
      padding: 0;
      background: var(--bg);
      color: var(--text);
      font: 15px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
    }}

    body {{
      padding: 20px;
    }}

    main {{
      max-width: 760px;
      margin: 0 auto;
    }}

    h1, h2, h3 {{
      line-height: 1.25;
      margin: 1.2em 0 0.45em;
    }}

    h1 {{
      font-size: 1.7rem;
      margin-top: 0;
    }}

    h2 {{
      font-size: 1.2rem;
      padding-bottom: 0.2em;
      border-bottom: 1px solid var(--border);
    }}

    h3 {{
      font-size: 1rem;
    }}

    p {{
      margin: 0.7em 0;
      color: var(--text);
    }}

    ul {{
      margin: 0.6em 0 1em 1.2em;
      padding: 0;
    }}

    li {{
      margin: 0.45em 0;
    }}

    strong {{
      font-weight: 600;
    }}

    code {{
      font: 0.92em/1.4 ui-monospace, "SF Mono", Menlo, Consolas, monospace;
      background: var(--code-bg);
      padding: 0.12em 0.35em;
      border-radius: 6px;
    }}

    a {{
      color: var(--link);
      text-decoration: none;
    }}

    a:hover {{
      text-decoration: underline;
    }}
  </style>
</head>
<body>
  <main>
{body_html}
  </main>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Render release notes markdown to standalone HTML")
    parser.add_argument("--input", required=True, help="Path to the markdown release notes file")
    parser.add_argument("--output", required=True, help="Path to write the HTML output")
    parser.add_argument("--version", required=True, help="Display version for the HTML title")
    parser.add_argument("--app-name", default="Pindrop", help="App name for the HTML title")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    markdown = input_path.read_text(encoding="utf-8")
    body_html = render_markdown(markdown)
    document = build_document(body_html, args.version, args.app_name)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(document, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
