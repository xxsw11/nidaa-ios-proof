"""Idempotently include app/UI-test Swift sources and the local integration package."""
from pathlib import Path
import hashlib
import plistlib

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / 'NidaaProof.xcodeproj/project.pbxproj'
project = plistlib.loads(PATH.read_bytes())
objects = project['objects']
root = objects[project['rootObject']]
group = objects[root['mainGroup']]


def identifier(value):
    return hashlib.sha256(('nidaa-integration:' + value).encode()).hexdigest()[:24].upper()


def append_once(values, value):
    if value not in values:
        values.append(value)


targets = {value['name']:value for value in objects.values() if value['isa']=='PBXNativeTarget'}
for directory,target_name in [('App','NidaaProof'),('UITests','NidaaUITests')]:
    target = targets[target_name]
    phase = next(objects[key] for key in target['buildPhases'] if objects[key]['isa']=='PBXSourcesBuildPhase')
    for path in sorted((ROOT / directory).rglob('*.swift')):
        relative = path.relative_to(ROOT).as_posix()
        reference = next((key for key,value in objects.items() if value['isa']=='PBXFileReference' and value.get('path')==relative),None)
        if reference is None:
            reference = identifier(relative)
            objects[reference] = dict(isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path=relative,sourceTree='<group>')
            append_once(group['children'],reference)
        build = next((key for key,value in objects.items() if value['isa']=='PBXBuildFile' and value.get('fileRef')==reference),None)
        if build is None:
            build = identifier('build:' + relative)
            objects[build] = dict(isa='PBXBuildFile',fileRef=reference)
        append_once(phase['files'],build)

package = identifier('package')
product = identifier('product')
build = identifier('product-build')
objects[package] = dict(isa='XCLocalSwiftPackageReference',relativePath='IntegrationClient')
objects[product] = dict(isa='XCSwiftPackageProductDependency',package=package,productName='NidaaIntegration')
objects[build] = dict(isa='PBXBuildFile',productRef=product)
append_once(root['packageReferences'],package)
target = targets['NidaaProof']
append_once(target['packageProductDependencies'],product)
frameworks = next(objects[key] for key in target['buildPhases'] if objects[key]['isa']=='PBXFrameworksBuildPhase')
append_once(frameworks['files'],build)

# Only Debug uses the local-network plist. Release retains the original ATS policy.
for key in objects[target['buildConfigurationList']]['buildConfigurations']:
    config = objects[key]
    if config['name']=='Debug':
        config['buildSettings']['INFOPLIST_FILE']='Config/Integration-Debug-Info.plist'
debug_info = plistlib.loads((ROOT/'App/Info.plist').read_bytes())
debug_info['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking':True}
(ROOT/'Config/Integration-Debug-Info.plist').write_bytes(plistlib.dumps(debug_info,sort_keys=False))
PATH.write_bytes(plistlib.dumps(project,sort_keys=False))
print('App/UI sources and local package are included; local-network policy is Debug only.')
