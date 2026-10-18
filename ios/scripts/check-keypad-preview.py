#!/usr/bin/env python3
"""Check the preview-only target's boundary before installing a no-call build."""
from pathlib import Path
import json
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
project = json.loads(subprocess.check_output([
    'plutil', '-convert', 'json', '-o', '-', str(root / 'Porch.xcodeproj/project.pbxproj')]))['objects']
target = next(value for value in project.values()
              if value.get('isa') == 'PBXNativeTarget' and value.get('name') == 'PorchKeypadPreview')
phases = [project[item] for item in target['buildPhases']]
sources = next(item for item in phases if item['isa'] == 'PBXSourcesBuildPhase')
paths = {project[project[item]['fileRef']]['path'] for item in sources['files']}
allowed = {'PorchKeypadPreviewApp.swift', 'KeypadPreviewViewController.swift', 'CaregiverUI.swift',
           'Cell2JackBridge.m', 'Cell2JackDTMFParser.swift', 'Cell2JackLogCapture.swift',
           'Cell2JackVersionResult.swift'}
assert paths == allowed, f'Preview sources changed; review the no-call boundary: {paths ^ allowed}'
products = [project[item]['productName'] for item in target['packageProductDependencies']]
assert products == ['PorchCore'], f'Unexpected calling package linked: {products}'
info = plistlib.loads((root / 'PorchKeypadPreview/Info.plist').read_bytes())
for name in ['UIBackgroundModes', 'CFBundleURLTypes', 'NSMicrophoneUsageDescription', 'NSCameraUsageDescription']:
    assert name not in info, f'Unexpected call/media entry point: {name}'
entitlements = plistlib.loads((root / 'PorchKeypadPreview/Preview.entitlements').read_bytes())
assert entitlements == {'com.apple.developer.driverkit.communicates-with-drivers': True}
if len(sys.argv) > 1:
    app = Path(sys.argv[1])
    built = plistlib.loads((app / 'Info.plist').read_bytes())
    binary = app / built['CFBundleExecutable']
    linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
    symbols = subprocess.check_output(['nm', '-j', str(binary)], text=True, stderr=subprocess.DEVNULL)
    for name in ['LiveKit', 'CallKit', 'PushKit']:
        assert name not in linked, f'Calling framework linked: {name}'
    for name in ['FamilyCoordinator', 'FamilyService', 'SystemIncomingCalls', 'NativeCallViewController',
                 'CXProvider', 'PKPushRegistry', 'AVAudioSession']:
        assert name not in symbols, f'Calling implementation linked: {name}'
print('Preview boundary passed: native Porch UI/Core + USB only; no calling engine or call/media entry points.')
