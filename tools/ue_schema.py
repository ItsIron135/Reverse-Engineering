"""Recover UE 5.1 reflected property layouts from a shipped executable, and decode cooked
unversioned property data with them.

Cooked packages written with unversioned properties store fields by index into the class's
property list (derived class first, then each base class). The executable keeps the generated
reflection tables (FPropertyParamsBase* arrays), so each class's field order can be read back by
finding any one of its property names.
"""
import json
import struct
from pathlib import Path

TYPE_NAMES = {
    0: "Byte", 1: "Int8", 2: "Int16", 3: "Int", 4: "Int64", 5: "UInt16", 6: "UInt32", 7: "UInt64",
    10: "Float", 11: "Double", 12: "Bool", 13: "SoftClass", 14: "WeakObject", 15: "LazyObject",
    16: "SoftObject", 17: "Class", 18: "Object", 19: "Interface", 20: "Name", 21: "Str", 22: "Array",
    23: "Map", 24: "Set", 25: "Struct", 26: "Delegate", 27: "InlineMulticastDelegate",
    28: "SparseMulticastDelegate", 29: "Text", 30: "Enum", 31: "FieldPath", 32: "LargeWorldCoordinatesReal",
}


class Executable:
    def __init__(self, path):
        self.d = Path(path).read_bytes()
        d = self.d
        pe = struct.unpack_from("<I", d, 0x3C)[0]
        count = struct.unpack_from("<H", d, pe + 6)[0]
        opt = pe + 24
        size = struct.unpack_from("<H", d, pe + 20)[0]
        self.base = struct.unpack_from("<Q", d, opt + 24)[0]
        self.sections = []
        for i in range(count):
            o = opt + size + i * 40
            vs, va, rs, ro = struct.unpack_from("<IIII", d, o + 8)
            self.sections.append((va, rs, ro))

    def to_va(self, off):
        for va, rs, ro in self.sections:
            if ro <= off < ro + rs:
                return self.base + va + off - ro
        return None

    def to_off(self, a):
        for va, rs, ro in self.sections:
            if self.base + va <= a < self.base + va + rs:
                return ro + a - self.base - va
        return None

    def cstr(self, a):
        o = self.to_off(a)
        if o is None:
            return None
        e = self.d.find(b"\0", o, o + 200)
        if e < 0:
            return None
        try:
            s = self.d[o:e].decode()
        except UnicodeDecodeError:
            return None
        return s if s and all(32 <= ord(c) < 127 for c in s) else None

    def descriptor(self, a):
        d = self.d
        o = self.to_off(a)
        if o is None or o + 64 > len(d):
            return None
        name = self.cstr(struct.unpack_from("<Q", d, o)[0])
        flags_type = struct.unpack_from("<I", d, o + 24)[0]
        if not name or flags_type > 127 or struct.unpack_from("<I", d, o + 28)[0] != 0x45:
            return None
        return {"name": name, "type": flags_type & 0x3F, "dim": struct.unpack_from("<I", d, o + 32)[0], "va": a}

    def hits(self, pattern):
        cur, out = 0, []
        while True:
            k = self.d.find(pattern, cur)
            if k < 0:
                return out
            out.append(k)
            cur = k + 1

    def tables_with(self, prop_name):
        """Every reflected property table containing a property with this name."""
        d = self.d
        tables = []
        for so in self.hits(prop_name.encode() + b"\0"):
            if d[so - 1] != 0:
                continue
            for ref in self.hits(struct.pack("<Q", self.to_va(so))):
                if not self.descriptor(self.to_va(ref)):
                    continue
                for use in self.hits(struct.pack("<Q", self.to_va(ref))):
                    if use % 8:
                        continue
                    lo = hi = use
                    while lo >= 8 and self.descriptor(struct.unpack_from("<Q", d, lo - 8)[0]):
                        lo -= 8
                    while self.descriptor(struct.unpack_from("<Q", d, hi + 8)[0]):
                        hi += 8
                    table = [self.descriptor(struct.unpack_from("<Q", d, q)[0]) for q in range(lo, hi + 1, 8)]
                    if table not in tables:
                        tables.append(table)
        return tables

    def class_fields(self, seed, must_contain=()):
        """Serialized field list (enum helper entries dropped, static arrays expanded)."""
        for table in self.tables_with(seed):
            names = {p["name"] for p in table}
            if all(m in names for m in must_contain):
                fields = []
                for i, p in enumerate(table):
                    if p["name"] == "UnderlyingType":
                        continue
                    # Array/Set/Map inner (key/value) descriptors share the container's name
                    nxt = table[i + 1] if i + 1 < len(table) else None
                    if nxt and nxt["name"] == p["name"] and p["type"] not in (22, 23, 24):
                        continue
                    for k in range(max(1, p["dim"])):
                        fields.append({"name": p["name"] + (f"[{k}]" if p["dim"] > 1 else ""), "type": p["type"]})
                return fields
        raise LookupError(seed)


