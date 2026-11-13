#!/usr/bin/env python3
"""Ассемблер для 16-битной ISA курсовой (см. docs/ISA.md и docs/ASM.md).

    python3 tools/asm.py asm/fib.asm -o build/fib

Создаёт:
    build/fib.rom.hex  — память команд для $readmemh (+rom=...)
    build/fib.ram.hex  — начальные данные RAM (+ram=...), 256 слов
    build/fib.lst      — листинг: адрес, машинное слово, исходная строка

Два прохода: первый раскладывает команды и данные по адресам и собирает
метки, второй кодирует. Ошибки печатаются с номером строки, код выхода 1.
"""
import argparse
import re
import sys

ROM_SIZE = 1024
RAM_SIZE = 256

OPCODES = {
    "ALU": 0x0, "ADDI": 0x1, "LW": 0x2, "SW": 0x3, "BEQ": 0x4, "BNE": 0x5,
    "BLT": 0x6, "JMP": 0x7, "JAL": 0x8, "JR": 0x9, "LUI": 0xA, "LLI": 0xB,
    "FONT_RENDER": 0xC, "HALT": 0xF,
}
FUNCT = {"ADD": 0, "SUB": 1, "AND": 2, "OR": 3, "XOR": 4, "NOT": 5,
         "SHL": 6, "SHR": 7}

# Размер псевдокоманд в словах (нужен на первом проходе)
PSEUDO_SIZE = {"LI": 2, "MOV": 1, "NOP": 1, "B": 1, "CALL": 1, "RET": 1,
               "INC": 1, "DEC": 1, "BEQZ": 1, "BNEZ": 1, "BGT": 1,
               "LBEQ": 2, "LBNE": 2, "LBLT": 3}


class AsmError(Exception):
    def __init__(self, line_no, msg):
        super().__init__(f"строка {line_no}: {msg}")
        self.line_no = line_no


# ----------------------------------------------------------------------
# Выражения: числа, символы, + - * / ( ), функции hi() и lo()
# ----------------------------------------------------------------------
TOKEN_RE = re.compile(r"\s*(0x[0-9a-fA-F]+|0b[01]+|\d+|'(?:\\.|[^'])'|"
                      r"[A-Za-z_.][A-Za-z0-9_.]*|[-+*/()])")


def char_value(tok):
    body = tok[1:-1]
    escapes = {"\\n": 10, "\\r": 13, "\\t": 9, "\\0": 0, "\\\\": 92, "\\'": 39}
    if body in escapes:
        return escapes[body]
    if len(body) != 1:
        raise ValueError(f"плохой символ {tok}")
    return ord(body)


def evaluate(text, symbols, line_no, allow_undefined=False):
    tokens = []
    pos = 0
    text = text.strip()
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m or m.end() == pos:
            raise AsmError(line_no, f"не разобрать выражение «{text}»")
        tokens.append(m.group(1))
        pos = m.end()
        while pos < len(text) and text[pos].isspace():
            pos += 1
    if not tokens:
        raise AsmError(line_no, "пустое выражение")
    idx = [0]

    def peek():
        return tokens[idx[0]] if idx[0] < len(tokens) else None

    def take():
        tok = peek()
        idx[0] += 1
        return tok

    def atom():
        tok = take()
        if tok is None:
            raise AsmError(line_no, f"выражение оборвано: «{text}»")
        if tok == "-":
            return -atom()
        if tok == "+":
            return atom()
        if tok == "(":
            v = expr()
            if take() != ")":
                raise AsmError(line_no, f"нет закрывающей скобки: «{text}»")
            return v
        if tok.lower() in ("hi", "lo") and peek() == "(":
            take()
            v = expr()
            if take() != ")":
                raise AsmError(line_no, f"нет закрывающей скобки: «{text}»")
            v &= 0xFFFF
            return (v >> 8) if tok.lower() == "hi" else (v & 0xFF)
        if tok.startswith("0x"):
            return int(tok, 16)
        if tok.startswith("0b"):
            return int(tok[2:], 2)
        if tok.isdigit():
            return int(tok)
        if tok.startswith("'"):
            try:
                return char_value(tok)
            except ValueError as e:
                raise AsmError(line_no, str(e))
        key = tok.upper()
        if key in symbols:
            return symbols[key]
        if allow_undefined:
            return 0
        raise AsmError(line_no, f"неизвестная метка или константа «{tok}»")

    def term():
        v = atom()
        while peek() in ("*", "/"):
            op = take()
            r = atom()
            v = v * r if op == "*" else v // r
        return v

    def expr():
        v = term()
        while peek() in ("+", "-"):
            op = take()
            r = term()
            v = v + r if op == "+" else v - r
        return v

    value = expr()
    if peek() is not None:
        raise AsmError(line_no, f"лишнее в выражении: «{text}»")
    return value


