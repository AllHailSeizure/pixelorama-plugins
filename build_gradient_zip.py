import zipfile, os

base = r"D:\Libraries\Pixelorama\EasyGradient"
output = r"D:\Libraries\Pixelorama\EasyGradient.zip"

with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as zf:
    # Extension files
    ext_dir = os.path.join(base, "src", "Extensions", "EasyGradient")
    for fname in sorted(os.listdir(ext_dir)):
        fpath = os.path.join(ext_dir, fname)
        if os.path.isfile(fpath) and not fname.endswith(".uid"):
            arcname = "src/Extensions/EasyGradient/" + fname
            zf.write(fpath, arcname)
            print("  " + arcname)

    # Tool icons
    icons = [
        ("assets/graphics/tools/gradientline.png",
         os.path.join(base, "assets", "graphics", "tools", "gradientline.png")),
        ("assets/graphics/tools/cursors/gradientline.png",
         os.path.join(base, "assets", "graphics", "tools", "cursors", "gradientline.png")),
    ]
    for arcname, fpath in icons:
        if os.path.isfile(fpath):
            zf.write(fpath, arcname)
            print("  " + arcname)

print("\nBuilt " + output)
