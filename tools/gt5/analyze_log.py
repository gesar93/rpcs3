"""Extract observed RPCS3 log evidence; never infer a root cause from log severity."""
import argparse
import gzip
import hashlib
import json
import pathlib
import re


def analyze(path):
    path = pathlib.Path(path)
    evidence = dict(build=None, titles=[], serials=[], game_versions=[],
                    fatal=[], memory_errors=[], rsx_shutdown_waits=[], last_timestamp=None)
    opener = gzip.open if path.suffix.lower() == '.gz' else open
    with opener(path, 'rt', encoding='utf-8-sig', errors='replace') as stream:
        for number, line in enumerate(stream, 1):
            if evidence['build'] is None and line.startswith('RPCS3 v'):
                evidence['build'] = line.strip()
            stamp = re.search(r'(?<!\d)(\d+:\d\d:\d\d\.\d+)', line)
            if stamp:
                evidence['last_timestamp'] = stamp.group(1)
            for key, pattern in (
                ('titles', r'\bSYS: Title: (.+)'),
                ('serials', r'\bSYS: Serial: ([A-Z]{4}\d{5})'),
                ('game_versions', r'\bSYS: Version: (.+)'),
            ):
                match = re.search(pattern, line)
                if match and match.group(1).strip() not in evidence[key]:
                    evidence[key].append(match.group(1).strip())
            item = dict(line=number, text=line.rstrip()[:1500])
            if re.match(r'^[·\s]*F\s+\d+:\d\d:', line):
                if len(evidence['fatal']) < 20:
                    evidence['fatal'].append(item)
            if re.search(r'bad_alloc|out of (?:host |device )?memory|CELL_ENOMEM|VK_ERROR_OUT_OF_(?:HOST|DEVICE)_MEMORY', line, re.I):
                if len(evidence['memory_errors']) < 20:
                    evidence['memory_errors'].append(item)
            if 'Thread [rsx::thread] is too sleepy.' in line:
                evidence['rsx_shutdown_waits'].append(item)
                evidence['rsx_shutdown_waits'] = evidence['rsx_shutdown_waits'][-8:]
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return dict(sha256=h.hexdigest(), bytes=path.stat().st_size, evidence=evidence,
                interpretation='Observations only. Shutdown waits do not establish the original hang cause; absence of OOM messages does not rule out memory exhaustion.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    report = json.dumps(analyze(args.log), ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(report + '\n', encoding='utf-8')
    else:
        print(report)
