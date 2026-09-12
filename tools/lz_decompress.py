#!/usr/bin/env python3
"""Aerobiz's LZ decompressor, reimplemented from the 68000 at $003FEC.

U-031 needs this to read map data out of the ROM at build time instead of
grabbing it off a screen. U-046 needs the same routine understood well enough
to port to the SH2 -- it is 11.93% of gameplay frames, the single largest
non-idle cost in the profile. One reimplementation serves both.

Transcribed literally from the disassembly rather than rewritten into something
tidier, so it can be diffed against the original:

  $003F72  read_bits(n)  -- consume n bits from the top of a 16-bit window,
                            refilling from the stream a word at a time. The
                            stream's words are LITTLE-endian: hi = src[1].
  $003FEC  decompress()  -- control byte every 8 tokens, bit set = literal.
                            A match decodes a prefix-coded length then a
                            prefix-coded distance, then copies length+1 bytes
                            from distance+1 back.

Note the odd consumption rule: read_bits(n) shifts n bits out, and the caller
then clears the new top bit with ANDI #$7FFF -- so a token actually consumes
n+1 bits. The literal transcription keeps that rather than folding it in.
"""
import struct, sys

MASK = [(1 << n) - 1 for n in range(17)]      # the table at $04684C


class Stream:
    def __init__(self, data, pos):
        self.d = data
        self.p = pos
        self.window = 0          # $FFBD56
        self.word = 0            # $FFBD54, current source word
        self.avail = 0           # $FF1802, bits left in self.word

    def byte(self):
        b = self.d[self.p]
        self.p += 1
        return b

    def read_bits(self, n):
        """$003F72."""
        self.window = (self.window << n) & 0xFFFF
        if n > self.avail:
            n -= self.avail
            got = MASK[self.avail] & self.word
            self.window = (self.window | ((got << n) & 0xFFFF)) & 0xFFFF
            lo = self.d[self.p]
            hi = self.d[self.p + 1]
            self.word = (hi << 8) | lo          # little-endian in the stream
            self.p += 2
            self.avail = 16 - n
        else:
            self.avail -= n
        bits = (self.word >> self.avail) & MASK[n]
        self.window = (self.window | bits) & 0xFFFF


def decompress(rom, src, limit=1 << 20):
    """$003FEC. Returns the decompressed bytes."""
    out = bytearray()
    s = Stream(rom, src)
    s.read_bits(16)                              # prime the window

    while True:
        ctrl = s.byte()                          # $FFA78C
        for _ in range(8):
            if ctrl & 0x80:
                out.append(s.byte())             # literal
            else:
                w = s.window
                if w & 0x8000:
                    length, n = 1, 0
                elif w & 0x4000:
                    length, n = (w & 0x6000) >> 13, 2
                elif w & 0x2000:
                    length, n = (w & 0x3800) >> 11, 4
                elif w & 0x1000:
                    length, n = (w & 0x1E00) >> 9, 6
                elif w & 0x0800:
                    length, n = (w & 0x0F80) >> 7, 8
                elif w & 0x0400:
                    length, n = (w & 0x07E0) >> 5, 10
                elif w & 0x0200:
                    length, n = (w & 0x03F8) >> 3, 12
                else:
                    length = ((w & 0x01FC) >> 2) + 0x80
                    if length == 0xFF:           # $004232, end of stream
                        return bytes(out)
                    n = 13
                if n:
                    s.read_bits(n)
                s.window &= 0x7FFF               # $0040F0

                w = s.window
                if w < 0x0800:
                    dist, n = (w & 0x0600) >> 9, 7
                elif w < 0x0C00:
                    dist, n = ((w & 0x0300) >> 8) + 4, 8
                elif w < 0x1800:
                    dist, n = (((w - 0x0C00) & 0x0F80) >> 7) + 8, 9
                elif w < 0x3000:
                    dist, n = (((w - 0x1800) & 0x1FC0) >> 6) + 0x20, 10
                elif w < 0x4000:
                    dist, n = ((w & 0x1FFF) | 0x1000) >> 5, 11
                elif w < 0x5000:
                    dist, n = ((w & 0x1FFF) | 0x1000) >> 4, 12
                elif w < 0x6000:
                    dist, n = ((w & 0x1FFF) | 0x1000) >> 3, 13
                elif w < 0x7000:
                    dist, n = ((w & 0x1FFF) | 0x1000) >> 2, 14
                else:
                    dist, n = ((w & 0x1FFF) | 0x1000) >> 1, 15
                s.read_bits(n)

                back = len(out) - dist - 1
                if back < 0:
                    raise ValueError(f"back-reference before the start "
                                     f"(out={len(out)} dist={dist})")
                for i in range(length + 1):      # length+1 bytes
                    out.append(out[back + i])

            ctrl = (ctrl + ctrl) & 0xFF          # ADD.B d0,$FFA78C
            if len(out) > limit:
                raise ValueError("output limit exceeded; probably desynced")


if __name__ == '__main__':
    rom = open(sys.argv[1], 'rb').read()
    addr = int(sys.argv[2], 0)
    data = decompress(rom, addr)
    print(f"${addr:06X}: {len(data)} bytes out")
    if len(sys.argv) > 3:
        open(sys.argv[3], 'wb').write(data)
        print(f"wrote {sys.argv[3]}")
    else:
        print(data[:64].hex(' '))
