; ============================================================================
; DrawDualPanels -- Draws two fixed-size background panels side-by-side by calling the tile-placement function twice at column offsets 1 and 13
; Called: ?? times.
; 68 bytes | $0177C4-$017807
; ============================================================================
DrawDualPanels:                                                  ; $0177C4
    pea     ($000A).w
    pea     ($001E).w
    pea     ($0002).w
    pea     ($0001).w
    jsr     (ROM_BASE+$005A04).l
    clr.l   -(sp)
    jsr     (ROM_BASE+$00F104).l
    pea     ($000A).w
    pea     ($001E).w
    pea     ($000D).w
    pea     ($0001).w
    jsr     (ROM_BASE+$005A04).l
    pea     ($0001).w
    jsr     (ROM_BASE+$00F104).l
    lea     $0028(sp),sp
    rts
; === Translated block $017808-$017CE6 ===
; 8 functions, 1246 bytes
