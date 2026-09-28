import json, sys
data=json.load(open(sys.argv[1]))
devices=[(runtime, d) for runtime, values in data['devices'].items() if 'iOS' in runtime for d in values if d.get('isAvailable') and 'iPhone' in d['name']]
if not devices: raise SystemExit('No available iPhone Simulator')
def priority(item):
    runtime,d=item
    # Avoid SE as the sole screenshot target; prefer a standard recent Pro, not Max.
    preferred=0 if d['name'] in ['iPhone 16 Pro','iPhone 17 Pro','iPhone 15 Pro'] else 1
    return (preferred, 'Max' in d['name'], 'SE' in d['name'], d['name'])
runtime, device = sorted(devices,key=priority)[0]
if '--template' in sys.argv[2:]:
    print(device['deviceTypeIdentifier'])
    print(runtime)
else:
    print(device['udid'])
