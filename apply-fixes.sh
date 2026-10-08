#!/usr/bin/env bash
#
# apply-fixes.sh — Re-apply custom fixes after a new Froala release.
#
# Fixes applied:
#   1. image.min.js      — Guard width/height with hasAttribute() check
#   2. word_paste.min.js — Preserve "data-fr-image-pasted" during paste cleanup
#   3. dark.css          — Remove unscoped .fr-clearfix / .fr-hide-by-clipping rules
#   4. dark.min.css      — Same as above (minified version)
#   5. image.min.js      — Re-mark pasted images after cleanup so uploads always run
#   6. image.min.js      — Avoid S3 key collisions during simultaneous image uploads
#   7. S3 image bundles  — Honor an exact server-signed S3 key when supplied
#   8. core bundles      — Format a text selection inside one selected table cell
#                          instead of overwriting it
#   9. url bundles       — Give a typed www./bare-domain link a real scheme, not "//"
#  10. link bundles      — Open Link opens a new tab and leaves the link's target alone
#  11. link bundles      — Put the caret after a link inserted at the caret
#  12. core bundles      — Undo/redo first save typing that is still waiting for its
#                          undo step
#  13. core bundles      — Enter at the end of a formatted P/DIV keeps its formatting
#                          (ENTER_BR)
#  14. colors bundles    — Enter in the HEX field applies the colour
#  15. lists bundles     — The list type "Default" resets the markers
#  16. core bundles      — Style inlining scores the selector that matched (selector
#                          lists, :where)
#  17. image bundles     — An image copied in a browser is uploaded from the clipboard
#  18. image bundles     — A handle resize writes the new width/height attributes, in
#                          whole pixels
#  19. table bundles     — Table properties keeps an unaligned table where it was
#  20. core bundles      — Style inlining keeps properties the browser lacks (mso-*)
#  21. image bundles     — A resize starts from the image's own width, so Cmd/Ctrl+-
#                          shrinks it and a drag doesn't grow it by 2px
#  22. line_breaker bundles — The "+" shows between two touching tables
#  23. line_breaker bundles — The "+" below an inline image adds a line under it
#  24. table bundles     — The table hover outline is never saved
#  25. table bundles     — Back/Escape on the Insert table grid keeps the caret
#  26. image bundles     — Escape on a selected image doesn't reach a dialog around
#                          the editor
#  27. link bundles      — Insert with an empty URL keeps the popup open, field marked
#  28. emoticons bundles — A flag is saved without a zero-width joiner
#  29. word_paste bundles — A paragraph border (Outlook's line above "From:")
#                          survives the unwrap of its div
#  30. core + AI bundles — The AI popup stays on screen: not flipped above the
#                          editor (dialogs, editors low on a page), top kept below
#                          the window's and scroll box's top
#  31. AI bundles        — Esc in the AI popup closes it, and not the dialog around it
#  32. core bundles      — An expanded "more" row is as tall as its buttons' real
#                          lines (AI Assist was cut off at 386–404px)
#  33. core bundles      — A shortcut whose command has no toolbar button runs the
#                          plugin command with the editor (no TypeError)
#  34. core bundles      — A Safari/Apple Mail/Notes copy (caret-color) is not taken
#                          for Word
#  35. core bundles      — The selection actions popup doesn't take the focus back
#                          from the toolbar (Alt+F10 with words selected)
#  36. core bundles      — keys.forceUndo clears its typing timer handle, so undo
#                          stops saving a step every time
#  37. core bundles      — Formatting into a non-editable wrapper of blocks
#                          (<signature>) no longer recurses until the stack overflows
#  38. core bundles      — Formatting met from outside goes around a non-editable
#                          wrapper of blocks instead of wrapping it (Select All +
#                          Bold no longer bolds the whole signature)
#  39. image bundles     — An image copied in Safari or Apple Mail (caret-color) is
#                          uploaded from the clipboard, not taken for OneNote
#  40. AI bundles        — Enter in the AI prompt asks a follow-up typed under a
#                          suggestion; on an empty prompt it inserts the suggestion
#  41. AI bundles        — The AI popup is moved up when the answer makes it tall
#                          (editors low on a page or in a dialog kept Insert below
#                          the window)
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

def apply_fix(filepath, desc, search_re, replace_fn, already_applied_check, count=1):
    """Apply a regex-based fix to a file (count=0 fixes every occurrence)."""
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
    new_content, replaced = search_re.subn(replace_fn, content, count=count)
    if replaced == 0:
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


# ── Fix 7: image bundles — honor an exact server-signed S3 key ───────────────
#
# Froala normally derives the object key from keyStart. Exact-key POST policies
# instead sign one server-generated key, so appending timestamps or filenames
# makes the browser request fail policy validation. Prefer an explicit `key`
# while preserving the collision-resistant keyStart behavior as a fallback.

exact_s3_key_pattern = re.compile(
    r'(\w)\.append\("key",(\w)\.opts\.imageUploadToS3\.keyStart'
    r'\+\(new Date\)\.getTime\(\)\+"-"\+'
    r'(?:Math\.random\(\)\.toString\(36\)\.slice\(2\)\+"-"\+)?'
    r'\((\w)\.name\|\|"untitled"\)\)'
)

for image_bundle in (
    "js/plugins/image.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        image_bundle,
        f'{image_bundle}: honor an exact server-signed S3 key',
        exact_s3_key_pattern,
        lambda m: (
            f'{m[1]}.append("key",{m[2]}.opts.imageUploadToS3.key||'
            f'{m[2]}.opts.imageUploadToS3.keyStart+(new Date).getTime()+"-"'
            f'+Math.random().toString(36).slice(2)+"-"+({m[3]}.name||"untitled"))'
        ),
        lambda c: '.opts.imageUploadToS3.key||' in c
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


# ── Fix 5: image.min.js — re-mark pasted images after cleanup ──────────────
#
# The image plugin marks pasted <img> tags in paste.beforeCleanup, but Froala's
# cleanup can remove that internal data attribute when htmlAllowedAttrs is
# customized. Re-marking uploadable images in paste.afterCleanup keeps
# paste.after deterministic without requiring app-level sanitizer knowledge.

apply_fix(
    "js/plugins/image.min.js",
    'image.min.js: re-mark pasted images after cleanup',
    re.compile(
        r'(function [A-Za-z_$][\w$]*\(e\)\{e=e\.replace\(/<img /gi,\'<img data-fr-image-pasted="true" \'\);'
        r'var t=([A-Za-z_$][\w$]*)\.doc\.createElement\("div"\);'
        r'return t\.innerHTML=e,[A-Za-z_$][\w$]*=0<t\.textContent\.trim\(\)\.length,e\})'
        r'(function [A-Za-z_$][\w$]*\(e\)\{)'
    ),
    lambda m: (
        m[1]
        + f'function frReMarkPastedImages(e){{var t={m[2]}.doc.createElement("div");t.innerHTML=e;'
        + 'for(var a=t.querySelectorAll("img"),i=0;i<a.length;i++){'
        + 'var n=a[i].getAttribute("src")||"";'
        + '(0===n.indexOf("data:")||0===n.indexOf("blob:")||0===n.indexOf("http"))'
        + '&&a[i].setAttribute("data-fr-image-pasted","true")}'
        + 'return t.innerHTML}'
        + m[3]
    ),
    lambda c: 'function frReMarkPastedImages(e){' in c
)

apply_fix(
    "js/plugins/image.min.js",
    'image.min.js: run re-mark hook after paste cleanup',
    re.compile(
        r'([A-Za-z_$][\w$]*)\.events\.on\("paste\.before",([A-Za-z_$][\w$]*)\),'
        r'\1\.events\.on\("paste\.beforeCleanup",([A-Za-z_$][\w$]*)\),'
        r'\1\.events\.on\("paste\.after",([A-Za-z_$][\w$]*)\)'
    ),
    lambda m: (
        f'{m[1]}.events.on("paste.before",{m[2]}),'
        f'{m[1]}.events.on("paste.beforeCleanup",{m[3]}),'
        f'{m[1]}.events.on("paste.afterCleanup",frReMarkPastedImages),'
        f'{m[1]}.events.on("paste.after",{m[4]})'
    ),
    lambda c: '.events.on("paste.afterCleanup",frReMarkPastedImages)' in c
)


# ── Fix 6: image.min.js — collision-resistant S3 object keys ─────────────────
#
# Froala's S3 uploader used Date.getTime() alone for pasted Blob filenames and
# S3 keys. Multi-image Word paste can enqueue several uploads in the same
# millisecond, causing every image to POST to the same object key and resolve to
# the same CDN URL. Add a random segment to the key so simultaneous uploads do
# not overwrite each other.

apply_fix(
    "js/plugins/image.min.js",
    'image.min.js: avoid S3 key collisions for simultaneous uploads',
    re.compile(
        r'i\.append\("key",S\.opts\.imageUploadToS3\.keyStart\+\(new Date\)\.getTime\(\)\+"-"\+\(e\.name\|\|"untitled"\)\)'
    ),
    lambda m: (
        'i.append("key",S.opts.imageUploadToS3.keyStart+(new Date).getTime()+"-"'
        '+Math.random().toString(36).slice(2)+"-"+(e.name||"untitled"))'
    ),
    lambda c: 'Math.random().toString(36).slice(2)+"-"+(e.name||"untitled")' in c
)


# ── Fix 8: core bundles — keep the text when formatting inside one table cell ─
#
# A click in a table cell marks it .fr-selected-cell (for the table popup), and
# the mark can outlive a drag that then selects text in that cell. With exactly
# one selected cell, format.applyStyle/apply first insert a temporary marker
# with html.insert, which replaces the selected text: changing the font, size,
# colour or bold of copy in a template table emptied the cell. A text selection
# means the user is formatting that text, so drop the cell mark and let the
# normal text path format the selection.
#
# Upstream pattern (variable names change each release):
#   V1=V2.table.selectedCells();if(!V3&&0<V1.length&&V4){
#
# Fixed pattern:
#   V1=V2.table.selectedCells();if(!V3&&1===V1.length&&!V2.selection.isCollapsed()
#     &&(V2.$el.find(".fr-selected-cell").removeClass("fr-selected-cell"),
#        V1=V2.table.selectedCells()),!V3&&0<V1.length&&V4){

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: keep the selected text when formatting inside one selected table cell',
        re.compile(r'(\w)=(\w)\.table\.selectedCells\(\);if\(!(\w)&&0<\1\.length&&(\w)\)\{'),
        lambda m: (
            f'{m[1]}={m[2]}.table.selectedCells();'
            f'if(!{m[3]}&&1==={m[1]}.length&&!{m[2]}.selection.isCollapsed()'
            f'&&({m[2]}.$el.find(".fr-selected-cell").removeClass("fr-selected-cell"),'
            f'{m[1]}={m[2]}.table.selectedCells()),'
            f'!{m[3]}&&0<{m[1]}.length&&{m[4]}){{'
        ),
        lambda c: re.search(
            r'if\(!\w&&1===\w\.length&&!\w\.selection\.isCollapsed\(\)'
            r'&&\(\w\.\$el\.find\("\.fr-selected-cell"\)\.removeClass\("fr-selected-cell"\),',
            c,
        ) is not None
    )