# ----------------------------------------------------------------------
# Разбор строк
# ----------------------------------------------------------------------
def strip_comment(line):
    out = []
    in_str = in_chr = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == "\\" and (in_str or in_chr):
            out.append(line[i:i + 2])
            i += 2
            continue
        if ch == '"' and not in_chr:
            in_str = not in_str
        elif ch == "'" and not in_str:
            in_chr = not in_chr
        elif not in_str and not in_chr and (ch == ";" or line.startswith("//", i)):
            break
        out.append(ch)
        i += 1
    return "".join(out).strip()


def split_operands(text):
    """Делит по запятым вне кавычек."""
    parts, cur, in_str, in_chr = [], [], False, False
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and (in_str or in_chr):
            cur.append(text[i:i + 2])
            i += 2
            continue
        if ch == '"' and not in_chr:
            in_str = not in_str
        elif ch == "'" and not in_str:
            in_chr = not in_chr
        if ch == "," and not in_str and not in_chr:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    parts.append("".join(cur).strip())
    return [p for p in parts if p]


def parse_string(text, line_no):
    text = text.strip()
    if len(text) < 2 or text[0] != '"' or text[-1] != '"':
        raise AsmError(line_no, f"ожидалась строка в кавычках: {text}")
    body = text[1:-1]
    out, i = [], 0
    escapes = {"n": 10, "r": 13, "t": 9, "0": 0, "\\": 92, '"': 34}
    while i < len(body):
        if body[i] == "\\" and i + 1 < len(body):
            if body[i + 1] not in escapes:
                raise AsmError(line_no, f"неизвестная escape-последовательность \\{body[i+1]}")
            out.append(escapes[body[i + 1]])
            i += 2
        else:
            out.append(ord(body[i]))
            i += 1
    return out


def reg(text, line_no):
    m = re.fullmatch(r"[Rr]([0-7])", text.strip())
    if not m:
        raise AsmError(line_no, f"ожидался регистр R0..R7, а не «{text}»")
    return int(m.group(1))


class Item:
    """Одна команда или блок данных, привязанный к адресу."""
    def __init__(self, line_no, src, section, addr, mnem, ops, size):
        self.line_no, self.src, self.section = line_no, src, section
        self.addr, self.mnem, self.ops, self.size = addr, mnem, ops, size


