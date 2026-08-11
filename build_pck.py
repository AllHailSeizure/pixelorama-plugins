import struct, hashlib, os

def build_pck(output_path, files_dict, engine_major=4, engine_minor=6, engine_patch=3, pack_version=3):
    MAGIC = b"GDPC"
    RESERVED = b"\x00" * (16 * 4)

    file_entries = []
    for res_path, local_path in sorted(files_dict.items()):
        with open(local_path, "rb") as f:
            data = f.read()
        md5 = hashlib.md5(data).digest()
        file_entries.append((res_path, data, md5))

    header = MAGIC
    header += struct.pack("<I", pack_version)
    header += struct.pack("<I", engine_major)
    header += struct.pack("<I", engine_minor)
    header += struct.pack("<I", engine_patch)
    header += struct.pack("<I", 0)  # flags
    header += struct.pack("<q", 0)  # files_base
    header += RESERVED
    header += struct.pack("<I", len(file_entries))

    table_size = 0
    for res_path, data, md5 in file_entries:
        path_bytes = res_path.encode("utf-8") + b"\x00"
        padded_len = (len(path_bytes) + 3) & ~3
        table_size += 4 + padded_len + 8 + 8 + 16 + 4

    data_offset = len(header) + table_size
    data_offset = (data_offset + 63) & ~63

    table = b""
    current_offset = data_offset
    data_blobs = []
    for res_path, data, md5 in file_entries:
        path_bytes = res_path.encode("utf-8") + b"\x00"
        padded_len = (len(path_bytes) + 3) & ~3
        table += struct.pack("<I", padded_len)
        table += path_bytes + b"\x00" * (padded_len - len(path_bytes))
        table += struct.pack("<q", current_offset)
        table += struct.pack("<q", len(data))
        table += md5
        table += struct.pack("<I", 0)  # flags
        data_blobs.append(data)
        current_offset += len(data)
        padding = (64 - (current_offset % 64)) % 64
        current_offset += padding

    with open(output_path, "wb") as f:
        f.write(header)
        f.write(table)
        current_pos = len(header) + len(table)
        if current_pos < data_offset:
            f.write(b"\x00" * (data_offset - current_pos))
        for i, data in enumerate(data_blobs):
            f.write(data)
            if i < len(data_blobs) - 1:
                padding = (64 - (f.tell() % 64)) % 64
                f.write(b"\x00" * padding)

    print(f"Built {output_path} with {len(file_entries)} files")


base = r"D:\Libraries\Synapse\Pixelorama\TileTools\src\Extensions\TileTools"
files = {}
for fname in os.listdir(base):
    fpath = os.path.join(base, fname)
    if os.path.isfile(fpath) and not fname.endswith(".uid"):
        res_path = f"res://src/Extensions/TileTools/{fname}"
        files[res_path] = fpath
        print(f"  {res_path} <- {fname}")

output = r"D:\Libraries\Synapse\Pixelorama\TileTools.pck"
build_pck(output, files)