# ── Fix 9: url bundles — a typed www./bare-domain link gets a real scheme ────
#
# The url plugin links a typed "www.example.com" or "example.org" as
# href="//www.example.com". A protocol-relative link has no page to take its
# scheme from in an email, so it opens nothing, and link tracking skips it.
# Use the link plugin's linkAutoPrefix (what the Insert Link popup adds),
# falling back to https://.
#
# Upstream pattern (variable names change each release):
#   .PLUGINS.url=function(V1){…/^((http|https|ftp|ftps|mailto|tel|sms|notes|data)\:)/i.test(V2)||(V2="//".concat(V2))
#
# Fixed pattern:
#   …||(V2=(V1.opts.linkAutoPrefix||"https://").concat(V2))

for url_bundle in (
    "js/plugins/url.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        url_bundle,
        f'{url_bundle}: give a typed www./bare-domain link a real scheme',
        re.compile(
            r'(\.PLUGINS\.url=function\(([\w$]+)\)\{[\s\S]*?'
            r'/\^\(\(http\|https\|ftp\|ftps\|mailto\|tel\|sms\|notes\|data\)\\:\)/i\.test\(([\w$]+)\)\|\|)'
            r'\(\3="//"\.concat\(\3\)\)'
        ),
        lambda m: f'{m[1]}({m[3]}=({m[2]}.opts.linkAutoPrefix||"https://").concat({m[3]}))',
        lambda c: re.search(r'\(([\w$]+)=\([\w$]+\.opts\.linkAutoPrefix\|\|"https://"\)\.concat\(\1\)\)', c)
        is not None
    )


# ── Fix 10: link bundles — Open Link opens a new tab ─────────────────────────
#
# The link popup's Open Link button set target="_self" on a link without a
# target and opened it there: the editor's own tab navigated away (losing the
# unsaved message), and target="_self" was written into the content. Always
# open a new tab, without changing the link.
#
# Upstream pattern (variable names change each release):
#   (V.target||(V.target="_self"),this.browser.msie||this.browser.edge
#     ?this.o_win.open(V.href,V.target):this.o_win.open(V.href,V.target,"noopener"))
#
# Fixed pattern:
#   (this.browser.msie||this.browser.edge
#     ?this.o_win.open(V.href,"_blank"):this.o_win.open(V.href,"_blank","noopener"))

for link_bundle in (
    "js/plugins/link.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        link_bundle,
        f'{link_bundle}: Open Link opens a new tab and leaves the target alone',
        re.compile(
            r'\(([\w$]+)\.target\|\|\(\1\.target="_self"\),this\.browser\.msie\|\|this\.browser\.edge'
            r'\?this\.o_win\.open\(\1\.href,\1\.target\):this\.o_win\.open\(\1\.href,\1\.target,"noopener"\)\)'
        ),
        lambda m: (
            f'(this.browser.msie||this.browser.edge?this.o_win.open({m[1]}.href,"_blank")'
            f':this.o_win.open({m[1]}.href,"_blank","noopener"))'
        ),
        lambda c: re.search(r'this\.o_win\.open\([\w$]+\.href,"_blank","noopener"\)', c) is not None
    )


# ── Fix 11: link bundles — caret after a link inserted at the caret ──────────
#
# A link inserted at a caret (URL and text typed in the popup) was left with
# its text selected, so the next key the user typed replaced the new link. When
# the insert started from a caret, put the caret after the link instead; a link
# made from selected text keeps that text selected, as before.
#
# Upstream pattern (variable names change each release):
#   else if(V1.format.remove("a"),V1.selection.isCollapsed())
#   …1==V2.length&&V1.$wp&&!V3&&(V4(V2[0]).prepend(V5.START_MARKER).append(V5.END_MARKER),V1.selection.restore())
#
# Fixed pattern (the collapsed branch records it on the editor, the end uses it):
#   else if(V1.format.remove("a"),V1._frLinkAtCaret=V1.selection.isCollapsed())
#   …1==V2.length&&V1.$wp&&!V3&&(V1._frLinkAtCaret?V4(V2[0]).after(V5.MARKERS)
#     :V4(V2[0]).prepend(V5.START_MARKER).append(V5.END_MARKER),V1.selection.restore()),V1._frLinkAtCaret=!1

for link_bundle in (
    "js/plugins/link.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        link_bundle,
        f'{link_bundle}: put the caret after a link inserted at the caret',
        re.compile(
            r'else if\(([\w$]+)\.format\.remove\("a"\),\1\.selection\.isCollapsed\(\)\)'
            r'([\s\S]*?)'
            r'1==([\w$]+)\.length&&\1\.\$wp&&!([\w$]+)&&\(([\w$]+)\(\3\[0\]\)\.prepend\(([\w$]+)\.START_MARKER\)'
            r'\.append\(\6\.END_MARKER\),\1\.selection\.restore\(\)\)'
        ),
        lambda m: (
            f'else if({m[1]}.format.remove("a"),{m[1]}._frLinkAtCaret={m[1]}.selection.isCollapsed())'
            f'{m[2]}'
            f'1=={m[3]}.length&&{m[1]}.$wp&&!{m[4]}&&({m[1]}._frLinkAtCaret?{m[5]}({m[3]}[0]).after({m[6]}.MARKERS)'
            f':{m[5]}({m[3]}[0]).prepend({m[6]}.START_MARKER).append({m[6]}.END_MARKER),'
            f'{m[1]}.selection.restore()),{m[1]}._frLinkAtCaret=!1'
        ),
        lambda c: '._frLinkAtCaret=' in c
    )


# ── Fix 12: core bundles — undo/redo save pending typing first ───────────────
#
# Typing saves its undo step only after a 500 ms timer. Undo pressed within
# that time stepped back past the typing, then the timer saved the reverted
# state and dropped the redo stack: the typing was gone for good. Flush the
# pending step (keys.forceUndo) before undoing or redoing, so undo removes just
# the typing and redo brings it back.
#
# Upstream pattern (variable names change each release):
#   run:function(){var V1;1<V2.undo_index&&
#   redo:function(){var V1;V2.undo_index<V2.undo_stack.length&&
#
# Fixed pattern:
#   run:function(){var V1;V2.keys&&V2.keys.forceUndo(),1<V2.undo_index&&
#   redo:function(){var V1;V2.keys&&V2.keys.forceUndo(),V2.undo_index<V2.undo_stack.length&&

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: undo saves pending typing first',
        re.compile(r'run:function\(\)\{var ([\w$]+);1<([\w$]+)\.undo_index&&'),
        lambda m: f'run:function(){{var {m[1]};{m[2]}.keys&&{m[2]}.keys.forceUndo(),1<{m[2]}.undo_index&&',
        lambda c: re.search(r'run:function\(\)\{var [\w$]+;([\w$]+)\.keys&&\1\.keys\.forceUndo\(\),', c)
        is not None
    )
    apply_fix(
        core_bundle,
        f'{core_bundle}: redo saves pending typing first',
        re.compile(r'redo:function\(\)\{var ([\w$]+);([\w$]+)\.undo_index<\2\.undo_stack\.length&&'),
        lambda m: (
            f'redo:function(){{var {m[1]};{m[2]}.keys&&{m[2]}.keys.forceUndo(),'
            f'{m[2]}.undo_index<{m[2]}.undo_stack.length&&'
        ),
        lambda c: re.search(r'redo:function\(\)\{var [\w$]+;([\w$]+)\.keys&&\1\.keys\.forceUndo\(\),', c)
        is not None
    )


