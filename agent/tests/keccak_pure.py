"""TEST-ONLY pure-python Keccak-256.

Why this exists: local Python 3.14 has no compiled keccak backend (pycryptodome /
pysha3 uninstallable), so eth_utils.keccak cannot run here. This helper drives
hash-shape tests only. CORRECTNESS ANCHOR: outputs are asserted against vectors
from ethers v6 (independent implementation) in test_strategy.py — if this file
ever diverges, those tests fail. Production (Render py3.11) uses eth_utils.
"""

_ROT = [
    [0, 36, 3, 41, 18],
    [1, 44, 10, 45, 2],
    [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56],
    [27, 20, 39, 8, 14],
]

_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]

_MASK = (1 << 64) - 1


def _rot(x: int, n: int) -> int:
    n %= 64
    return ((x << n) | (x >> (64 - n))) & _MASK if n else x & _MASK


def _keccak_f(s: list[int]) -> None:
    """Keccak-f[1600] permutation, in place on 25 lanes."""
    for rc in _RC:
        # theta
        c = [s[x] ^ s[x + 5] ^ s[x + 10] ^ s[x + 15] ^ s[x + 20] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rot(c[(x + 1) % 5], 1) for x in range(5)]
        s = [s[i] ^ d[i % 5] for i in range(25)]
        # rho + pi
        b = [0] * 25
        for x in range(5):
            for y in range(5):
                b[y + ((2 * x + 3 * y) % 5) * 5] = _rot(s[x + 5 * y], _ROT[x][y])
        # chi
        for x in range(5):
            for y in range(5):
                s[x + 5 * y] = b[x + 5 * y] ^ ((~b[(x + 1) % 5 + 5 * y]) & b[(x + 2) % 5 + 5 * y])
        s[0] ^= rc
    return s


def keccak256(data: bytes) -> bytes:
    """Keccak-256 digest (Ethereum variant: 0x01 suffix, NOT NIST padding)."""
    # why: suffix 0x01 (not 0x06) is THE difference between Keccak and SHA3.
    rate = 136
    state = [0] * 25
    padded = bytearray(data) + b"\x01"
    while len(padded) % rate != rate - 1:
        padded += b"\x00"
    padded += b"\x80"
    for off in range(0, len(padded), rate):
        block = padded[off:off + rate]
        lanes = [int.from_bytes(block[i:i + 8], "little") for i in range(0, rate, 8)]
        for i, lane in enumerate(lanes):
            state[i] ^= lane
        state = _keccak_f(state)
    return b"".join(v.to_bytes(8, "little") for v in state[:4])


def checksum_address(addr: str) -> str:
    """EIP-55 casing using the helper above (test-only)."""
    a = addr.lower().removeprefix("0x")
    h = keccak256(a.encode()).hex()
    return "0x" + "".join(c.upper() if int(h[i], 16) >= 8 else c for i, c in enumerate(a))