class Assembler:
    def __init__(self):
        self.symbols = {}
        self.items = []
        self.rom = {}
        self.ram = {}

    # ---------------- проход 1 ----------------
    def pass1(self, lines):
        section = "text"
        loc = {"text": 0, "data": 0}
        for line_no, raw in enumerate(lines, 1):
            line = strip_comment(raw)
            while True:
                m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*:(.*)$", line)
                if not m:
                    break
                name = m.group(1).upper()
                if name in self.symbols:
                    raise AsmError(line_no, f"метка «{m.group(1)}» уже определена")
                self.symbols[name] = loc[section]
                line = m.group(2).strip()
            if not line:
                continue
            parts = line.split(None, 1)
            mnem = parts[0].upper()
            ops = split_operands(parts[1]) if len(parts) > 1 else []

            if mnem == ".TEXT":
                section = "text"
                continue
            if mnem == ".DATA":
                section = "data"
                continue
            if mnem == ".ORG":
                self.need(ops, 1, line_no, mnem)
                loc[section] = evaluate(ops[0], self.symbols, line_no)
                continue
            if mnem == ".EQU":
                self.need(ops, 2, line_no, mnem)
                name = ops[0].strip().upper()
                if name in self.symbols:
                    raise AsmError(line_no, f"константа «{ops[0]}» уже определена")
                self.symbols[name] = evaluate(ops[1], self.symbols, line_no)
                continue

            if mnem == ".WORD":
                size = len(ops)
                if size == 0:
                    raise AsmError(line_no, ".word без значений")
            elif mnem == ".STRING":
                self.need(ops, 1, line_no, mnem)
                size = len(parse_string(ops[0], line_no))
            elif mnem == ".SPACE":
                self.need(ops, 1, line_no, mnem)
                size = evaluate(ops[0], self.symbols, line_no)
            elif mnem.startswith("."):
                raise AsmError(line_no, f"неизвестная директива {parts[0]}")
            else:
                if section != "text":
                    raise AsmError(line_no, "команда в секции .data")
                if mnem in PSEUDO_SIZE:
                    size = PSEUDO_SIZE[mnem]
                elif mnem in OPCODES or mnem in FUNCT or mnem == "FONT":
                    size = 1
                else:
                    raise AsmError(line_no, f"неизвестная команда «{parts[0]}»")
            self.items.append(Item(line_no, raw.rstrip(), section,
                                   loc[section], mnem, ops, size))
            loc[section] += size
        if loc["text"] > ROM_SIZE:
            raise AsmError(len(lines), f"программа не влезает в ROM ({loc['text']} > {ROM_SIZE})")
        if loc["data"] > RAM_SIZE:
            raise AsmError(len(lines), f"данные не влезают в RAM ({loc['data']} > {RAM_SIZE})")

    @staticmethod
    def need(ops, n, line_no, mnem):
        if len(ops) != n:
            raise AsmError(line_no, f"{mnem}: нужно операндов {n}, указано {len(ops)}")

    # ---------------- проход 2 ----------------
    def ev(self, text, line_no):
        return evaluate(text, self.symbols, line_no)

    def imm_range(self, v, lo, hi, line_no, what):
        if not lo <= v <= hi:
            raise AsmError(line_no, f"{what} {v} вне диапазона {lo}..{hi}")
        return v

    def enc_r(self, op, rd, rs1, rs2, funct):
        return (op << 12) | (rd << 9) | (rs1 << 6) | (rs2 << 3) | funct

    def enc_i(self, op, rd, rs1, imm, line_no, what="константа"):
        self.imm_range(imm, -32, 31, line_no, what)
        return (op << 12) | (rd << 9) | (rs1 << 6) | (imm & 0x3F)

    def enc_u(self, op, rd, imm, line_no):
        if not -128 <= imm <= 255:
            raise AsmError(line_no, f"8-битная константа {imm} вне диапазона")
        return (op << 12) | (rd << 9) | (imm & 0xFF)

    def enc_j(self, op, addr, line_no):
        self.imm_range(addr, 0, ROM_SIZE - 1, line_no, "адрес перехода")
        return (op << 12) | addr

    def mem_operand(self, text, line_no):
        m = re.fullmatch(r"(.*)\(\s*([Rr][0-7])\s*\)", text.strip())
        if m:
            off = m.group(1).strip()
            return reg(m.group(2), line_no), (self.ev(off, line_no) if off else 0)
        return 0, self.ev(text, line_no)          # абсолютный адрес: imm(R0)

    def branch(self, op, ra, rb, target, item):
        off = self.ev(target, item.line_no) - (item.addr + 1)
        return self.enc_i(op, ra, rb, off, item.line_no, "смещение перехода")

    def encode(self, item):
        m, ops, ln = item.mnem, item.ops, item.line_no
        n = lambda k: self.need(ops, k, ln, m)
        R = lambda i: reg(ops[i], ln)

        if m in FUNCT and m != "NOT":
            n(3)
            return [self.enc_r(0, R(0), R(1), R(2), FUNCT[m])]
        if m == "NOT":
            n(2)
            return [self.enc_r(0, R(0), R(1), 0, FUNCT["NOT"])]
        if m in ("FONT_RENDER", "FONT"):
            n(3)
            return [self.enc_r(OPCODES["FONT_RENDER"], R(0), R(1), R(2), 0)]
        if m == "ADDI":
            n(3)
            return [self.enc_i(1, R(0), R(1), self.ev(ops[2], ln), ln)]
        if m in ("LW", "SW"):
            n(2)
            base, off = self.mem_operand(ops[1], ln)
            return [self.enc_i(OPCODES[m], R(0), base, off, ln, "смещение адреса")]
        if m in ("BEQ", "BNE", "BLT"):
            n(3)
            return [self.branch(OPCODES[m], R(0), R(1), ops[2], item)]
        if m in ("JMP", "JAL"):
            n(1)
            return [self.enc_j(OPCODES[m], self.ev(ops[0], ln), ln)]
        if m == "JR":
            n(1)
            return [(OPCODES["JR"] << 12) | (R(0) << 6)]
        if m in ("LUI", "LLI"):
            n(2)
            return [self.enc_u(OPCODES[m], R(0), self.ev(ops[1], ln), ln)]
        if m == "HALT":
            n(0)
            return [0xF000]
        # ---------- псевдокоманды ----------
        if m == "LI":
            n(2)
            v = self.ev(ops[1], ln)
            if not -32768 <= v <= 0xFFFF:
                raise AsmError(ln, f"константа {v} не влезает в 16 бит")
            v &= 0xFFFF
            return [self.enc_u(0xA, R(0), v >> 8, ln), self.enc_u(0xB, R(0), v & 0xFF, ln)]
        if m == "MOV":
            n(2)
            return [self.enc_r(0, R(0), R(1), 0, FUNCT["ADD"])]
        if m == "NOP":
            n(0)
            return [0x0000]
        if m == "B":
            n(1)
            return [self.branch(OPCODES["BEQ"], 0, 0, ops[0], item)]
        if m == "CALL":
            n(1)
            return [self.enc_j(OPCODES["JAL"], self.ev(ops[0], ln), ln)]
        if m == "RET":
            n(0)
            return [(OPCODES["JR"] << 12) | (7 << 6)]
        if m in ("INC", "DEC"):
            n(1)
            return [self.enc_i(1, R(0), R(0), 1 if m == "INC" else -1, ln)]
        if m in ("BEQZ", "BNEZ"):
            n(2)
            op = OPCODES["BEQ"] if m == "BEQZ" else OPCODES["BNE"]
            return [self.branch(op, R(0), 0, ops[1], item)]
        if m == "BGT":
            n(3)                                   # ra > rb  <=>  rb < ra
            return [self.branch(OPCODES["BLT"], R(1), R(0), ops[2], item)]
        # «длинные» условные переходы на любой адрес ROM:
        # обычный переход достаёт только PC + 1 - 32 .. PC + 1 + 31
        if m in ("LBEQ", "LBNE"):
            n(3)
            inv = OPCODES["BNE"] if m == "LBEQ" else OPCODES["BEQ"]
            return [self.enc_i(inv, R(0), R(1), 1, ln),          # обратное условие: обойти JMP
                    self.enc_j(OPCODES["JMP"], self.ev(ops[2], ln), ln)]
        if m == "LBLT":
            n(3)
            return [self.enc_i(OPCODES["BLT"], R(0), R(1), 1, ln),  # меньше -> на JMP
                    self.enc_i(OPCODES["BEQ"], 0, 0, 1, ln),        # иначе обойти JMP
                    self.enc_j(OPCODES["JMP"], self.ev(ops[2], ln), ln)]
        raise AsmError(ln, f"неизвестная команда {m}")

    def pass2(self):
        listing = []
        for item in self.items:
            ln = item.line_no
            if item.mnem == ".WORD":
                words = [self.ev(o, ln) & 0xFFFF for o in item.ops]
            elif item.mnem == ".STRING":
                words = parse_string(item.ops[0], ln)
            elif item.mnem == ".SPACE":
                words = [0] * item.size
            else:
                words = self.encode(item)
            assert len(words) == item.size, item.mnem
            mem = self.rom if item.section == "text" else self.ram
            for k, w in enumerate(words):
                a = item.addr + k
                if a in mem:
                    raise AsmError(ln, f"адрес 0x{a:03x} уже занят")
                mem[a] = w & 0xFFFF
            listing.append((item, words))
        return listing

    def assemble(self, text):
        lines = text.splitlines()
        self.pass1(lines)
        return self.pass2()


