#!/usr/bin/env python3
"""Write the open-source acknowledgements shown in Settings → Porch.

Run this after changing a Swift package version, once Xcode has resolved the
packages (open the project or build it):

    python3 ios/scripts/generate-acknowledgements.py [--packages <SourcePackages>]

Each pinned package's license comes from its checkout. The WebRTC and LiveKit
UniFFI binaries compile in other libraries and Rust crates without shipping
their notices, so those are found in the binaries and their licenses are
fetched from upstream and crates.io. The family bundle leaves out the
Cell2Jack driver's Apple sample code, which only the Porch build embeds.
"""
import argparse
import base64
import io
import json
import plistlib
import re
import subprocess
import tarfile
import urllib.request
from pathlib import Path

ios = Path(__file__).resolve().parents[1]
resolved = ios / "Porch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
porch_settings = ios / "Porch/Settings.bundle"
family_settings = ios / "Porch/FamilySettings/Settings.bundle"
apple_sample = ios / "Cell2JackDriver/APPLE-SAMPLE-LICENSE.txt"

PACKAGES = {
    "client-sdk-swift": ("LiveKit Swift SDK", "Apache-2.0"),
    "livekit-uniffi-xcframework": ("LiveKit UniFFI", "Apache-2.0"),
    "phonenumberkit": ("PhoneNumberKit", "MIT"),
    "webrtc-xcframework": ("LiveKit WebRTC", "MIT"),
}

# Libraries compiled into LiveKitWebRTC, each found by a string it leaves in the binary.
WEBRTC_LIBRARIES = [
    ("Abseil", "Apache-2.0", b"third_party/abseil-cpp",
     "https://raw.githubusercontent.com/abseil/abseil-cpp/master/LICENSE"),
    ("BoringSSL", "Apache-2.0", b"third_party/boringssl",
     "https://raw.githubusercontent.com/google/boringssl/main/LICENSE"),
    ("dav1d", "BSD-2-Clause", b"dav1d",
     "https://code.videolan.org/videolan/dav1d/-/raw/master/COPYING"),
    ("libaom", "BSD-2-Clause", b"Libaom",
     "https://aomedia.googlesource.com/aom/+/refs/heads/main/LICENSE?format=TEXT"),
    ("libc++", "Apache-2.0 WITH LLVM-exception", b"third_party/libc++",
     "https://raw.githubusercontent.com/llvm/llvm-project/main/libcxx/LICENSE.TXT"),
    ("libsrtp", "BSD-3-Clause", b"libsrtp",
     "https://raw.githubusercontent.com/cisco/libsrtp/main/LICENSE"),
    ("libvpx", "BSD-3-Clause", b"libvpx",
     "https://chromium.googlesource.com/webm/libvpx/+/refs/heads/main/LICENSE?format=TEXT"),
    ("libyuv", "BSD-3-Clause", b"libyuv::",
     "https://chromium.googlesource.com/libyuv/libyuv/+/refs/heads/main/LICENSE?format=TEXT"),
    ("Opus", "BSD-3-Clause", b"third_party/opus",
     "https://raw.githubusercontent.com/xiph/opus/main/COPYING"),
]


# Official texts for crates that name a license without including its file.
LICENSE_TEXTS = {"MPL-2.0": "https://www.mozilla.org/media/MPL/2.0/index.txt"}


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    # Gitiles serves raw files only as base64.
    return base64.b64decode(data) if url.endswith("?format=TEXT") else data


def clean(text):
    text = text.replace("\r\n", "\n").strip()
    if text.startswith("/*") and text.endswith("*/"):
        lines = text[2:-2].strip("\n").split("\n")
        text = "\n".join(re.sub(r"^\s*\* ?", "", line) for line in lines).strip()
    return text


def entry(title, license, text, package=None):
    item = {"Type": "PSGroupSpecifier", "Title": title, "License": license, "FooterText": text}
    if package:
        item["Package"] = package
    return item


def find_packages():
    project = str(ios / "Porch.xcodeproj")
    candidates = []
    for info in (Path.home() / "Library/Developer/Xcode/DerivedData").glob("*/info.plist"):
        try:
            workspace = plistlib.loads(info.read_bytes()).get("WorkspacePath")
        except Exception:
            continue
        packages = info.parent / "SourcePackages"
        if workspace == project and (packages / "checkouts").is_dir():
            candidates.append(packages)
    if not candidates:
        raise SystemExit("No resolved packages found. Open ios/Porch.xcodeproj in Xcode, or pass --packages.")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def framework_binary(packages, identity):
    binaries = list((packages / "artifacts" / identity).glob("*/*.xcframework/ios-arm64/*.framework"))
    assert len(binaries) == 1, f"Expected one iOS framework for {identity}, found {binaries}"
    return binaries[0] / binaries[0].stem