# ── Fix 13: core bundles — Enter at the end of a formatted block keeps it ────
#
# With enter: ENTER_BR, html.defaultTag() is null, and Enter at the end of a
# block closed the block and put the new line after it as bare text: the font,
# size, alignment, line height or indent of a <p style> (pasted from Word, set
# with the toolbar) or <div style="text-align:center"> was gone from the next
# line, though Enter in the middle of the same block keeps it. For a P or DIV
# with formatting (style, align, dir), open the new line with a copy of the
# block, as the ENTER_P branch does. Unformatted blocks, Shift+Enter and the
# clearFormatOnEnterNewLine option behave as before.
#
# Upstream pattern (variable names change each release):
#   ("PRE"!=O.tagName||E.nextSibling||(T=!0),F.node.isBlock(O)&&!T||(N="<br/>"),""),S="",L="",C="";
#   (R=F.html.defaultTag())&&F.node.isBlock(O)&&(…),F.node.openTagString(R.get(0)));do{
#
# Fixed pattern (appended before do{):
#   ,!F.html.defaultTag()&&!T&&("P"===O.tagName||"DIV"===O.tagName)
#     &&(O.getAttribute("style")||O.getAttribute("align")||O.getAttribute("dir"))
#     &&!F.opts.clearFormatOnEnterNewLine
#     &&(L=F.node.openTagString($(O).clone().removeAttr("id").removeAttr("data-pasted").get(0)),
#        C=F.node.closeTagString(O));do{

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: Enter at the end of a formatted block keeps its formatting',
        re.compile(
            r'\("PRE"!=([\w$]+)\.tagName\|\|([\w$]+)\.nextSibling\|\|\(([\w$]+)=!0\),([\w$]+)\.node\.isBlock\(\1\)'
            r'&&!\3\|\|\([\w$]+="<br/>"\),""\),[\w$]+="",([\w$]+)="",([\w$]+)="";'
            r'\(([\w$]+)=\4\.html\.defaultTag\(\)\)&&\4\.node\.isBlock\(\1\)&&\(\5="<"\.concat\(\7,">"\),'
            r'\6="</"\.concat\(\7,">"\),\1\.tagName===\7\.toUpperCase\(\)\)&&\(\7=([\w$]+)\(\1\)\.clone\(\)'
            r'\.removeAttr\("id"\)\.removeAttr\("data-pasted"\),\4\.opts\.clearFormatOnEnterNewLine&&\7\.attr\("style"\)'
            r'&&\7\.removeAttr\("style"\),\5=\4\.node\.openTagString\(\7\.get\(0\)\)\)'
            r'(?=;do\{)'
        ),
        lambda m: (
            f'{m[0]},!{m[4]}.html.defaultTag()&&!{m[3]}&&("P"==={m[1]}.tagName||"DIV"==={m[1]}.tagName)'
            f'&&({m[1]}.getAttribute("style")||{m[1]}.getAttribute("align")||{m[1]}.getAttribute("dir"))'
            f'&&!{m[4]}.opts.clearFormatOnEnterNewLine'
            f'&&({m[5]}={m[4]}.node.openTagString({m[8]}({m[1]}).clone().removeAttr("id").removeAttr("data-pasted")'
            f'.get(0)),{m[6]}={m[4]}.node.closeTagString({m[1]}))'
        ),
        lambda c: re.search(
            r'!([\w$]+)\.html\.defaultTag\(\)&&![\w$]+&&\("P"===([\w$]+)\.tagName\|\|"DIV"===\2\.tagName\)', c
        ) is not None
    )


# ── Fix 14: colors bundles — Enter in the HEX field applies the colour ───────
#
# The colour popup's keyboard handler ran the focused element's command on
# Enter and stopped the event. The HEX input has no command, so Enter after
# typing a colour did nothing and the popup stayed open; only OK worked. On
# Enter in the input, run the popup's OK button instead.
#
# Upstream pattern (variable names change each release):
#   function(P,…){E.events.on("popup.tab",function(…){… K.KEYCODE.ENTER===T&&(E.button.exec(L),R=!1)
#
# Fixed pattern:
#   … K.KEYCODE.ENTER===T&&(E.button.exec(L.is("input")?P.find(".fr-submit"):L),R=!1)

for colors_bundle in (
    "js/plugins/colors.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        colors_bundle,
        f'{colors_bundle}: Enter in the HEX field applies the colour',
        re.compile(
            r'(function\(([\w$]+),[\w$]+\)\{([\w$]+)\.events\.on\("popup\.tab",function\([\w$]+\)\{[\s\S]*?)'
            r'([\w$]+)\.KEYCODE\.ENTER===([\w$]+)&&\(\3\.button\.exec\(([\w$]+)\),([\w$]+)=!1\)'
        ),
        lambda m: (
            f'{m[1]}{m[4]}.KEYCODE.ENTER==={m[5]}&&({m[3]}.button.exec({m[6]}.is("input")?{m[2]}.find(".fr-submit"):{m[6]}),'
            f'{m[7]}=!1)'
        ),
        lambda c: re.search(r'\.button\.exec\(([\w$]+)\.is\("input"\)\?[\w$]+\.find\("\.fr-submit"\):\1\)', c)
        is not None
    )


# ── Fix 15: lists bundles — the list type "Default" resets the markers ───────
#
# Choosing Default in the numbered or bulleted list options of a list that
# already had a type (Lower Alpha, Square, …) left list-style-type in place,
# so the list kept its old markers. Clear the property for Default.
#
# Upstream pattern (variable names change each release):
#   (A=$(R[N].parentNode),T&&"default"!==T)&&A.css("list-style-type",T)
#
# Fixed pattern:
#   (A=$(R[N].parentNode),T)&&A.css("list-style-type","default"===T?"":T)

for lists_bundle in (
    "js/plugins/lists.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        lists_bundle,
        f'{lists_bundle}: the list type Default resets the markers',
        re.compile(
            r'\(([\w$]+)=([\w$]+)\(([\w$]+)\[([\w$]+)\]\.parentNode\),([\w$]+)&&"default"!==\5\)'
            r'&&\1\.css\("list-style-type",\5\)'
        ),
        lambda m: (
            f'({m[1]}={m[2]}({m[3]}[{m[4]}].parentNode),{m[5]})'
            f'&&{m[1]}.css("list-style-type","default"==={m[5]}?"":{m[5]})'
        ),
        lambda c: re.search(r'\.css\("list-style-type","default"===([\w$]+)\?"":\1\)', c) is not None
    )


# ── Fix 16: core bundles — style inlining scores the selector that matched ───
#
# With useClasses: false, html.get copies the page's CSS rules into inline
# styles and lets the most specific rule win. The specificity was counted over
# the rule's whole selectorText: every part of a selector list ("td, th") was
# added up, and :where(...) counted although it adds none. So
# `.fr-view :where(table:not([border='0'])>*>tr)>td, … th` outscored
# `.fr-view table td.fr-highlighted`: a cell style or table style (Highlighted,
# Dashed Borders, a borderless template table) showed in the editor but the
# saved email got the default 1px #ddd border. Score only the part of the list
# that matches the element, without its :where(...) groups.
#
# Upstream pattern (variable names change each release):
#   L[E[I]]||(L[E[I]]={});for(var B=1e3*U+(N=R[H].selectorText,
#
# Fixed pattern:
#   L[E[I]]||(L[E[I]]={});for(var B=1e3*U+(N=function(s,e){…}(R[H].selectorText,E[I]),

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: style inlining scores the selector that matched',
        re.compile(
            r'([\w$]+)\[([\w$]+)\[([\w$]+)\]\]\|\|\(\1\[\2\[\3\]\]=\{\}\);'
            r'for\(var ([\w$]+)=1e3\*([\w$]+)\+\(([\w$]+)=([\w$]+)\[([\w$]+)\]\.selectorText,'
        ),
        lambda m: (
            f'{m[1]}[{m[2]}[{m[3]}]]||({m[1]}[{m[2]}[{m[3]}]]={{}});'
            f'for(var {m[4]}=1e3*{m[5]}+({m[6]}=function(s,e){{'
            r'for(var x=s.split(/,(?![^(]*\))/),i=0;i<x.length;i++){var q=x[i].trim();'
            r'try{if(e.matches(q.replace(/::/g,":")))'
            r'return q.replace(/:where\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)/g,"")}catch(z){}}'
            r'return s'
            f'}}({m[7]}[{m[8]}].selectorText,{m[2]}[{m[3]}]),'
        ),
        lambda c: 'return q.replace(/:where\\(' in c
    )


# ── Fix 17: image bundles — an image copied in a browser is uploaded ─────────
#
# Pasting an image copied from a web page (clipboard: the image file plus
# <img src="https://…">) should insert the file. The paste handler assigned
# FileReader.onload the value of an expression that ran at once: it inserted
# the page's remote src before the file was read, so the email linked to the
# other site's image (which can move or need a login) instead of an upload.
# Make onload a function that inserts the file's data URL; the pasted-image
# path then uploads it. The files manager plugin has the same code.
#
# Upstream pattern (variable names change each release):
#   R.onload=(A=T,(W=E.opts.imageDefaultWidth)…,void E.events.trigger("paste.after")),R.readAsDataURL(
#
# Fixed pattern:
#   R.onload=function(frEvent){A=frEvent.target.result,(W=E.opts.imageDefaultWidth)…,
#     void E.events.trigger("paste.after")},R.readAsDataURL(

for image_bundle in (
    "js/plugins/image.min.js",
    "js/plugins/files_manager.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        image_bundle,
        f'{image_bundle}: an image copied in a browser is uploaded from the clipboard',
        re.compile(
            r'([\w$]+)\.onload=\(([\w$]+)=[\w$]+,(\(([\w$]+)=([\w$]+)\.opts\.imageDefaultWidth\)[\s\S]{0,500}?'
            r',void \5\.events\.trigger\("paste\.after"\))\),\1\.readAsDataURL\('
        ),
        lambda m: (
            f'{m[1]}.onload=function(frEvent){{{m[2]}=frEvent.target.result,{m[3]}}},{m[1]}.readAsDataURL('
        ),
        lambda c: '.onload=function(frEvent){' in c,
        count=0,
    )


# ── Fix 18: image bundles — resizing keeps width/height attributes in step ───
#
# imageOutputSize writes an image's width/height attributes (what Outlook
# sizes it by) and, with Fix 1, only when they are missing. Resizing with the
# corner handles changed the CSS size only, so the saved image kept the old
# width attribute with the new height: distorted in Outlook. Drop the
# attributes when a resize ends, as Froala's size popup does, so the new size
# is written; and write whole pixels, since `height="180.984"` is not a valid
# HTML dimension.
#
# Upstream patterns (variable names change each release):
#   R=null,P.hide(),A(),B(),E.undo.saveStep(),E.events.trigger("image.resizeEnd",[I])
#   T&&L[N].setAttribute("width","".concat(T).replace(/px/,"")),H&&L[N].setAttribute("height","".concat(H).replace(/px/,""))
#
# Fixed patterns:
#   …,I.removeAttr("width").removeAttr("height"),E.undo.saveStep(),…
#   T&&L[N].setAttribute("width",frPixels(T)),H&&L[N].setAttribute("height",frPixels(H))
#     where frPixels rounds a px/number value and keeps a percentage