def write_hex(path, mem, size, fill):
    last = max(mem) + 1 if mem else 0
    with open(path, "w") as f:
        for a in range(max(last, 1) if size is None else size):
            f.write(f"{mem.get(a, fill):04x}\n")


def write_listing(path, listing, symbols):
    with open(path, "w") as f:
        f.write("; секция адрес  слово  исходная строка\n")
        for item, words in listing:
            sec = "T" if item.section == "text" else "D"
            for k, w in enumerate(words):
                src = item.src.strip() if k == 0 else ""
                f.write(f"{sec}  {item.addr + k:04x}   {w:04x}   {src}\n")
        f.write("\n; метки и константы\n")
        for name, val in sorted(symbols.items(), key=lambda kv: kv[1]):
            f.write(f";   {name:<20} = 0x{val & 0xFFFF:04x} ({val})\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Ассемблер 16-битной ISA курсовой")
    ap.add_argument("source")
    ap.add_argument("-o", "--out", required=True, help="префикс выходных файлов")
    args = ap.parse_args(argv)
    try:
        with open(args.source, encoding="utf-8") as f:
            text = f.read()
        asm = Assembler()
        listing = asm.assemble(text)
    except AsmError as e:
        print(f"{args.source}: {e}", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"ошибка: {e}", file=sys.stderr)
        return 1
    write_hex(args.out + ".rom.hex", asm.rom, None, 0xF000)
    write_hex(args.out + ".ram.hex", asm.ram, RAM_SIZE, 0x0000)
    write_listing(args.out + ".lst", listing, asm.symbols)
    print(f"{args.source}: {len(asm.rom)} слов кода, {len(asm.ram)} слов данных -> {args.out}.*")
    return 0


if __name__ == "__main__":
    sys.exit(main())
