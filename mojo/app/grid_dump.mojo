# One hex-encoded spec a line (`-` is empty) in, the planOf answer a line out.
from std.sys import argv
from persona.grid import plan_of


def hexval(b: UInt8) -> Int:
    if b >= 97:
        return Int(b) - 87
    return Int(b) - 48


def decode(h: String) raises -> String:
    var bytes = List[UInt8]()
    var hb = h.as_bytes()
    var i = 0
    while i + 1 < len(hb):
        bytes.append(UInt8(hexval(hb[i]) * 16 + hexval(hb[i + 1])))
        i += 2
    return String(from_utf8=bytes)


def main() raises:
    var path = String(argv()[1])
    var text: String
    with open(path, "r") as f:
        text = f.read()
    for ln in text.split("\n"):
        var l = String(ln)
        if l.byte_length() == 0:
            continue
        print(plan_of("" if l == "-" else decode(l)))