for image_bundle in (
    "js/plugins/image.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        image_bundle,
        f'{image_bundle}: a handle resize writes the new width/height attributes',
        re.compile(
            r'(([\w$]+)=null,([\w$]+)\.hide\(\),([\w$]+)\(\),([\w$]+)\(\),)([\w$]+)\.undo\.saveStep\(\),'
            r'\6\.events\.trigger\("image\.resizeEnd",\[([\w$]+)\]\)'
        ),
        lambda m: (
            f'{m[1]}{m[7]}.removeAttr("width").removeAttr("height"),{m[6]}.undo.saveStep(),'
            f'{m[6]}.events.trigger("image.resizeEnd",[{m[7]}])'
        ),
        lambda c: re.search(r'([\w$]+)\.removeAttr\("width"\)\.removeAttr\("height"\),[\w$]+\.undo\.saveStep\(\),'
                            r'[\w$]+\.events\.trigger\("image\.resizeEnd",\[\1\]\)', c) is not None
    )
    apply_fix(
        image_bundle,
        f'{image_bundle}: image size attributes are whole pixels',
        re.compile(
            r'([\w$]+)&&([\w$]+)\[([\w$]+)\]\.setAttribute\("width",""\.concat\(\1\)\.replace\(/px/,""\)\),'
            r'([\w$]+)&&\2\[\3\]\.setAttribute\("height",""\.concat\(\4\)\.replace\(/px/,""\)\)'
        ),
        lambda m: (
            f'{m[1]}&&{m[2]}[{m[3]}].setAttribute("width",function(v){{v="".concat(v).replace(/px$/,"");'
            r'return/^\d+(\.\d+)?$/.test(v)?String(Math.round(parseFloat(v))):v'
            f'}}({m[1]})),'
            f'{m[4]}&&{m[2]}[{m[3]}].setAttribute("height",function(v){{v="".concat(v).replace(/px$/,"");'
            r'return/^\d+(\.\d+)?$/.test(v)?String(Math.round(parseFloat(v))):v'
            f'}}({m[4]}))'
        ),
        lambda c: 'String(Math.round(parseFloat(v))):v' in c,
        count=0,
    )


# ── Fix 19: table bundles — Table properties keeps an unaligned table put ────
#
# The Table properties popup read a table with no alignment class and no
# margin:auto as aligned "left", so saving any property (a background, a
# width) added fr-table-left-align, which is float:left: the saved email's
# table floated and the next paragraph moved up beside it. Read such a table
# as having no alignment, so Save leaves it where it was.
#
# Upstream pattern (variable names change each release):
#   …:S&&/\bmargin\s*:\s*auto\b/i.test(F)?"center":"left"
#
# Fixed pattern:
#   …:S&&/\bmargin\s*:\s*auto\b/i.test(F)?"center":""

for table_bundle in (
    "js/plugins/table.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        table_bundle,
        f'{table_bundle}: Table properties keeps an unaligned table put',
        re.compile(r'(\?"rightNoWrap":([\w$]+)&&/\\bmargin\\s\*:\\s\*auto\\b/i\.test\(([\w$]+)\)\?"center":)"left"'),
        lambda m: f'{m[1]}""',
        lambda c: re.search(r'/\\bmargin\\s\*:\\s\*auto\\b/i\.test\([\w$]+\)\?"center":""', c) is not None
    )
    # The popup then shows no alignment as active (it looked up ".fr-table--align" and threw).
    apply_fix(
        table_bundle,
        f'{table_bundle}: Table properties shows no alignment as active for an unaligned table',
        re.compile(
            r':\(([\w$]+)=([\w$]+)\.find\("\.fr-table-"\.concat\(([\w$]+),"-align"\)\)\.get\(0\)\)\.innerHTML='
            r'([\w$]+)\.icon\.create\(""\.concat\(\3,"TableAlignActive"\)\),\1\.focus\(\),'
        ),
        lambda m: (
            f':{m[3]}&&(({m[1]}={m[2]}.find(".fr-table-".concat({m[3]},"-align")).get(0)).innerHTML='
            f'{m[4]}.icon.create("".concat({m[3]},"TableAlignActive"))),{m[1]}&&{m[1]}.focus(),'
        ),
        lambda c: re.search(r'\),([\w$]+)&&\1\.focus\(\),[\w$]+\.data\("tableAlign"', c) is not None
    )


# ── Fix 20: core bundles — style inlining keeps properties the browser lacks ─
#
# With useClasses: false, html.get puts an element's own inline declarations
# back through the CSSOM after inlining the page's rules. A property the
# browser doesn't implement (mso-padding-alt, mso-line-height-rule, …) is
# silently dropped there, so the saved HTML lost Outlook-only styles, e.g. the
# padding of an email button in Outlook. Write such declarations back into the
# style attribute after the CSSOM ones.
#
# Upstream pattern (variable names change each release):
#   for(var T,S,A=E[F].getAttribute("fr-original-style").split(";"),M=0;M<A.length;M++)
#     0<A[M].indexOf(":")&&(S=(T=A[M].split(":"))[0],T.splice(0,1),E[F].style[S.trim()]=T.join(":").trim())
#
# Fixed pattern:
#   {for(var T,S,A=…,frKeep=[],M=0;M<A.length;M++)0<A[M].indexOf(":")&&(S=…,T.splice(0,1),
#     S.trim() in E[F].style?E[F].style[S.trim()]=T.join(":").trim():frKeep.push(…));
#   frKeep.length&&E[F].setAttribute("style",…+frKeep.join("; "))}

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: style inlining keeps properties the browser lacks',
        re.compile(
            r'for\(var ([\w$]+),([\w$]+),([\w$]+)=([\w$]+)\[([\w$]+)\]\.getAttribute\("fr-original-style"\)\.split\(";"\),'
            r'([\w$]+)=0;\6<\3\.length;\6\+\+\)0<\3\[\6\]\.indexOf\(":"\)&&\(\2=\(\1=\3\[\6\]\.split\(":"\)\)\[0\],'
            r'\1\.splice\(0,1\),\4\[\5\]\.style\[\2\.trim\(\)\]=\1\.join\(":"\)\.trim\(\)\)'
        ),
        lambda m: (
            f'{{for(var {m[1]},{m[2]},{m[3]}={m[4]}[{m[5]}].getAttribute("fr-original-style").split(";"),frKeep=[],'
            f'{m[6]}=0;{m[6]}<{m[3]}.length;{m[6]}++)0<{m[3]}[{m[6]}].indexOf(":")&&'
            f'({m[2]}=({m[1]}={m[3]}[{m[6]}].split(":"))[0],{m[1]}.splice(0,1),'
            f'{m[2]}.trim() in {m[4]}[{m[5]}].style?{m[4]}[{m[5]}].style[{m[2]}.trim()]={m[1]}.join(":").trim()'
            f':frKeep.push({m[2]}.trim()+": "+{m[1]}.join(":").trim()));'
            f'frKeep.length&&{m[4]}[{m[5]}].setAttribute("style",'
            f'(({m[4]}[{m[5]}].getAttribute("style")||"").replace(/;?\\s*$/,"")+"; "+frKeep.join("; "))'
            f'.replace(/^;\\s*/,""))}}'
        ),
        lambda c: 'frKeep.push(' in c
    )


# ── Fix 21: image bundles — a resize starts from the image's own width ───────
#
# A resize (a handle drag, or Cmd/Ctrl+= / Cmd/Ctrl+- on a selected image, which
# simulates one) started from E.width(), the image's box including the
# padding: 0 1px Froala gives images in the editor, and wrote it back as the CSS
# width. Every resize began 2px wider: Cmd+- grew the image by 1px and Cmd+=
# by 3px. Start from the computed CSS width, which writing back keeps as is.
#
# Upstream patterns (variable names change each release):
#   .data("start-width",I.width())   …   .data("start-height",I.height())…;W=I.width();
#
# Fixed patterns:
#   .data("start-width",parseFloat(getComputedStyle(I.get(0)).width)||I.width())
#   …;W=parseFloat(getComputedStyle(I.get(0)).width)||I.width();

for image_bundle in (
    "js/plugins/image.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        image_bundle,
        f'{image_bundle}: a resize starts from the image\'s own width',
        re.compile(r'\.data\("start-width",([\w$]+)\.width\(\)\)'),
        lambda m: f'.data("start-width",parseFloat(getComputedStyle({m[1]}.get(0)).width)||{m[1]}.width())',
        lambda c: '.data("start-width",parseFloat(getComputedStyle(' in c,
        count=0,
    )
    apply_fix(
        image_bundle,
        f'{image_bundle}: a resize writes back the image\'s own width',
        re.compile(
            r'(\.data\("start-height",([\w$]+)\.height\(\)\)(?:,[\w$]+\.events\.trigger\("image\.resizeStart",\[\2\]\))?;'
            r'([\w$]+)=)\2\.width\(\);'
        ),
        lambda m: f'{m[1]}parseFloat(getComputedStyle({m[2]}.get(0)).width)||{m[2]}.width();',
        lambda c: re.search(r'\.data\("start-height",[\w$]+\.height\(\)\)[^;]*;[\w$]+=parseFloat\(getComputedStyle\(', c)
        is not None,
        count=0,
    )


# ── Fix 22: line_breaker bundles — the "+" shows between two touching tables ──
#
# Between two elements the line breaker hid itself when the second one started
# above the first one's bottom, taken as offset().top + height(). height() is
# offsetHeight, rounded (51.78 -> 52), while offset() keeps the fraction, so
# two tables that touch looked as if they overlapped by a fraction of a pixel
# and the "+" never showed. Allow a 1px overlap.
#
# Upstream pattern (variable names change each release):
#   var r=e.parent(),o=e.offset().top+e.height(),i=t.offset().top;if(i<o)return;
#
# Fixed pattern:
#   var r=e.parent(),o=e.offset().top+e.height(),i=t.offset().top;if(i<o-1)return;

for line_breaker_bundle in (
    "js/plugins/line_breaker.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        line_breaker_bundle,
        f'{line_breaker_bundle}: the "+" shows between two touching tables',
        re.compile(
            r'(([\w$]+)=([\w$]+)\.offset\(\)\.top\+\3\.height\(\),([\w$]+)=[\w$]+\.offset\(\)\.top;'
            r'if\(\4<\2)\)return;'
        ),
        lambda m: f'{m[1]}-1)return;',
        lambda c: re.search(r'\.offset\(\)\.top\+[\w$]+\.height\(\),[\w$]+=[\w$]+\.offset\(\)\.top;if\([\w$]+<[\w$]+-1\)return;', c)
        is not None
    )


