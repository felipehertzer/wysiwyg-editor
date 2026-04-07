#!/usr/bin/env bash
#
# apply-fixes.sh — Re-apply custom fixes after a new Froala release.
#
# Fixes applied:
#   1. image.min.js      — Guard width/height with hasAttribute() check
#   2. word_paste.min.js — Preserve "data-fr-image-pasted" during paste cleanup
#   3. dark.css          — Remove unscoped .fr-clearfix / .fr-hide-by-clipping rules
#   4. dark.min.css      — Same as above (minified version)
#
# Usage:
#   ./apply-fixes.sh
#

set -euo pipefail

cd "$(dirname "$0")"

PASS=0
FAIL=0
SKIP=0

python3 << 'PYEOF'
import re, sys, json

results = []

def apply_fix(filepath, desc, search_re, replace_fn, already_applied_check):
    """Apply a regex-based fix to a file."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        results.append(("SKIP", desc, "file not found"))
        return

    # Check if fix is already applied
    if already_applied_check(content):
        results.append(("SKIP", desc, "already applied"))
        return

    # Try to apply
    new_content, count = search_re.subn(replace_fn, content, count=1)
    if count == 0:
        results.append(("FAIL", desc, "pattern not found - upstream may have changed"))
        return

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    results.append(("OK", desc, ""))


# ── Fix 1: image.min.js — hasAttribute guard for width/height ──────────────
#
# Upstream pattern (variable names change each release):
#   V1=V2[V3].style.width||V1,V4=V2[V3].style.height||FUNC(V2[V3]).height()
#
# Fixed pattern:
#   V1=!V2[V3].hasAttribute("width")&&(V2[V3].style.width||V1),
#   V4=!V2[V3].hasAttribute("height")&&(V2[V3].style.height||FUNC(V2[V3]).height())

apply_fix(
    "js/plugins/image.min.js",
    'image.min.js: hasAttribute guard for width/height',
    re.compile(
        r'(\w)=(\w)\[(\w)\]\.style\.width\|\|\1,'
        r'(\w)=\2\[\3\]\.style\.height\|\|(\w)\(\2\[\3\]\)\.height\(\)'
    ),
    lambda m: (
        f'{m[1]}=!{m[2]}[{m[3]}].hasAttribute("width")&&({m[2]}[{m[3]}].style.width||{m[1]}),'
        f'{m[4]}=!{m[2]}[{m[3]}].hasAttribute("height")&&({m[2]}[{m[3]}].style.height||{m[5]}({m[2]}[{m[3]}]).height())'
    ),
    lambda c: 'hasAttribute("width")' in c
)


# ── Fix 2: word_paste.min.js — preserve data-fr-image-pasted ───────────────
#
# Upstream pattern:
#   .startsWith("data-")||V.toLowerCase().startsWith("xml:")
#
# Fixed pattern:
#   .startsWith("data-")&&"data-fr-image-pasted"!==V.toLowerCase()||V.toLowerCase().startsWith("xml:")

apply_fix(
    "js/plugins/word_paste.min.js",
    'word_paste.min.js: preserve data-fr-image-pasted attribute',
    re.compile(
        r'\.startsWith\("data-"\)\|\|(\w)\.toLowerCase\(\)\.startsWith\("xml:"\)'
    ),
    lambda m: (
        f'.startsWith("data-")&&"data-fr-image-pasted"!=={m[1]}.toLowerCase()'
        f'||{m[1]}.toLowerCase().startsWith("xml:")'
    ),
    lambda c: 'data-fr-image-pasted' in c and 'startsWith("data-")&&"data-fr-image-pasted"' in c
)


# ── Fix 3: dark.min.css — remove unscoped generic rules ────────────────────
#
# These two rules are not scoped to .dark-theme and conflict with the base stylesheet.

apply_fix(
    "css/themes/dark.min.css",
    'dark.min.css: remove unscoped .fr-clearfix/.fr-hide-by-clipping',
    re.compile(
        r'\.fr-clearfix::after\{clear:both;display:block;content:"";height:0\}'
        r'\.fr-hide-by-clipping\{position:absolute;width:1px;height:1px;'
        r'padding:0;margin:-1px;overflow:hidden;clip:rect\(0, 0, 0, 0\);border:0\}'
    ),
    '',
    lambda c: '.fr-clearfix::after' not in c
)


# ── Fix 4: dark.css — remove unscoped generic rules (unminified) ───────────

apply_fix(
    "css/themes/dark.css",
    'dark.css: remove unscoped .fr-clearfix/.fr-hide-by-clipping',
    re.compile(
        r'\.fr-clearfix::after\s*\{[^}]*\}\s*'
        r'\.fr-hide-by-clipping\s*\{[^}]*\}\s*',
        re.DOTALL
    ),
    '',
    lambda c: '.fr-clearfix::after' not in c
)


# ── Print results ──────────────────────────────────────────────────────────
for status, desc, detail in results:
    suffix = f" ({detail})" if detail else ""
    print(f"  {status:4s}  {desc}{suffix}")

ok = sum(1 for s, _, _ in results if s == "OK")
skip = sum(1 for s, _, _ in results if s == "SKIP")
fail = sum(1 for s, _, _ in results if s == "FAIL")
print(f"\nDone: {ok} applied, {skip} skipped, {fail} failed")

sys.exit(1 if fail > 0 else 0)
PYEOF
