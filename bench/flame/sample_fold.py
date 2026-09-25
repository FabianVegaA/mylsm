#!/usr/bin/env python3
"""Convert macOS `sample` call-graph output to folded stacks for flamegraph.pl.

Usage: sample_fold.py <sample.txt> > folded.txt
  flamegraph.pl folded.txt > flame.svg   # Brendan Gregg's tool, external

Depth rule for sample(1) call graphs: the sample count column starts at
index 6 for depth 1 and advances 4 to depth 2, then 2 per extra [! : |]
marker. Frame name is the token after the count up to ' (in' or ' +'.
Leaf weight is the frame's own sample count.
"""
import re, sys

def depth_of(line):
    stripped = line.lstrip(' ')
    indent = len(line) - len(stripped)
    m = re.match(r'\+?\s*[!|: ]*(\d+)', line[indent:] if False else line)
    # find count column: first integer token after markers
    mm = re.match(r'\s*\+?\s*((?:[!|:]\s*)*)(\d+)', line)
    if not mm:
        return None, None, None
    markers, count = mm.group(1), int(mm.group(2))
    pos = mm.start(2)
    if pos == 4:
        depth = 0
    elif pos == 7:
        depth = 1
    elif pos == 8:
        depth = 2
    else:
        depth = (pos - 8) // 2 + 2
    rest = line[mm.end(2):].strip()
    name = re.split(r'\s+\(in\s|\s+\+', rest, maxsplit=1)[0].strip()
    return depth, count, name

def main():
    path = sys.argv[1]
    records = []
    in_main = False
    for line in open(path, errors='replace'):
        if line.startswith('Binary Images:'):
            break
        mthread = re.match(r'\s+\d+ (Thread_\d+)(.*)$', line)
        if mthread:
            in_main = 'main-thread' in mthread.group(2)
            continue
        if not in_main:
            continue
        if not line.strip() or line.startswith(('Analysis', 'Process:', 'Path:',
                'Load Address', 'Identifier:', 'Version:', 'Code Type',
                'Platform:', 'Parent Process', 'Target Type', 'Date/Time',
                'Launch Time', 'OS Version', 'Report Version', 'Analysis Tool',
                'Physical', 'Idle exit', '----', 'Call graph:')):
            continue
        d = depth_of(line)
        if d[0] is None:
            continue
        depth, count, name = d
        if not name or depth == 0:
            continue
        if re.fullmatch(r'Thread_\d+', name):
            continue
        records.append((depth, count, name))
    # single pass: emit a frame when popped childless (or at EOF)
    stack, agg = [], {}

    def emit(path, count):
        key = ';'.join(path)
        agg[key] = agg.get(key, 0) + count

    def pop_emit():
        dd, nn, cc, hc = stack.pop()
        if not hc:
            emit([n for _, n, _, _ in stack] + [nn], cc)

    for depth, count, name in records:
        while stack and stack[-1][0] >= depth:
            dd, nn, cc, ks = stack.pop()
            own = cc - ks
            if own > 0:
                emit([n for _, n, _, _ in stack] + [nn], own)
        for e in stack:
            e[3] += count
        stack.append([depth, name, count, 0])
    while stack:
        dd, nn, cc, ks = stack.pop()
        own = cc - ks
        if own > 0:
            emit([n for _, n, _, _ in stack] + [nn], own)
    for s, c in sorted(agg.items()):
        print(f'{s} {c}')

main()