# ── Fix 23: line_breaker bundles — the "+" below an inline element adds a line ─
#
# Clicking the "+" below an element inserted MARKERS + <br> after it. After an
# inline element (an image in a paragraph) the caret then sat on the element's
# own line, so the typed text went beside the image. After an inline-level
# element insert <br> + MARKERS + <br>, so the caret starts a new line. Block
# elements (tables, block images) are unchanged.
#
# Upstream pattern (variable names change each release):
#   :r.after("".concat(b.MARKERS,"<br>")),e.selection.restore(),s.undo.saveStep(),s.toolbar.enable()}
#
# Fixed pattern:
#   :r.after((/^inline/.test(getComputedStyle(r.get(0)).display)?"<br>":"")+"".concat(b.MARKERS,"<br>")),…

for line_breaker_bundle in (
    "js/plugins/line_breaker.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        line_breaker_bundle,
        f'{line_breaker_bundle}: the "+" below an inline element adds a line under it',
        re.compile(
            r':([\w$]+)\.after\(""\.concat\(([\w$]+)\.MARKERS,"<br>"\)\)'
            r'(,[\w$]+\.selection\.restore\(\),([\w$]+)\.undo\.saveStep\(\),\4\.toolbar\.enable\(\)\})'
        ),
        lambda m: (
            f':{m[1]}.after((/^inline/.test(getComputedStyle({m[1]}.get(0)).display)?"<br>":"")'
            f'+"".concat({m[2]}.MARKERS,"<br>")){m[3]}'
        ),
        lambda c: '.after((/^inline/.test(getComputedStyle(' in c
    )


# ── Fix 24: table bundles — the table hover outline is never saved ────────────
#
# Core dragSelectControls gives the table under the mouse the class
# fr-selection-handle-hover (a yellow outline). It is taken off for undo
# snapshots and on the next mouse move or key, but html.beforeGet only took off
# fr-selected-cell and fr-selection-handle-selected. Clicking a "+" insert
# helper stops that mouse move, so with useClasses: false html.get inlined the
# class as outline: … 2px into the saved table. Take the hover class off in
# html.beforeGet and put it back in html.afterGet, as -selected is.
#
# Upstream pattern (variable names change each release):
#   (t=R.$el.find("table.fr-selection-handle-selected"))&&t.length&&d(t,"fr-selection-handle-selected")}),
#   R.events.on("html.afterGet",function(){…;a=[],t&&t.length&&t.addClass("fr-selection-handle-selected")
#
# Fixed pattern:
#   …&&d(t,"fr-selection-handle-selected"),(R.frHoverHandles=R.$el.find(".fr-selection-handle-hover")).length
#     &&d(R.frHoverHandles,"fr-selection-handle-hover")}),R.events.on("html.afterGet",function(){…
#     t&&t.length&&t.addClass("fr-selection-handle-selected"),R.frHoverHandles&&R.frHoverHandles.length
#     &&R.frHoverHandles.addClass("fr-selection-handle-hover"),R.frHoverHandles=null

for table_bundle in (
    "js/plugins/table.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        table_bundle,
        f'{table_bundle}: the table hover outline is never saved',
        re.compile(
            r'(\(([\w$]+)=([\w$]+)\.\$el\.find\("table\.fr-selection-handle-selected"\)\)&&\2\.length&&'
            r'([\w$]+)\(\2,"fr-selection-handle-selected"\))'
            r'(\}\),\3\.events\.on\("html\.afterGet",function\(\)\{[^{}]*?'
            r'\2&&\2\.length&&\2\.addClass\("fr-selection-handle-selected"\))'
        ),
        lambda m: (
            f'{m[1]},({m[3]}.frHoverHandles={m[3]}.$el.find(".fr-selection-handle-hover")).length&&'
            f'{m[4]}({m[3]}.frHoverHandles,"fr-selection-handle-hover"){m[5]},'
            f'{m[3]}.frHoverHandles&&{m[3]}.frHoverHandles.length&&'
            f'{m[3]}.frHoverHandles.addClass("fr-selection-handle-hover"),{m[3]}.frHoverHandles=null'
        ),
        lambda c: '.frHoverHandles=' in c
    )


# ── Fix 25: table bundles — Back/Escape on the insert grid keeps the caret ────
#
# The Insert table grid takes the focus (its first cell) and may keep the
# selection as markers. Clicking its toolbar button again restores the
# selection and focuses the editor, but Back (and Escape, which clicks Back)
# only hid the popup: the focus stayed on the page, so typing went nowhere.
# Restore the selection the way the insertTable toggle does and focus the
# editor again.
#
# Upstream pattern (variable names change each release):
#   :0<P().length?u():(R.popups.hide("table.insert"),R.toolbar.showInline())
#
# Fixed pattern:
#   :0<P().length?u():(R.$el.find(".fr-marker").length&&(R.events.disableBlur(),R.selection.restore()),
#     R.popups.hide("table.insert"),R.toolbar.showInline(),R.events.focus())

for table_bundle in (
    "js/plugins/table.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        table_bundle,
        f'{table_bundle}: Back/Escape on the insert grid keeps the caret',
        re.compile(
            r'(:0<[\w$]+\(\)\.length\?[\w$]+\(\):\()(([\w$]+)\.popups\.hide\("table\.insert"\),\3\.toolbar\.showInline\(\)\))'
        ),
        lambda m: (
            f'{m[1]}{m[3]}.$el.find(".fr-marker").length&&({m[3]}.events.disableBlur(),{m[3]}.selection.restore()),'
            f'{m[2][:-1]},{m[3]}.events.focus())'
        ),
        lambda c: re.search(
            r'\.selection\.restore\(\)\),[\w$]+\.popups\.hide\("table\.insert"\),[\w$]+\.toolbar\.showInline\(\),'
            r'[\w$]+\.events\.focus\(\)\)', c
        ) is not None
    )


# ── Fix 26: image bundles — Escape on a selected image stays in the editor ────
#
# Escape on a selected image leaves the image (caret after it) and prevents
# the default, but let the event bubble on: a dialog around the editor (PA's
# composer, a MUI Dialog) took the same Escape as "close". Stop it there.
#
# Upstream pattern (variable names change each release; the files_manager copy
# of this code, which has no ?null: guard, is left alone):
#   …?null:E)||t!=xe.KEYCODE.BACKSPACE&&t!=xe.KEYCODE.DELETE?E&&t==xe.KEYCODE.ESC?(a=E,D(!0),S.selection.setAfter(a.get(0)),S.selection.restore(),e.preventDefault(),!1)
#
# Fixed pattern:
#   …,S.selection.restore(),e.preventDefault(),e.stopPropagation(),!1)

for image_bundle in (
    "js/plugins/image.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        image_bundle,
        f'{image_bundle}: Escape on a selected image stays in the editor',
        re.compile(
            r'(!\(([\w$]+)=[\w$]+\?null:\2\)\|\|[\w$]+!=[\w$]+\.KEYCODE\.BACKSPACE&&[\w$]+!=[\w$]+\.KEYCODE\.DELETE\?'
            r'\2&&[\w$]+==[\w$]+\.KEYCODE\.ESC\?\(([\w$]+)=\2,[\w$]+\(!0\),([\w$]+)\.selection\.setAfter\(\3\.get\(0\)\),'
            r'\4\.selection\.restore\(\),([\w$]+)\.preventDefault\(\),)!1\)'
        ),
        lambda m: f'{m[1]}{m[5]}.stopPropagation(),!1)',
        lambda c: re.search(
            r'\?null:[\w$]+\)\|\|[\w$]+!=[\w$]+\.KEYCODE\.BACKSPACE&&[\w$]+!=[\w$]+\.KEYCODE\.DELETE\?'
            r'[\w$]+&&[\w$]+==[\w$]+\.KEYCODE\.ESC\?\([\w$]+=[\w$]+,[\w$]+\(!0\),[\w$]+\.selection\.setAfter\([\w$]+\.get\(0\)\),'
            r'[\w$]+\.selection\.restore\(\),[\w$]+\.preventDefault\(\),[\w$]+\.stopPropagation\(\),!1\)', c
        ) is not None
    )


# ── Fix 27: link bundles — an empty URL keeps the link popup open ─────────────
#
# link.insert() restored the selection and hid the popup before it checked the
# URL, then marked the URL field of the popup it had already closed: Insert
# with no URL just closed the popup. Leave the popup (and the saved selection)
# alone when the URL is empty, so the check marks the field of the open popup.
#
# Upstream pattern (variable names change each release):
#   r=(i||"A"==b.el.tagName?"A"==b.el.tagName&&b.$el.focus():(b.selection.restore(),b.popups.hide("link.insert")),e)
#
# Fixed pattern:
#   …:(e&&e!==b.opts.linkAutoPrefix?(b.selection.restore(),b.popups.hide("link.insert")):0),e)

for link_bundle in (
    "js/plugins/link.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        link_bundle,
        f'{link_bundle}: an empty URL keeps the link popup open',
        re.compile(
            r'(\([\w$]+\|\|"A"==([\w$]+)\.el\.tagName\?"A"==\2\.el\.tagName&&\2\.\$el\.focus\(\):)'
            r'(\(\2\.selection\.restore\(\),\2\.popups\.hide\("link\.insert"\)\)),([\w$]+)\)'
        ),
        lambda m: f'{m[1]}({m[4]}&&{m[4]}!=={m[2]}.opts.linkAutoPrefix?{m[3]}:0),{m[4]})',
        lambda c: re.search(
            r'\$el\.focus\(\):\(([\w$]+)&&\1!==[\w$]+\.opts\.linkAutoPrefix\?\([\w$]+\.selection\.restore\(\),', c
        ) is not None
    )


