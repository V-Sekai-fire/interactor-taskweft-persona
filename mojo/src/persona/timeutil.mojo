# SPDX-License-Identifier: MIT
# Planner/Iso8601Duration.lean (the parser, reduced to the seconds it gives)
# and the datestamp helpers of Persona/Jsonld.lean.
#
# A Lean `Nat` subtraction stops at zero; `monus` is that.


def monus(a: Int, b: Int) -> Int:
    return a - b if a > b else 0


def _digit(b: UInt8) -> Bool:
    return b >= 48 and b <= 57


def _unit_ms(u: Int) -> Int:
    # 0 Y, 1 Mo, 2 W, 3 D, 4 H, 5 Mi, 6 S
    if u == 0:
        return 365 * 86400 * 1000
    if u == 1:
        return 30 * 86400 * 1000
    if u == 2:
        return 7 * 86400 * 1000
    if u == 3:
        return 86400 * 1000
    if u == 4:
        return 3600 * 1000
    if u == 5:
        return 60 * 1000
    return 1000


def parse_duration(s: String, mut seconds: Int) -> Bool:
    """ISO-8601 durations in the order the Lean grammar allows, as whole
    seconds. False for every reject reason."""
    var b = s.as_bytes()
    var n = len(b)
    if n == 0 or b[0] != 80:  # 'P'
        return False
    seconds = 0
    if n == 1:
        return True
    var pos = 1
    var in_time = False
    var saw_t = False
    var saw_w = False
    var any_part = False
    var last_rank = -1
    var frac_seen = False
    var total_ms = 0
    while pos < n:
        if frac_seen:
            return False
        if b[pos] == 84:  # 'T'
            if saw_t or pos + 1 == n:
                return False
            in_time = True
            saw_t = True
            pos += 1
            continue
        if not _digit(b[pos]):
            return False
        var whole = 0
        var i = pos
        while i < n and _digit(b[i]):
            whole = whole * 10 + Int(b[i]) - 48
            i += 1
        var milli = 0
        if i < n and b[i] == 46:  # '.'
            if i + 1 >= n or not _digit(b[i + 1]):
                return False
            i += 1
            var cnt = 0
            var acc = 0
            while i < n and _digit(b[i]) and cnt < 3:
                acc = acc * 10 + Int(b[i]) - 48
                cnt += 1
                i += 1
            for _ in range(3 - cnt):
                acc *= 10
            milli = acc
        if i >= n:
            return False  # a number with no unit
        var c = b[i]
        pos = i + 1
        if c == 87 and (any_part or in_time):  # 'W'
            return False
        if saw_w:
            return False
        var unit = -1
        var rank = 0
        if not in_time:
            if c == 89:  # Y
                unit = 0
                rank = 0
            elif c == 77:  # M
                unit = 1
                rank = 1
            elif c == 87:  # W
                unit = 2
                rank = 99
            elif c == 68:  # D
                unit = 3
                rank = 2
        else:
            if c == 72:  # H
                unit = 4
                rank = 3
            elif c == 77:  # M
                unit = 5
                rank = 4
            elif c == 83:  # S
                unit = 6
                rank = 5
        if unit < 0:
            return False
        if rank <= last_rank:
            return False
        if unit == 2:
            saw_w = True
        any_part = True
        last_rank = rank
        frac_seen = milli != 0
        total_ms += whole * _unit_ms(unit) + milli * (_unit_ms(unit) // 1000)
    seconds = total_ms // 1000
    return True


def days_from_civil(y0: Int, m: Int, d: Int) -> Int:
    var y = y0 - 1 if m <= 2 else y0
    var era = y // 400
    var yoe = y - era * 400
    var mp = (m + 9) % 12
    var doy = (153 * mp + 2) // 5 + d - 1
    var doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468


def _num(b: Span[Byte, _], a: Int, e: Int, mut out: Int) -> Bool:
    out = 0
    for i in range(a, e):
        if not _digit(b[i]):
            return False
        out = out * 10 + Int(b[i]) - 48
    return True


def parse_stamp(s: String, mut seconds: Int) -> Bool:
    """`YYYY-MM-DDTHH:MM:SSZ` as seconds since the epoch."""
    var b = s.as_bytes()
    if len(b) != 20:
        return False
    var y = 0
    var mo = 0
    var d = 0
    var h = 0
    var mi = 0
    var se = 0
    if not (
        _num(b, 0, 4, y)
        and _num(b, 5, 7, mo)
        and _num(b, 8, 10, d)
        and _num(b, 11, 13, h)
        and _num(b, 14, 16, mi)
        and _num(b, 17, 19, se)
    ):
        return False
    if not (
        b[4] == 45
        and b[7] == 45
        and b[10] == 84
        and b[13] == 58
        and b[16] == 58
        and b[19] == 90
        and y >= 1970
        and 1 <= mo
        and mo <= 12
        and 1 <= d
        and d <= 31
        and h < 24
        and mi < 60
        and se < 60
    ):
        return False
    var days = days_from_civil(y, mo, d)
    seconds = (days if days > 0 else 0) * 86400 + h * 3600 + mi * 60 + se
    return True


def _pad(n: Int, w: Int) -> String:
    var t = String(n)
    var out = String()
    for _ in range(monus(w, t.byte_length())):
        out += "0"
    return out + t


def fmt_stamp(t: Int) -> String:
    var z = t // 86400 + 719468
    var era = z // 146097
    var doe = z - era * 146097
    var yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    var y = yoe + era * 400
    var doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    var mp = (5 * doy + 2) // 153
    var d = doy - (153 * mp + 2) // 5 + 1
    var m = mp + 3 if mp < 10 else mp - 9
    if m <= 2:
        y += 1
    return (
        _pad(y, 4) + "-" + _pad(m, 2) + "-" + _pad(d, 2) + "T"
        + _pad(t % 86400 // 3600, 2) + ":" + _pad(t % 3600 // 60, 2) + ":"
        + _pad(t % 60, 2) + "Z"
    )


def fmt_dur(s: Int) -> String:
    """Seconds as a canonical ISO-8601 duration: PT0S, P3D, P1DT2H30M."""
    var d = s // 86400
    var h = s % 86400 // 3600
    var m = s % 3600 // 60
    var x = s % 60
    if s == 0:
        return "PT0S"
    var out = String("P")
    if d > 0:
        out += String(d) + "D"
    if h + m + x > 0:
        out += "T"
        if h > 0:
            out += String(h) + "H"
        if m > 0:
            out += String(m) + "M"
        if x > 0:
            out += String(x) + "S"
    return out^