def unversioned_header(data, pos=0):
    """Returns ([(field_index, is_zero)], new_pos)."""
    fragments = []
    while True:
        packed = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        skip, zeros, last, values = packed & 0x7F, bool(packed & 0x80), bool(packed & 0x100), packed >> 9
        fragments.append((skip, zeros, values))
        if last:
            break
    zero_count = sum(v for _, z, v in fragments if z)
    mask_bits = []
    if zero_count:
        nbytes = 1 if zero_count <= 8 else 2 if zero_count <= 16 else ((zero_count + 31) // 32) * 4
        mask = int.from_bytes(data[pos:pos + nbytes], "little")
        pos += nbytes
        mask_bits = [bool(mask >> i & 1) for i in range(zero_count)]
    fields, index, zi = [], 0, 0
    for skip, zeros, values in fragments:
        index += skip
        for _ in range(values):
            is_zero = False
            if zeros:
                is_zero = mask_bits[zi]
                zi += 1
            fields.append((index, is_zero))
            index += 1
    return fields, pos


# Native structs that cook as raw bytes (no unversioned header)
RAW_STRUCTS = {
    "Vector": ("<ddd", 24), "Rotator": ("<ddd", 24), "Vector4": ("<dddd", 32), "Quat": ("<dddd", 32),
    "LinearColor": ("<ffff", 16), "Color": ("<BBBB", 4), "Guid": ("<IIII", 16), "Vector2D": ("<dd", 16),
    "IntPoint": ("<ii", 8), "Box": ("<ddddddB", 49),
}


def decode(data, fields, pos=0, struct_types=None, names=None, imports=None, stop_unknown=True,
           schemas=None, arrays=None):
    """Decode one unversioned property block.

    struct_types maps field name -> raw struct kind (RAW_STRUCTS) or "schema:<key>" for a nested
    unversioned struct whose field list is schemas[key]. arrays maps field name -> "object" or
    "schema:<key>" for the element type.
    """
    struct_types = struct_types or {}
    schemas = schemas or {}
    arrays = arrays or {}
    header, pos = unversioned_header(data, pos)
    out = {}
    for index, zero in header:
        f = fields[index]
        name, typ = f["name"], f["type"]
        base = name.split("[")[0]
        if zero:
            out[name] = 0
            continue
        kind = struct_types.get(base, "")
        if typ == 25 and kind.startswith("schema:"):
            out[name], pos = decode(data, schemas[kind[7:]], pos, struct_types, names, imports, stop_unknown, schemas, arrays)
            if isinstance(out[name], dict) and "__stopped_at" in out[name]:
                out["__stopped_at"] = out[name]["__stopped_at"]
                return out, pos
            continue
        if typ == 22 and base in arrays:
            count = struct.unpack_from("<i", data, pos)[0]
            pos += 4
            items = []
            for _ in range(count):
                if arrays[base] == "object":
                    items.append(struct.unpack_from("<i", data, pos)[0])
                    pos += 4
                elif arrays[base] == "int8":
                    items.append(data[pos])
                    pos += 1
                else:
                    item, pos = decode(data, schemas[arrays[base][7:]], pos, struct_types, names, imports, stop_unknown, schemas, arrays)
                    items.append(item)
            out[name] = items
            continue
        if typ == 12:
            out[name] = bool(data[pos]); pos += 1
        elif typ == 10:
            out[name] = struct.unpack_from("<f", data, pos)[0]; pos += 4
        elif typ in (11, 32):
            out[name] = struct.unpack_from("<d", data, pos)[0]; pos += 8
        elif typ in (3, 6):
            out[name] = struct.unpack_from("<i", data, pos)[0]; pos += 4
        elif typ in (0, 30):
            out[name] = data[pos]; pos += 1
        elif typ == 15:
            out[name] = data[pos:pos + 16].hex(); pos += 16
        elif typ in (17, 18, 14):
            out[name] = struct.unpack_from("<i", data, pos)[0]; pos += 4
        elif typ == 20:
            a, b = struct.unpack_from("<ii", data, pos); pos += 8
            out[name] = (names[a] if names else a, b)
        elif typ == 25 and struct_types.get(name.split("[")[0]) in RAW_STRUCTS:
            fmt, size = RAW_STRUCTS[struct_types[name.split("[")[0]]]
            out[name] = struct.unpack_from(fmt, data, pos); pos += size
        else:
            out[name] = f"<undecoded {TYPE_NAMES.get(typ, typ)} at {pos}>"
            if stop_unknown:
                out["__stopped_at"] = pos
                return out, pos
    return out, pos


def main():
    import sys
    exe = Executable(sys.argv[1])
    seed = sys.argv[2]
    must = sys.argv[3:]
    print(json.dumps(exe.class_fields(seed, must), indent=1))


if __name__ == "__main__":
    main()