# ── Fix 28: emoticons bundles — a flag is saved without a zero-width joiner ───
#
# The emoticons plugin builds each emoji from its code by joining the parts
# with &zwj;. A country flag is two regional indicator letters with nothing
# between them, so the flag was saved as letter, ZWJ, letter, which mail
# clients that don't special-case it show as two letters. Join a regional
# indicator (U+1F1E6–U+1F1FF) without the ZWJ; real ZWJ sequences keep it.
#
# Upstream pattern (variable names change each release):
#   reduce(function(e,c){return(e?"".concat(e,"&zwj;&#x"):"&#x").concat(c.toLowerCase(),";")},"")
#
# Fixed pattern:
#   reduce(function(e,c){return(e?"".concat(e,/^1f1[ef]/i.test(c)?"&#x":"&zwj;&#x"):"&#x").concat(…)},"")

for emoticons_bundle in (
    "js/plugins/emoticons.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        emoticons_bundle,
        f'{emoticons_bundle}: a flag is saved without a zero-width joiner',
        re.compile(
            r'reduce\(function\(([\w$]+),([\w$]+)\)\{return\(\1\?""\.concat\(\1,"&zwj;&#x"\):"&#x"\)'
            r'(\.concat\(\2\.toLowerCase\(\),";"\)\})'
        ),
        lambda m: (
            f'reduce(function({m[1]},{m[2]}){{return({m[1]}?"".concat({m[1]},/^1f1[ef]/i.test({m[2]})?"&#x":"&zwj;&#x")'
            f':"&#x"){m[3]}'
        ),
        lambda c: '/^1f1[ef]/i.test(' in c
    )


# ── Fix 29: word_paste bundles — a paragraph border survives the unwrap ───────
#
# Word and Outlook write a paragraph border as a wrapping div
# (mso-element:para-border-div) that carries the border and padding, with
# border:none;padding:0 on the p inside. The clean-up unwraps a lone p from its
# div and so dropped the border: an Outlook reply lost the grey line above its
# "From:" header. Move the div's border and padding onto the p first: the
# sides the div draws replace the p's own border (border:none), and the div's
# padding replaces the p's.
#
# Upstream pattern (variable names change each release):
#   return t&&"P"===t.tagName&&"DIV"===t.parentNode.tagName&&1==t.parentNode.children.length&&I(t).unwrap(),!0
#
# Fixed pattern:
#   …&&1==t.parentNode.children.length&&(function(frP,frDiv){…border-<side> of each drawn side, padding-<side>…}
#     (t,t.parentNode.style),I(t).unwrap()),!0

for word_paste_bundle in (
    "js/plugins/word_paste.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        word_paste_bundle,
        f'{word_paste_bundle}: a paragraph border survives the unwrap',
        re.compile(
            r'(([\w$]+)&&"P"===\2\.tagName&&"DIV"===\2\.parentNode\.tagName&&1==\2\.parentNode\.children\.length&&)'
            r'([\w$]+\(\2\)\.unwrap\(\)),!0'
        ),
        lambda m: (
            f'{m[1]}((function(frP,frDiv){{var frSides=["top","right","bottom","left"],'
            f'frDrawn=frSides.filter(function(frSide){{var frStyle=frDiv.getPropertyValue("border-"+frSide+"-style");'
            f'return frStyle&&"none"!==frStyle&&"hidden"!==frStyle}});'
            f'frDrawn.length&&frP.style.removeProperty("border"),'
            f'frDrawn.forEach(function(frSide){{frP.style.setProperty("border-"+frSide,frDiv.getPropertyValue("border-"+frSide))}}),'
            f'frSides.forEach(function(frSide){{frDiv.getPropertyValue("padding-"+frSide)&&'
            f'frP.style.setProperty("padding-"+frSide,frDiv.getPropertyValue("padding-"+frSide))}})}})'
            f'({m[2]},{m[2]}.parentNode.style),{m[3]}),!0'
        ),
        lambda c: 'frDrawn.length&&frP.style.removeProperty("border")' in c
    )


# ── Fix 30: core + AI bundles — the AI popup stays on screen ───────────────
#
# AI Assist keeps its popup in the editor box, its bottom on the bottom of the
# editing area (or of the window). position.at() flips a popup above its anchor
# when it doesn't fit below, adding the popup parent's page offset to the top it
# was given; AI Assist's top already holds that offset, so the check counted the
# box's offset twice: in a dialog, or once the editor sat ~400px down a page
# with a short body, the popup jumped above the editor when the answer came and
# the dialog clipped it, hiding Insert and Close. Leave a popup in the editor
# box where its plugin put it (only AI Assist positions one there), and have AI
# Assist keep its popup's top, and the X on its corner, below the top of the
# window and of any scrolling or clipping box the editor is in.
#
# Upstream patterns (variable names change each release):
#   core: !g.helpers.isMobile()&&g.$tb&&r.parent().length&&r.parent().get(0)!==g.$tb.get(0)&&(o=r.parent().offset().top,…
#   AI:   T.opts.toolbarBottom&&(r=n<0?Math.abs(n)+i+i:n+i),r+=T.$box.offset().top,
#
# Fixed patterns:
#   core: …&&r.parent().get(0)!==g.$tb.get(0)&&!(g.$box&&r.parent().get(0)===g.$box.get(0))&&(o=r.parent().offset().top,…
#   AI:   T.opts.toolbarBottom&&(…),r=Math.max(r,function(e){for(var t=0;e&&1===e.nodeType&&e!==e.ownerDocument.body;
#           e=e.parentNode)/auto|scroll|hidden|clip|overlay/.test(getComputedStyle(e).overflowY)&&(t=Math.max(t,
#           e.getBoundingClientRect().top));return t}(T.$box[0].parentNode)+15),r+=T.$box.offset().top,

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: a popup in the editor box is not flipped above it',
        re.compile(
            r'(!([\w$]+)\.helpers\.isMobile\(\)&&\2\.\$tb&&([\w$]+)\.parent\(\)\.length&&'
            r'\3\.parent\(\)\.get\(0\)!==\2\.\$tb\.get\(0\))&&\(([\w$]+)=\3\.parent\(\)\.offset\(\)\.top,'
        ),
        lambda m: f'{m[1]}&&!({m[2]}.$box&&{m[3]}.parent().get(0)==={m[2]}.$box.get(0))&&({m[4]}={m[3]}.parent().offset().top,',
        lambda c: re.search(r'&&!\(([\w$]+)\.\$box&&[\w$]+\.parent\(\)\.get\(0\)===\1\.\$box\.get\(0\)\)&&\(', c) is not None
    )

for ai_bundle in (
    "js/plugins/ai_assist.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        ai_bundle,
        f'{ai_bundle}: the AI popup keeps its top inside the window and its scroll box',
        re.compile(
            r'(([\w$]+)\.opts\.toolbarBottom&&\(([\w$]+)=[\w$]+<0\?Math\.abs\([\w$]+\)\+[\w$]+\+[\w$]+:[\w$]+\+[\w$]+\),)'
            r'(\3\+=\2\.\$box\.offset\(\)\.top,)'
        ),
        lambda m: (
            f'{m[1]}{m[3]}=Math.max({m[3]},function(e){{for(var t=0;e&&1===e.nodeType&&e!==e.ownerDocument.body;'
            f'e=e.parentNode)/auto|scroll|hidden|clip|overlay/.test(getComputedStyle(e).overflowY)&&'
            f'(t=Math.max(t,e.getBoundingClientRect().top));return t}}({m[2]}.$box[0].parentNode)+15),{m[4]}'
        ),
        lambda c: '/auto|scroll|hidden|clip|overlay/.test(getComputedStyle(e).overflowY)' in c
    )


# ── Fix 31: AI bundles — Esc closes the AI popup ────────────────────────────
#
# The AI Assist popup is marked fr-do-not-hide and its X has tabindex=-1, so
# Esc (handled by the popup's keyboard navigation, which only hides popups that
# allow it) left it open and a keyboard user couldn't close it. Esc pressed in
# the popup now closes it as the X does, and goes no further, so a dialog the
# editor sits in stays open.
#
# Upstream pattern (variable names change each release):
#   f.on("keydown",O),l.bindPopup(f),T.events.on("popups.hide.aiAssist.promptPopup",B)
#
# Fixed pattern:
#   …,T.events.on("popups.hide.aiAssist.promptPopup",B),T.events.on("popup.tab",function(e){
#     if("Escape"===e.key&&f&&f.isVisible()&&f.get(0).contains(e.target))return e.preventDefault(),
#     e.stopPropagation(),f.removeClass("fr-do-not-hide"),T.popups.hide("aiAssist.promptPopup"),!1})

for ai_bundle in (
    "js/plugins/ai_assist.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        ai_bundle,
        f'{ai_bundle}: Esc closes the AI popup',
        re.compile(
            r'(\.on\("keydown",[\w$]+\),[\w$]+\.bindPopup\(([\w$]+)\),'
            r'([\w$]+)\.events\.on\("popups\.hide\.aiAssist\.promptPopup",[\w$]+\))'
        ),
        lambda m: (
            f'{m[1]},{m[3]}.events.on("popup.tab",function(e){{if("Escape"===e.key&&{m[2]}&&{m[2]}.isVisible()'
            f'&&{m[2]}.get(0).contains(e.target))return e.preventDefault(),e.stopPropagation(),'
            f'{m[2]}.removeClass("fr-do-not-hide"),{m[3]}.popups.hide("aiAssist.promptPopup"),!1}})'
        ),
        lambda c: '.events.on("popup.tab",function(e){if("Escape"===e.key&&' in c
    )


