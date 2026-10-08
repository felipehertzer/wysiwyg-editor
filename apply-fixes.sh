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
