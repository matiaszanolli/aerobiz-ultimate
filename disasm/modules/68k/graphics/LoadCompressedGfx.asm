; ============================================================================
; LoadCompressedGfx -- Decompress world-map graphics for screen IDs 18-25 and place tiles on screen
; Called: 7 times.
; 174 bytes | $005FF6-$0060A3
; ============================================================================
LoadCompressedGfx:                                                  ; $005FF6
    movem.l d2-d4,-(sp)
    move.l  $0010(sp),d2
    move.l  $0018(sp),d3
    move.l  $0014(sp),d4
    cmpi.w  #$12,d2
    bcs.w   .l609e
    cmpi.w  #$19,d2
    bhi.w   .l609e
    cmpi.w  #$18,d2
    bne.b   .l602c
    pea     ($0010).w
    pea     ($0030).w
    pea     (ROM_BASE+$0007675E).l
    bra.b   .l603a
.l602c:                                                 ; $00602C
    pea     ($0010).w
    pea     ($0030).w
    pea     (ROM_BASE+$0007673E).l
.l603a:                                                 ; $00603A
    jsr     (ROM_BASE+$005092).l
    moveq   #$0,d0
    move.w  d2,d0
    lsl.l   #$2,d0
    movea.l #ROM_BASE+$00088c90,a0
    move.l  (a0,d0.l),-(sp)
    pea     ($00FF1804).l
    jsr     (ROM_BASE+$003FEC).l
    pea     ($0078).w
    pea     ($0640).w
    pea     ($00FF1804).l
    jsr     (ROM_BASE+$0045E6).l
    lea     $0020(sp),sp
    pea     (ROM_BASE+$000700A8).l
    pea     ($000A).w
    pea     ($000C).w
    moveq   #$0,d0
    move.w  d3,d0
    move.l  d0,-(sp)
    moveq   #$0,d0
    move.w  d4,d0
    move.l  d0,-(sp)
    clr.l   -(sp)
    pea     ($001B).w
    jsr     (ROM_BASE+$000D64).l
    lea     $001c(sp),sp
.l609e:                                                 ; $00609E
    movem.l (sp)+,d2-d4
    rts
; === Translated block $0060A4-$006298 ===
; 6 functions, 500 bytes
