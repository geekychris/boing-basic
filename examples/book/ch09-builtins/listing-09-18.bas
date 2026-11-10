Print Shl(1, 10); ShrA(-16, 2); ShrL(-16, 28); Hex(Shl(&HFF, 8) Or &HAB)
' 16.16 fixed point: 1.5 * 2.25
Dim a As Long, b As Long
a = 1.5 * 65536: b = 2.25 * 65536
Print MulShr(a, b, 16) / 65536
Print MulDiv(1000000, 3000, 7000)       ' 1000000 * 3000 does not fit in a Long
