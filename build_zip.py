import zipfile, os

base = r"D:\Libraries\Pixelorama\TileTools"
output = r"D:\Libraries\Pixelorama\TileTools.zip"

with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as zf:
    # Extension files
    ext_dir = os.path.join(base, "src", "Extensions", "TileTools")
    for fname in sorted(os.listdir(ext_dir)):
        fpath = os.path.join(ext_dir, fname)
        if os.path.isfile(fpath) and not fname.endswith(".uid"):
            arcname = "src/Extensions/TileTools/" + fname
            zf.write(fpath, arcname)
            print("  " + arcname)

    # Tool icons
    icons = [
        ("assets/graphics/tools/tileselect.png",
         os.path.join(base, "assets", "graphics", "tools", "tileselect.png")),
        ("assets/graphics/tools/cursors/tileselect.png",
         os.path.join(base, "assets", "graphics", "tools", "cursors", "tileselect.png")),
    ]
    for arcname, fpath in icons:
        if os.path.isfile(fpath):
            zf.write(fpath, arcname)
            print("  " + arcname)

print("\nBuilt " + output)
