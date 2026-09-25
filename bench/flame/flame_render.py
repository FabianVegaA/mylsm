#!/usr/bin/env python3
"""Render folded stacks to a self-contained SVG flame graph (stdlib only).
Usage: flame_render.py <folded.txt> <out.svg> [title]
Colors: runtime hues by top-level callee category; hover via <title>.
"""
import sys
from xml.sax.saxutils import escape

W, ROW_H, PAD_TOP, PAD_BOTTOM = 1200, 22, 60, 30
FONT = 12

def color(holder):
    h = abs(hash(holder)) % 360
    if 'SELECT' in holder or 'select' in holder:
        return f'hsl(210,60%,{55 + hash(holder) % 15}%)'
    if holder.startswith('WL_FID'):
        return f'hsl({10 + abs(hash(holder)) % 30},65%,55%)'
    if holder.startswith(('term_', 'span_', 'pool_', 'corpus_', 'io_')):
        return f'hsl({45 + abs(hash(holder)) % 25},60%,55%)'
    return f'hsl({h},45%,60%)'

def short(name, width):
    maxch = max(1, int(width // (FONT * 0.6)))
    return name if len(name) <= maxch else name[:maxch - 1] + '…'

def main():
    folded, out, title = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else 'flame graph'
    stacks = []
    total = 0
    for line in open(folded):
        line = line.rstrip('\n')
        if not line:
            continue
        stack, weight = line.rsplit(' ', 1)
        weight = int(weight)
        total += weight
        stacks.append((stack.split(';'), weight))
    maxdepth = max(len(s) for s, _ in stacks)
    H = PAD_TOP + maxdepth * ROW_H + PAD_BOTTOM
    unit = W / total
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="monospace" font-size="{FONT}">',
             f'<text x="{W//2}" y="24" text-anchor="middle" font-size="16">{escape(title)} — {total} samples</text>']
    cursor = {}
    for frames, weight in sorted(stacks):
        parent = tuple(frames[:-1])
        x = cursor.get(parent, 0.0)
        w = weight * unit
        cursor[parent] = x + w
        y = PAD_TOP + (len(frames) - 1) * ROW_H
        fill = color(frames[-1])
        tip = f"{';'.join(frames)} — {weight} ({100*weight/total:.1f}%)"
        parts.append(f'<rect x="{x:.1f}" y="{y}" width="{max(0.5,w):.1f}" height="{ROW_H-2}" fill="{fill}" stroke="white"><title>{escape(tip)}</title></rect>')
        if w > 30:
            parts.append(f'<text x="{x+3:.1f}" y="{y+15}">{escape(short(frames[-1], w-6))}</text>')
    parts.append('</svg>')
    open(out, 'w').write('\n'.join(parts))
    print(f'wrote {out} ({total} samples, {maxdepth} deep)')

main()
