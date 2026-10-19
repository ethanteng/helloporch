#!/usr/bin/env python3
"""Check that family builds share feature sources but cannot embed a USB driver."""
import json
import plistlib
import subprocess
from pathlib import Path

ios = Path(__file__).resolve().parents[1]
project = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", str(ios / "Porch.xcodeproj/project.pbxproj")]))
objects = project["objects"]
targets = {obj["name"]: obj for obj in objects.values() if obj.get("isa") == "PBXNativeTarget"}
normal, family = targets["Porch"], targets["PorchFamily"]

def phases(target, kind):
    return [key for key in target["buildPhases"] if objects[key]["isa"] == kind]

assert phases(normal, "PBXSourcesBuildPhase") == phases(family, "PBXSourcesBuildPhase"), "Feature sources must stay shared"
assert phases(normal, "PBXFrameworksBuildPhase") == phases(family, "PBXFrameworksBuildPhase"), "Feature frameworks must stay shared"
assert not family["dependencies"], "Family must not depend on a driver"
assert not phases(family, "PBXCopyFilesBuildPhase"), "Family must not embed a driver"
assert objects[normal["productReference"]]["path"] != objects[family["productReference"]]["path"], "Variants must not reuse stale app products"
assert phases(normal, "PBXCopyFilesBuildPhase") and normal["dependencies"], "Preserve the Cell2Jack development build"
normal_phases = phases(normal, "PBXResourcesBuildPhase")
family_phases = phases(family, "PBXResourcesBuildPhase")
assert len(family_phases) == 1 and family_phases[0] in normal_phases, "Feature resources must stay shared"
driver_resources = [key for key in normal_phases if key not in family_phases]
assert len(driver_resources) == 1
settings = objects[driver_resources[0]]["files"]
assert len(settings) == 1 and objects[objects[settings[0]]["fileRef"]]["path"].endswith("Settings.bundle")
for config in objects[family["buildConfigurationList"]]["buildConfigurations"]:
    settings = objects[config]["buildSettings"]
    assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.ethanteng.helloporch"
    assert settings["PRODUCT_MODULE_NAME"] == "Porch"
    assert "PORCH_NO_CELL2JACK" in settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]
    assert not settings["SWIFT_OBJC_BRIDGING_HEADER"]
    assert "Cell2JackBridge.m" in settings["EXCLUDED_SOURCE_FILE_NAMES"]
    assert "Cell2JackLogCapture.swift" in settings["EXCLUDED_SOURCE_FILE_NAMES"]
    entitlements = plistlib.loads((ios / settings["CODE_SIGN_ENTITLEMENTS"]).read_bytes())
    assert entitlements == {"aps-environment": "$(APS_ENVIRONMENT)"}

def build_setting(target_name, key):
    values = [objects[config]["buildSettings"].get(key)
              for config in objects[targets[target_name]["buildConfigurationList"]]["buildConfigurations"]]
    assert len({str(value) for value in values}) == 1, (target_name, key, values)
    return values[0]

# A frozen driver build number matches the already-installed dext, so iPadOS keeps the old copy.
assert str(build_setting("Porch", "CURRENT_PROJECT_VERSION")) == "$(PORCH_BUILD_NUMBER)"
assert str(build_setting("PorchCell2JackCallsDriver", "CURRENT_PROJECT_VERSION")) == "$(PORCH_BUILD_NUMBER)"
project = next(obj for obj in objects.values() if obj.get("isa") == "PBXProject")
build_numbers = [objects[config]["buildSettings"].get("PORCH_BUILD_NUMBER")
                 for config in objects[project["buildConfigurationList"]]["buildConfigurations"]]
assert len({str(number) for number in build_numbers}) == 1, build_numbers
assert str(build_numbers[0]).isdigit() and int(build_numbers[0]) > 6, build_numbers
print("Shared feature sources, family driver exclusion, and Cell2Jack development build checks passed")
