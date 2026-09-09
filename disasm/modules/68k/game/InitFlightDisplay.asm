; ============================================================================
; InitFlightDisplay -- Loads the flight-path background graphic, initialises the scroll table, clears the sprite counter, and zeroes the flight-slot array at $FF153C
; Called: ?? times.
; 62 bytes | $01A60E-$01A64B
; ============================================================================
InitFlightDisplay:                                                  ; $01A60E
    pea     ($00049B26).l
    pea     ($0002).w
    pea     ($000A).w
    pea     ($0560).w
    jsr     (ROM_BASE+$01D7BE).l
    pea     ($0004).w
    pea     ($0037).w
    jsr     (ROM_BASE+$01E0B8).l
    pea     ($0048).w
    clr.l   -(sp)
    pea     ($00FF153C).l
    jsr     (ROM_BASE+$01D520).l
    lea     $0024(sp),sp
    rts
