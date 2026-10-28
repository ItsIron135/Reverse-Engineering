"""Minimal reader for legacy (retoc-converted) UE 5.1 .uasset/.umap + .uexp pairs:
name map, imports and exports, plus helpers to resolve object references."""
import struct
from pathlib import Path


class Package:
    def __init__(self, path):
        path = Path(path)
        d = path.read_bytes()
        self.path = path
        i32 = lambda o: struct.unpack_from("<i", d, o)[0]
        o = 36 + abs(i32(32)) * (2 if i32(32) < 0 else 1)
        name_count, name_offset = i32(o + 4), i32(o + 8)
        export_count, export_offset, import_count, import_offset = i32(o + 28), i32(o + 32), i32(o + 36), i32(o + 40)
        self.names = []
        q = name_offset
        for _ in range(name_count):
            n = i32(q)
            q += 4
            size = abs(n) * (2 if n < 0 else 1)
            self.names.append(d[q:q + size].decode("utf-16-le" if n < 0 else "utf-8").rstrip("\0"))
            q += size + 4

        def fname(q):
            n, number = struct.unpack_from("<ii", d, q)
            return self.names[n] + (f"_{number - 1}" if number else "")

        self.imports = []
        for k in range(import_count):
            q = import_offset + k * 32
            self.imports.append({"class": fname(q + 8), "outer": i32(q + 16), "name": fname(q + 20)})
        self.raw = path.with_suffix(".uexp").read_bytes()
        self.exports = []
        for k in range(export_count):
            q = export_offset + k * 96
            cls, super_, template, outer = struct.unpack_from("<iiii", d, q)
            size, offset = struct.unpack_from("<qq", d, q + 28)
            self.exports.append({"index": k + 1, "name": fname(q + 16), "class": cls, "outer": outer,
                                 "size": size, "start": offset - len(d)})

    def class_name(self, export):
        c = export["class"]
        return self.imports[-c - 1]["name"] if c < 0 else self.exports[c - 1]["name"]

    def data(self, export):
        return self.raw[export["start"]:export["start"] + export["size"]]

    def ref_path(self, index):
        """Package path of an object reference (negative = import)."""
        if index == 0:
            return None
        if index > 0:
            return "export:" + self.exports[index - 1]["name"]
        imp = self.imports[-index - 1]
        parts = [imp["name"]]
        outer = imp["outer"]
        while outer < 0:
            parts.append(self.imports[-outer - 1]["name"])
            outer = self.imports[-outer - 1]["outer"]
        return "/".join(reversed(parts))