def swift_packages(packages, pins):
    entries = []
    for pin in pins:
        identity, state = pin["identity"], pin["state"]
        if identity not in PACKAGES:
            raise SystemExit(f"Add a title and license for the new package {identity} to PACKAGES.")
        title, license = PACKAGES[identity]
        checkout = packages / "checkouts" / pin["location"].rstrip("/").split("/")[-1].removesuffix(".git")
        revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
        if revision != state["revision"]:
            raise SystemExit(f"{checkout} is not at the pinned revision. Resolve packages in Xcode first.")
        text = "\n\n".join(clean(path.read_text()) for path in sorted(checkout.glob("*"))
                           if re.match(r"(LICENSE|NOTICE)(\.|$)", path.name))
        entries.append(entry(f"{title} {state['version']}", license, text, f"{identity}@{state['version']}"))
    return entries


def webrtc(packages):
    binary = framework_binary(packages, "webrtc-xcframework")
    contents = binary.read_bytes()
    entries = [entry("WebRTC", "BSD-3-Clause", clean((binary.parent.parent.parent / "LICENSE").read_text()))]
    for title, license, marker, url in WEBRTC_LIBRARIES:
        if marker not in contents:
            print(f"warning: {title} is no longer in WebRTC; leaving it out")
            continue
        text = clean(fetch(url).decode())
        entries.append(entry(title, license, f"{text}\n\nIncluded in WebRTC."))
    return entries


def crate(name, version):
    data = fetch(f"https://static.crates.io/crates/{name}/{name}-{version}.crate")
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive.getmembers():
            parts = member.name.split("/")
            if member.isfile() and len(parts) == 2:
                files[parts[1]] = archive.extractfile(member).read().decode(errors="replace")
    license = re.search(r'^license\s*=\s*"([^"]+)"', files["Cargo.toml"], re.M)
    license = license.group(1) if license else "See source"
    notices = sorted(file for file in files if re.match(r"(LICEN[CS]E|COPYING|NOTICE)", file, re.I))
    # Dual-licensed crates are used under MIT, the one that carries the authors' notice.
    if re.search(r"\bMIT\b", license):
        mit = [file for file in notices if "MIT" in file.upper() or "Permission is hereby granted" in files[file]]
        if mit:
            notices, license = mit, "MIT"
    text = "\n\n".join(clean(files[file]) for file in notices)
    if not text and license in LICENSE_TEXTS:
        text = clean(fetch(LICENSE_TEXTS[license]).decode())
    if not text:
        raise SystemExit(f"{name} {version} has no license file; add its {license} text to LICENSE_TEXTS.")
    return entry(f"{name} {version}", license,
                 f"{text}\n\nIncluded in LiveKit UniFFI. Source: https://crates.io/crates/{name}/{version}")


def rust_crates(packages):
    contents = framework_binary(packages, "livekit-uniffi-xcframework").read_bytes().decode("latin-1")
    found = set(re.findall(r"index\.crates\.io-[0-9a-f]+/([A-Za-z0-9_-]+?)-(\d+\.\d+\.\d+[0-9A-Za-z.+-]*)/",
                           contents))
    return [crate(name, version) for name, version in sorted(found)]


def write(bundle, entries):
    header = {"Type": "PSGroupSpecifier",
              "FooterText": "Porch includes the open-source software below, each under the license shown."}
    data = {"Title": "Acknowledgements", "PreferenceSpecifiers": [header] + entries}
    (bundle / "Acknowledgements.plist").write_bytes(plistlib.dumps(data))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--packages", type=Path, help="Xcode's SourcePackages folder for this project")
    packages = parser.parse_args().packages or find_packages()
    pins = json.loads(resolved.read_text())["pins"]
    shared = sorted(swift_packages(packages, pins), key=lambda item: item["Title"].lower())
    shared += webrtc(packages) + rust_crates(packages)
    write(family_settings, shared)
    driver = entry("Apple DriverKit sample code", "MIT", clean(apple_sample.read_text()))
    write(porch_settings, shared + [driver])
    print(f"Wrote {len(shared)} acknowledgements from {packages}")


if __name__ == "__main__":
    main()
