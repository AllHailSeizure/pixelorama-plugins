"""Build EasyPixels.zip for Pixelorama.

Tool icons are loaded by Pixelorama with load("res://assets/graphics/tools/<tool>.png"),
which only resolves if the pack also carries the .import sidecar and the .ctex
that sidecar points at. Shipping the bare .png silently yields a blank icon, so
this runs Godot's importer first and packs all three files per icon.
"""

import os
import subprocess
import sys
import zipfile

base = r"D:\Libraries\Pixelorama\EasyPixels"
output = r"D:\Libraries\Pixelorama\EasyPixels.zip"
godot = os.environ.get("GODOT", r"C:\Program Files\Godot 4\Godot_v4.6.3-stable_win64.exe")

ICONS = [
    "assets/graphics/tools/gradientline.png",
    "assets/graphics/tools/cursors/gradientline.png",
    "assets/graphics/tools/easysparkle.png",
    "assets/graphics/tools/cursors/easysparkle.png",
]


def reimport():
    if not os.path.isfile(godot):
        sys.exit("Godot not found at %s — set the GODOT env var." % godot)
    print("Importing assets with Godot...")
    subprocess.run(
        [godot, "--headless", "--path", base, "--import"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def imported_files(icon_rel):
    """The .import sidecar plus every generated resource it references."""
    local = os.path.join(base, icon_rel.replace("/", os.sep))
    if not os.path.isfile(local):
        sys.exit("Missing icon: %s" % local)
    sidecar = local + ".import"
    if not os.path.isfile(sidecar):
        sys.exit("No .import for %s — did the Godot import step run?" % icon_rel)

    files = [(icon_rel, local), (icon_rel + ".import", sidecar)]
    with open(sidecar) as f:
        for line in f:
            if line.startswith("path="):
                res = line.split("=", 1)[1].strip().strip('"')
                rel = res[len("res://"):]
                files.append((rel, os.path.join(base, rel.replace("/", os.sep))))
    return files


reimport()

with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as zf:
    ext_dir = os.path.join(base, "src", "Extensions", "EasyPixels")
    for fname in sorted(os.listdir(ext_dir)):
        fpath = os.path.join(ext_dir, fname)
        if os.path.isfile(fpath) and not fname.endswith(".uid"):
            arcname = "src/Extensions/EasyPixels/" + fname
            zf.write(fpath, arcname)
            print("  " + arcname)

    for icon in ICONS:
        for arcname, fpath in imported_files(icon):
            zf.write(fpath, arcname)
            print("  " + arcname)

print("\nBuilt " + output)