# ── Fix 32: core bundles — an expanded "more" row is as tall as its buttons ─
#
# The toolbar estimated an expanded "more" row's line count from its buttons'
# total width. The buttons wrap within the row's content box (after the
# padding-left that lines them up under their group button), so the estimate
# came up a line short at some widths (386–404px editors): the row, overflow:
# hidden, cut off its last line, AI Assist included. Count the lines the
# buttons actually wrap to.
#
# Upstream pattern (variable names change each release):
#   T.$tb.outerWidth()<n&&(i=Math.floor(n/T.$tb.outerWidth()),n+=i*(n/s[0].childElementCount),
#     i=Math.ceil(n/T.$tb.outerWidth()),a=(T.helpers.getPX(a.css("height"))+e+t)*i,s.css("height",a))
#
# Fixed pattern:
#   (a=T.helpers.getPX(a.css("height"))+e+t,n=1/0,e=-1/0,i.each(function(){var frR=this.getBoundingClientRect();
#     frR.height&&(n=Math.min(n,frR.bottom),e=Math.max(e,frR.bottom))}),i=e<n?1:1+Math.round((e-n)/a),
#     s.css("height",1<i?a*i:""))

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: an expanded "more" row is as tall as its buttons',
        re.compile(
            r'([\w$]+)\.\$tb\.outerWidth\(\)<([\w$]+)&&\(([\w$]+)=Math\.floor\(\2/\1\.\$tb\.outerWidth\(\)\),'
            r'\2\+=\3\*\(\2/([\w$]+)\[0\]\.childElementCount\),\3=Math\.ceil\(\2/\1\.\$tb\.outerWidth\(\)\),'
            r'([\w$]+)=\(\1\.helpers\.getPX\(\5\.css\("height"\)\)\+([\w$]+)\+([\w$]+)\)\*\3,\4\.css\("height",\5\)\)'
        ),
        lambda m: (
            f'({m[5]}={m[1]}.helpers.getPX({m[5]}.css("height"))+{m[6]}+{m[7]},{m[2]}=1/0,{m[6]}=-1/0,'
            f'{m[3]}.each(function(){{var frR=this.getBoundingClientRect();frR.height&&'
            f'({m[2]}=Math.min({m[2]},frR.bottom),{m[6]}=Math.max({m[6]},frR.bottom))}}),'
            f'{m[3]}={m[6]}<{m[2]}?1:1+Math.round(({m[6]}-{m[2]})/{m[5]}),'
            f'{m[4]}.css("height",1<{m[3]}?{m[5]}*{m[3]}:""))'
        ),
        lambda c: 'var frR=this.getBoundingClientRect();' in c
    )


# ── Fix 33: core bundles — a shortcut runs a plugin command with the editor ──
#
# When no toolbar button takes a shortcut's command, the shortcuts module ran
# the command's callback unbound and without arguments, so a plugin command
# (AI Assist's Cmd/Ctrl+Shift+I in an editor without that button) threw a
# TypeError. Call it as the command module does: this = the editor, then the
# command name and the shortcut's value, if it has one.
#
# Upstream pattern (variable names change each release):
#   r.events.trigger("shortcut",[e,n,o]) … "keydown"===e.type&&((r.commands[n]||Z.COMMANDS[n].callback)(),i=!0)
#
# Fixed pattern:
#   … "keydown"===e.type&&(r.commands[n]?r.commands[n]():Z.COMMANDS[n].callback.apply(r,null==o?[n]:[n,o]),i=!0)

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: a shortcut runs a plugin command with the editor',
        re.compile(
            r'(\.events\.trigger\("shortcut",\[[\w$]+,[\w$]+,([\w$]+)\]\).{0,200}?"keydown"===[\w$]+\.type&&)'
            r'\(\(([\w$]+)\.commands\[([\w$]+)\]\|\|([\w$]+)\.COMMANDS\[\4\]\.callback\)\(\),'
        ),
        lambda m: (
            f'{m[1]}({m[3]}.commands[{m[4]}]?{m[3]}.commands[{m[4]}]():'
            f'{m[5]}.COMMANDS[{m[4]}].callback.apply({m[3]},null=={m[2]}?[{m[4]}]:[{m[4]},{m[2]}]),'
        ),
        lambda c: re.search(r'\.COMMANDS\[[\w$]+\]\.callback\.apply\([\w$]+,null==[\w$]+\?\[', c) is not None
    )


# ── Fix 34: core bundles — a WebKit copy is not taken for Word ──────────────
#
# The paste module's Word check matched caret-color: rgb(0, 0, 0), which Safari,
# Apple Mail and Notes write on every copy, so pasting an Apple Mail reply asked
# about Microsoft Word and ran the Word clean-up. Office content still carries
# its own markers (mso-, class=Mso, w:WordDocument, OneNote.File, …).
#
# Upstream pattern:
#   …|OneNote\.File|caret-color:\s*rgb\(0,\s*0,\s*0\)|OutlineElement|…
#
# Fixed pattern:
#   …|OneNote\.File|OutlineElement|…

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: a WebKit copy is not taken for Word',
        re.compile(r'(\|OneNote\\\.File)\|caret-color:\\s\*rgb\\\(0,\\s\*0,\\s\*0\\\)(\|OutlineElement\|)'),
        lambda m: f'{m[1]}{m[2]}',
        lambda c: r'|OneNote\.File|OutlineElement|' in c
    )


# ── Fix 35: core bundles — selection actions leave the toolbar its focus ────
#
# 150 ms after a key-up Froala 5 shows the floating selection actions (Improve
# Writing) over a selection, and popups.show() focuses the editor again: Alt+F10
# with words selected moved the focus to the toolbar and straight back. Only
# open the selection actions while the editor has the focus; an open one is
# still moved with the selection.
#
# Upstream pattern (variable names change each release):
#   t.hasClass("fr-active")?(…position.at(…)):(s.popups.show("selectionActions.buttons",e.left,e.top),…)
#
# Fixed pattern:
#   t.hasClass("fr-active")?(…):s.core.hasFocus()&&(s.popups.show("selectionActions.buttons",e.left,e.top),…)

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: selection actions leave the toolbar its focus',
        re.compile(r'\)\):\(([\w$]+)\.popups\.show\("selectionActions\.buttons",'),
        lambda m: f')):{m[1]}.core.hasFocus()&&({m[1]}.popups.show("selectionActions.buttons",',
        lambda c: re.search(r'\.core\.hasFocus\(\)&&\([\w$]+\.popups\.show\("selectionActions\.buttons",', c) is not None
    )


# ── Fix 36: core bundles — undo after typing stops saving a step every time ─
#
# keys.forceUndo() (run before every undo and redo) saves the typing still
# waiting for its undo step and cancels that timer, but kept the timer's handle,
# so from the first keystroke on every undo saved a step first. When saving
# changes the snapshot (an html.get hook that re-serialises the DOM), that
# dropped the redo stack and undo kept restoring the same state. Clear the handle.
#
# Upstream pattern (variable names change each release):
#   forceUndo:function(){n&&(clearTimeout(n),g.undo.saveStep(),o=null)}
#
# Fixed pattern:
#   forceUndo:function(){n&&(clearTimeout(n),n=null,g.undo.saveStep(),o=null)}

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: forceUndo clears its typing timer handle',
        re.compile(r'forceUndo:function\(\)\{([\w$]+)&&\(clearTimeout\(\1\),(?!\1=null,)'),
        lambda m: f'forceUndo:function(){{{m[1]}&&(clearTimeout({m[1]}),{m[1]}=null,',
        lambda c: re.search(r'forceUndo:function\(\)\{([\w$]+)&&\(clearTimeout\(\1\),\1=null,', c) is not None
    )


# ── Fix 37: core bundles — formatting into a non-editable wrapper of blocks ─
#
# With allowStylingOnNonEditable, format.apply re-entered a non-editable
# ancestor that isn't a block tag. For a wrapper that holds blocks (PA's
# <signature contenteditable="false"><p>…</p></signature>) it went back down to
# the block and up to the wrapper again until the stack overflowed: Bold over a
# selection ending in the signature formatted nothing. Skip such a wrapper and
# go on after it, as is done without allowStylingOnNonEditable; an inline
# non-editable element (a merge tag) is still formatted whole.
#
# Upstream pattern (variable names change each release):
#   if(M.opts.allowStylingOnNonEditable){if(!M.node.isBlock(n))return void $(n,s,l);
#
# Fixed pattern:
#   if(M.opts.allowStylingOnNonEditable){if(!M.node.isBlock(n))return void([].some.call(n.querySelectorAll("*"),
#     M.node.isBlock)?n.nextSibling&&!M.node.hasClass(n.nextSibling,"fr-marker")&&$(n.nextSibling,s,l):$(n,s,l));

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: formatting skips a non-editable wrapper of blocks',
        re.compile(
            r'(\.opts\.allowStylingOnNonEditable\)\{)if\(!([\w$]+)\.node\.isBlock\(([\w$]+)\)\)'
            r'return void ([\w$]+)\(\3,([\w$]+),([\w$]+)\);'
        ),
        lambda m: (
            f'{m[1]}if(!{m[2]}.node.isBlock({m[3]}))return void([].some.call({m[3]}.querySelectorAll("*"),{m[2]}.node.isBlock)'
            f'?{m[3]}.nextSibling&&!{m[2]}.node.hasClass({m[3]}.nextSibling,"fr-marker")&&{m[4]}({m[3]}.nextSibling,{m[5]},{m[6]})'
            f':{m[4]}({m[3]},{m[5]},{m[6]}));'
        ),
        lambda c: re.search(r'\.querySelectorAll\("\*"\),[\w$]+\.node\.isBlock\)\?', c) is not None
    )


# ── Fix 38: core bundles — formatting goes around a non-editable wrapper of blocks
#
# Fix 37 covered the walk entering such a wrapper from inside. The walk also
# meets it from outside, as the next node after a block or as a sibling of
# inline text, and with allowStylingOnNonEditable it then wrapped it whole in
# the format: Select All + Bold saved <strong><signature><p>…</p></signature>
# </strong>, and the recipient read the whole signature in bold (italic,
# underline, colour and size alike). Treat a wrapper that holds blocks as
# Froala does any non-editable element without allowStylingOnNonEditable: go
# on after it, unless the selection ends inside it. An inline non-editable
# element (a merge tag) is still formatted whole.
#
# Upstream patterns (variable names change each release):
#   walk start: "false"===t){if(!M.opts.allowStylingOnNonEditable)return void(a.nextSibling&&!x(a.nextSibling)
#                 .hasClass("fr-marker")&&$(a.nextSibling,s,l));
#   sibling loop: E.tagName&&E.hasAttribute("contenteditable")&&"false"===E.getAttribute("contenteditable")
#                 &&!M.opts.allowStylingOnNonEditable&&!E.classList.contains("fr-anchor")
#
# Fixed patterns:
#   walk start: …;if(!M.node.isBlock(a)&&[].some.call(a.querySelectorAll("*"),M.node.isBlock))return void(
#                 !a.querySelector(".fr-marker")&&a.nextSibling&&!x(a.nextSibling).hasClass("fr-marker")
#                 &&$(a.nextSibling,s,l));
#   sibling loop: …&&(!M.opts.allowStylingOnNonEditable||!M.node.isBlock(E)&&[].some.call(
#                 E.querySelectorAll("*"),M.node.isBlock))&&!E.classList.contains("fr-anchor")

