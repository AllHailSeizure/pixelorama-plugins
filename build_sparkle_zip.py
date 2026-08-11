import os
import zipfile

base = r"D:\Libraries\Pixelorama\EasySparkle"
output = r"D:\Libraries\Pixelorama\EasySparkle.zip"

with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    extension_dir = os.path.join(base, "src", "Extensions", "EasySparkle")
    for filename in sorted(os.listdir(extension_dir)):
        path = os.path.join(extension_dir, filename)
        if os.path.isfile(path) and not filename.endswith(".uid"):
            archive_name = "src/Extensions/EasySparkle/" + filename
            archive.write(path, archive_name)
            print("  " + archive_name)

    icons = [
        (
            "assets/graphics/tools/easysparkle.png",
            os.path.join(base, "assets", "graphics", "tools", "easysparkle.png"),
        ),
        (
            "assets/graphics/tools/cursors/easysparkle.png",
            os.path.join(
                base, "assets", "graphics", "tools", "cursors", "easysparkle.png"
            ),
        ),
    ]
    for archive_name, path in icons:
        if os.path.isfile(path):
            archive.write(path, archive_name)
            print("  " + archive_name)

print("\nBuilt " + output)
