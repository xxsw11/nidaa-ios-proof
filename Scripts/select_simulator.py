"""Choose an available iPhone on the newest installed iOS runtime; no fixed model."""
import json
import re
import sys


def choose(payload):
    candidates = []
    for runtime, devices in payload.get('devices', {}).items():
        match = re.search(r'\.iOS-(\d+(?:-\d+)*)$', runtime)
        if not match:
            continue
        version = tuple(int(x) for x in match.group(1).split('-'))
        for device in devices:
            if device.get('isAvailable') and device.get('name', '').startswith('iPhone'):
                candidates.append((version, device['name'], device['udid']))
    if not candidates:
        raise ValueError('No available iPhone simulator. Review the runner image and installed runtimes.')
    return sorted(candidates, reverse=True)[0][2]


if __name__ == '__main__':
    with open(sys.argv[1], encoding='utf-8') as stream:
        print(choose(json.load(stream)))