for core_bundle in (
    "js/froala_editor.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        core_bundle,
        f'{core_bundle}: formatting from outside goes around a non-editable wrapper of blocks',
        re.compile(
            r'("false"===[\w$]+\)\{if\(!([\w$]+)\.opts\.allowStylingOnNonEditable\)return void\(([\w$]+)\.nextSibling&&'
            r'!([\w$]+)\(\3\.nextSibling\)\.hasClass\("fr-marker"\)&&([\w$]+)\(\3\.nextSibling,([\w$]+),([\w$]+)\)\);)'
            r'(?!if\(!)'
        ),
        lambda m: (
            f'{m[1]}if(!{m[2]}.node.isBlock({m[3]})&&[].some.call({m[3]}.querySelectorAll("*"),{m[2]}.node.isBlock))'
            f'return void(!{m[3]}.querySelector(".fr-marker")&&{m[3]}.nextSibling&&'
            f'!{m[4]}({m[3]}.nextSibling).hasClass("fr-marker")&&{m[5]}({m[3]}.nextSibling,{m[6]},{m[7]}));'
        ),
        lambda c: re.search(
            r'allowStylingOnNonEditable\)return void\([^;]*\);if\(![\w$]+\.node\.isBlock\(([\w$]+)\)&&'
            r'\[\]\.some\.call\(\1\.querySelectorAll\("\*"\),[\w$]+\.node\.isBlock\)\)return void\(!\1\.querySelector',
            c,
        ) is not None
    )
    apply_fix(
        core_bundle,
        f'{core_bundle}: formatting a run of siblings goes around a non-editable wrapper of blocks',
        re.compile(
            r'(([\w$]+)\.tagName&&\2\.hasAttribute\("contenteditable"\)&&"false"===\2\.getAttribute\("contenteditable"\)&&)'
            r'!([\w$]+)\.opts\.allowStylingOnNonEditable(&&!\2\.classList\.contains\("fr-anchor"\))'
        ),
        lambda m: (
            f'{m[1]}(!{m[3]}.opts.allowStylingOnNonEditable||!{m[3]}.node.isBlock({m[2]})&&'
            f'[].some.call({m[2]}.querySelectorAll("*"),{m[3]}.node.isBlock)){m[4]}'
        ),
        lambda c: re.search(
            r'&&\(![\w$]+\.opts\.allowStylingOnNonEditable\|\|![\w$]+\.node\.isBlock\(([\w$]+)\)&&'
            r'\[\]\.some\.call\(\1\.querySelectorAll\("\*"\),[\w$]+\.node\.isBlock\)\)&&!\1\.classList\.contains\("fr-anchor"\)',
            c,
        ) is not None
    )


# ── Fix 39: image bundles — an image copied in Safari or Apple Mail is uploaded
#
# The image paste handler leaves OneNote content to the HTML paste, before it
# looks for the clipboard's image file. Its OneNote check matched
# caret-color: rgb(, which Safari, Apple Mail and Notes write on every copy, so
# an image copied there was never read from the clipboard: Apple Mail's
# webkit-fake-url:// image was dropped, and Safari's was linked to the page it
# came from instead of uploaded. Look for OneNote's own markers instead
# (OneNote.File, OutlineElement), as the core's Word check does since Fix 34.
#
# Upstream pattern (variable names change each release):
#   e=/caret-color:\s*rgb\(/.test(t)||/direction:\s*ltr.*margin-top:\s*0in/.test(t)||…
#
# Fixed pattern:
#   e=/OneNote\.File|OutlineElement/.test(t)||/direction:\s*ltr.*margin-top:\s*0in/.test(t)||…

for image_bundle in (
    "js/plugins/image.min.js",
    "js/plugins/files_manager.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        image_bundle,
        f'{image_bundle}: an image copied in Safari or Apple Mail is uploaded',
        re.compile(
            r'/caret-color:\\s\*rgb\\\(/(\.test\([\w$]+\)\|\|/direction:\\s\*ltr\.\*margin-top:\\s\*0in/\.test\()'
        ),
        lambda m: r'/OneNote\.File|OutlineElement/' + m[1],
        lambda c: r'/OneNote\.File|OutlineElement/.test(' in c and r'/caret-color:\s*rgb\(/.test(' not in c,
        count=0,
    )


# ── Fix 40: AI bundles — Enter in the AI prompt asks, or inserts the suggestion
#
# Once a suggestion is shown, the popup's keyboard navigation took Enter in the
# prompt for its visible submit button, Insert, and ran it as a command. Insert
# is a click handler, not a command, so Enter did nothing: a follow-up typed
# under a suggestion was never asked (the plugin's own Enter handler, which
# asks, never got the key). Enter in the prompt now asks what is typed there,
# as the arrow button does, and on an empty prompt under a suggestion it
# inserts the suggestion, as Insert does.
#
# Upstream pattern (variable names change each release):
#   f.on("click",'.fr-command[data-cmd="aiAssistInsert"]',N),…,f.on("click",".fr-ai-assist-submit-btn",w),
#     f.on("input",".fr-ai-assist-prompt-input",y),f.on("keydown",O),l.bindPopup(f),
#     T.events.on("popups.hide.aiAssist.promptPopup",B)
#
# Fixed pattern:
#   …,T.events.on("popups.hide.aiAssist.promptPopup",B),T.events.on("popup.tab",function(e){
#     if("Enter"===e.key&&!e.isComposing&&f&&f.isVisible()&&e.target&&e.target.classList&&
#     e.target.classList.contains("fr-ai-assist-prompt-input")){if(e.target.value.trim())return
#     e.preventDefault(),e.stopPropagation(),w(),!1;if(!f.find(".fr-ai-assist-response-layer").hasClass("fr-hidden")
#     &&f.find(".fr-ai-assist-response-content").html())return e.preventDefault(),e.stopPropagation(),N(),!1}})

for ai_bundle in (
    "js/plugins/ai_assist.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        ai_bundle,
        f'{ai_bundle}: Enter in the AI prompt asks, or inserts the suggestion',
        re.compile(
            r'([\w$]+)\.on\("click",\'\.fr-command\[data-cmd="aiAssistInsert"\]\',([\w$]+)\),'
            r'\1\.on\("click",\'\.fr-command\[data-cmd="aiAssistRefresh"\]\',[\w$]+\),'
            r'\1\.on\("click","\.fr-ai-assist-submit-btn",([\w$]+)\),'
            r'\1\.on\("input","\.fr-ai-assist-prompt-input",[\w$]+\),\1\.on\("keydown",[\w$]+\),'
            r'[\w$]+\.bindPopup\(\1\),([\w$]+)\.events\.on\("popups\.hide\.aiAssist\.promptPopup",[\w$]+\)'
        ),
        lambda m: (
            f'{m[0]},{m[4]}.events.on("popup.tab",function(e){{if("Enter"===e.key&&!e.isComposing&&{m[1]}&&'
            f'{m[1]}.isVisible()&&e.target&&e.target.classList&&e.target.classList.contains("fr-ai-assist-prompt-input"))'
            f'{{if(e.target.value.trim())return e.preventDefault(),e.stopPropagation(),{m[3]}(),!1;'
            f'if(!{m[1]}.find(".fr-ai-assist-response-layer").hasClass("fr-hidden")&&'
            f'{m[1]}.find(".fr-ai-assist-response-content").html())return e.preventDefault(),e.stopPropagation(),{m[2]}(),!1}}}})'
        ),
        lambda c: 'e.target.classList.contains("fr-ai-assist-prompt-input")){if(e.target.value.trim())' in c
    )


# ── Fix 41: AI bundles — the AI popup is moved up when the answer makes it tall
#
# AI Assist places its popup with its bottom on the bottom of the editing area
# (or of the window), sized for the empty prompt. When the answer arrives the
# popup grows downwards, and it was only moved back up if the top of the
# editing area plus the popup's new height still fitted in the window: with the
# editor low on a page or in a dialog it stayed put, ran off the bottom of the
# window, and Insert couldn't be reached. Move it whenever the editing area is
# in the window (Fix 30 keeps its top below the window's and scroll box's top);
# once the editing area has scrolled out of the window the popup stays with it.
#
# Upstream pattern (variable names change each release):
#   t=(r=T.$wp[0].getBoundingClientRect()).bottom,n=r.top,…,f.isVisible()&&n+(f.height()+i+20)<a&&(…position.at(null,r,f))
#
# Fixed pattern:
#   t=(r=T.$wp[0].getBoundingClientRect()).bottom,n=r.top,…,f.isVisible()&&n<a&&0<t&&(…position.at(null,r,f))

for ai_bundle in (
    "js/plugins/ai_assist.min.js",
    "js/plugins.pkgd.min.js",
    "js/froala_editor.pkgd.min.js",
):
    apply_fix(
        ai_bundle,
        f'{ai_bundle}: the AI popup is moved up when the answer makes it tall',
        re.compile(
            r'(([\w$]+)=\(([\w$]+)=[\w$]+\.\$wp\[0\]\.getBoundingClientRect\(\)\)\.bottom,([\w$]+)=\3\.top,'
            r'[\s\S]{0,1200}?"aiAssist\.promptPopup",null,[\w$]+\):[\w$]+\.isVisible\(\)&&)'
            r'\4\+\([\w$]+\.height\(\)\+[\w$]+\+20\)<([\w$]+)&&'
        ),
        lambda m: f'{m[1]}{m[4]}<{m[5]}&&0<{m[2]}&&',
        lambda c: re.search(
            r'"aiAssist\.promptPopup",null,[\w$]+\):[\w$]+\.isVisible\(\)&&[\w$]+<[\w$]+&&0<[\w$]+&&', c
        ) is not None
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
