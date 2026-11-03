"""Read-only Rex IPA interoperability probe; writes a small JSON evidence file.

Usage: python tool/rex/inspect_ipa.py INPUT.ipa --output OUTPUT.json
Only the standard library is required. No app or bundled script is executed.
"""

from __future__ import annotations

import argparse
import base64
import bisect
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import zipfile


class MachO:
    def __init__(self, data: bytes):
        self.data = data
        if data[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError("Expected a thin little-endian 64-bit Mach-O")
        self.sections: list[dict] = []
        self.dylibs: list[str] = []
        self.symbols: list[str] = []
        self.imports: list[str] = []
        self.encryption: list[dict] = []
        self.starts: list[int] = []
        self.stubs: dict[int, str] = {}
        ncmds = struct.unpack_from("<I", data, 16)[0]
        off = 32
        commands = []
        base = None
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", data, off)
            if size < 8 or off + size > len(data):
                raise ValueError("Invalid Mach-O load command")
            commands.append((cmd, off))
            if cmd == 0x19:  # LC_SEGMENT_64
                seg = self.cstring(off + 8, 16)
                vmaddr, _, fileoff, _ = struct.unpack_from("<QQQQ", data, off + 24)
                if seg == "__TEXT":
                    base = vmaddr - fileoff
                count = struct.unpack_from("<I", data, off + 64)[0]
                for j in range(count):
                    s = off + 72 + j * 80
                    addr, length, file_offset = struct.unpack_from("<QQI", data, s + 32)
                    flags, first, stride = struct.unpack_from("<III", data, s + 64)
                    self.sections.append(dict(
                        name=self.cstring(s, 16), segment=seg, addr=addr,
                        size=length, offset=file_offset, flags=flags,
                        indirect_start=first, stub_stride=stride,
                    ))
            elif cmd in (0x21, 0x2C):
                cryptoff, cryptsize, cryptid = struct.unpack_from("<III", data, off + 8)
                self.encryption.append(dict(offset=cryptoff, size=cryptsize, cryptid=cryptid))
            elif cmd in (0xC, 0x18, 0x1F, 0x80000018, 0x8000001F):
                name_offset = struct.unpack_from("<I", data, off + 8)[0]
                self.dylibs.append(self.cstring(off + name_offset, size - name_offset))
            off += size
        indirect = []
        for cmd, off in commands:
            if cmd == 2:  # LC_SYMTAB
                symoff, count, stroff, strsize = struct.unpack_from("<IIII", data, off + 8)
                for j in range(count):
                    index, kind, _, _, _ = struct.unpack_from("<IBBHQ", data, symoff + j * 16)
                    name = self.cstring(stroff + index, strsize - index)
                    self.symbols.append(name)
                    if kind & 0xE == 0:
                        self.imports.append(name)
            elif cmd == 0xB:  # LC_DYSYMTAB
                table_offset, count = struct.unpack_from("<II", data, off + 56)
                indirect = struct.unpack_from(f"<{count}I", data, table_offset)
            elif cmd == 0x26 and base is not None:  # LC_FUNCTION_STARTS
                file_offset, size = struct.unpack_from("<II", data, off + 8)
                addr = base
                value = shift = 0
                for item in data[file_offset:file_offset + size]:
                    value |= (item & 127) << shift
                    if item & 128:
                        shift += 7
                    else:
                        if not value:
                            break
                        addr += value
                        self.starts.append(addr)
                        value = shift = 0
        for sec in self.sections:
            if sec["flags"] & 255 != 8 or not sec["stub_stride"]:
                continue  # S_SYMBOL_STUBS
            for i in range(sec["size"] // sec["stub_stride"]):
                slot = sec["indirect_start"] + i
                if slot < len(indirect) and indirect[slot] < len(self.symbols):
                    self.stubs[sec["addr"] + i * sec["stub_stride"]] = self.symbols[indirect[slot]]

    def cstring(self, off: int, limit: int) -> str:
        return self.data[off:off + max(0, limit)].split(b"\0", 1)[0].decode("utf-8", "replace")

    def at(self, addr: int, size: int) -> bytes:
        for sec in self.sections:
            if sec["addr"] <= addr < sec["addr"] + sec["size"]:
                off = sec["offset"] + addr - sec["addr"]
                return self.data[off:off + size]
        return b""

    def relative(self, addr: int) -> int:
        data = self.at(addr, 4)
        return addr + struct.unpack("<i", data)[0] if len(data) == 4 else 0

    def string_at(self, addr: int) -> str:
        return self.at(addr, 1024).split(b"\0", 1)[0].decode("utf-8", "replace")

    def function(self, addr: int) -> str:
        index = bisect.bisect_right(self.starts, addr) - 1
        return hex(self.starts[index]) if index >= 0 else hex(addr)

    def strings(self):
        for sec in self.sections:
            if sec["name"] not in ("__cstring", "__swift5_reflstr"):
                continue
            data = self.data[sec["offset"]:sec["offset"] + sec["size"]]
            for match in re.finditer(rb"[^\0]+", data):
                yield sec["addr"] + match.start(), match.group().decode("utf-8", "replace")

    def types(self):
        result = []
        wanted = {
            "ScriptJavaScriptRuntime", "ScriptEngineHub", "ScriptModuleCrypto",
            "ScriptContentKeyStore", "ScriptKeySessionClient", "ScriptStorageBridge",
            "ScriptModuleEngine", "ScriptSharedStorageRegistry", "ScriptLocalStorageRegistry",
        }
        for sec in self.sections:
            if sec["name"] != "__swift5_types":
                continue
            for addr in range(sec["addr"], sec["addr"] + sec["size"], 4):
                desc = self.relative(addr)
                name = self.string_at(self.relative(desc + 8))
                if name not in wanted:
                    continue
                fields = []
                fd = self.relative(desc + 16)
                header = self.at(fd, 16)
                if len(header) == 16:
                    stride, count = struct.unpack_from("<HI", header, 10)
                    if stride >= 12 and count < 100:
                        fields = [self.string_at(self.relative(fd + 16 + i * stride + 8)) for i in range(count)]
                result.append(dict(name=name, descriptor=hex(desc), fields=fields))
        return result

    def anchors(self):
        needles = (
            "/api/widgets/key-session", "key_session.begin", "key_session.success",
            "Content key unavailable", "Invalid encrypted payload",
            "Unsupported module encryption; re-encrypt for Rex", "Decryption failed (",
        )
        anchors = {addr: text for addr, text in self.strings() if text in needles}
        refs = []
        for sec in self.sections:
            if sec["name"] != "__text":
                continue
            data = self.data[sec["offset"]:sec["offset"] + sec["size"]]
            for off in range(0, len(data) - 3, 4):
                word = struct.unpack_from("<I", data, off)[0]
                addr = sec["addr"] + off
                if word & 0xFC000000 == 0x94000000:  # BL imm26
                    imm = word & 0x3FFFFFF
                    if imm & 0x2000000:
                        imm -= 0x4000000
                    target = addr + 4 * imm
                    symbol = self.stubs.get(target, "")
                    if "CryptoKit3AESO3GCMO4open" in symbol:
                        refs.append(dict(address=hex(addr), function=self.function(addr), target=hex(target), symbol=symbol))
                elif word & 0x9F000000 == 0x90000000:  # ADRP + nearby ADD
                    imm = ((word >> 29) & 3) | (((word >> 5) & 0x7FFFF) << 2)
                    if imm & 0x100000:
                        imm -= 0x200000
                    page = (addr & ~4095) + imm * 4096
                    if not any(target & ~4095 == page for target in anchors):
                        continue
                    reg = word & 31
                    for j in range(off + 4, min(off + 32, len(data) - 3), 4):
                        nxt = struct.unpack_from("<I", data, j)[0]
                        if nxt & 0x7F000000 != 0x11000000 or (nxt >> 5) & 31 != reg:
                            continue
                        delta = (nxt >> 10) & 4095
                        if nxt & (1 << 22):
                            delta <<= 12
                        target = page + delta
                        if target in anchors:
                            refs.append(dict(address=hex(sec["addr"] + j), function=self.function(addr), target=hex(target), text=anchors[target]))
        return dict(strings=[dict(address=hex(a), text=t) for a, t in anchors.items()], references=refs)


def inspect(path: Path) -> dict:
    with path.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    with zipfile.ZipFile(path) as archive:
        candidates = [n for n in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(candidates) != 1:
            raise ValueError("Expected exactly one top-level iOS app")
        info = plistlib.loads(archive.read(candidates[0]))
        prefix = candidates[0].rsplit("/", 1)[0] + "/"
        binary_path = prefix + info["CFBundleExecutable"]
        if archive.getinfo(binary_path).file_size > 256 * 1024 * 1024:
            raise ValueError("Executable exceeds probe limit (256 MiB)")
        binary = archive.read(binary_path)
        macho = MachO(binary)
        methods = set()
        for _, text in macho.strings():
            methods.update(re.findall(r"Widget\.call(?:Sync|Async)\(['\"]([^'\"]+)['\"]", text))
        resources = []
        for entry in archive.infolist():
            if entry.filename.startswith(prefix) and "RexScript_RexScript.bundle/" in entry.filename and not entry.is_dir():
                data = archive.read(entry)
                resources.append(dict(path=entry.filename[len(prefix):], bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
        imports = {kind: [n for n in macho.imports if re.search(pattern, n)] for kind, pattern in {
            "javascript": r"OBJC_CLASS_\$_JS(Context|Value)$",
            "crypto": r"CryptoKit3AESO3GCM|CryptoKit12SymmetricKey|^_CCCrypt",
            "keychain": r"^_SecItem",
            "network": r"OBJC_CLASS_\$_NSURLSession$",
        }.items()}
        dylibs = []
        for entry in archive.infolist():
            if entry.filename.startswith(prefix) and entry.filename.endswith(".dylib"):
                data = archive.read(entry)
                dylibs.append(dict(path=entry.filename[len(prefix):], bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
        return dict(
            format="lume.rex-ipa-evidence.v1", ipa_bytes=path.stat().st_size, ipa_sha256=digest,
            app={key: info.get(key) for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion")},
            executable=dict(bytes=len(binary), sha256=hashlib.sha256(binary).hexdigest(), encryption=macho.encryption),
            imports=imports, dependencies=[n for n in macho.dylibs if re.search("JavaScriptCore|CryptoKit|Security|hwpatch", n)],
            swift_types=macho.types(), widget_bridge_methods=sorted(methods),
            resources=resources, extra_dylibs=dylibs, anchors=macho.anchors(),
            limits=["Static inspection only; no app execution, decryption, service request or playback verification.", "ADRP references are candidates; function naming and complete call flow require disassembly review."],
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--module", type=Path, action="append", default=[])
    args = parser.parse_args()
    if args.output.resolve() in {p.resolve() for p in [args.ipa, *args.module]}:
        parser.error("Output must differ from the inputs")
    result = inspect(args.ipa)
    samples = []
    for path in args.module:
        data = path.read_bytes()
        lines = data.decode("utf-8-sig").strip().splitlines()
        if len(lines) != 3 or lines[0] not in ("REXENC", "FWENC"):
            raise ValueError(f"Not a three-line encrypted widget: {path.name}")
        header = json.loads(lines[1])
        samples.append(dict(
            file=path.name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
            marker=lines[0], header={k: header.get(k) for k in ("v", "mkv", "alg")},
            iv_bytes=len(base64.b64decode(header["iv"], validate=True)),
            kb_bytes=len(base64.b64decode(header["kb"], validate=True)),
            ciphertext_and_tag_bytes=len(base64.b64decode(lines[2], validate=True)),
            decrypted=False,
        ))
    result["module_samples"] = samples
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"output": str(args.output), "ipa_sha256": result["ipa_sha256"], "bridge_methods": len(result["widget_bridge_methods"]), "resources": len(result["resources"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
