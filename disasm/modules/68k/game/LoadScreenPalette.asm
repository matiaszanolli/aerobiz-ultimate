; ============================================================================
; LoadScreenPalette -- loads palette entries from a color table for a given player index and renders the palette bar
; Called: 7 times.
; 216 bytes | $0100F2-$0101C9
; ============================================================================
LoadScreenPalette:                                                  ; $0100F2
    link    a6,#-$10
    movem.l d2-d5/a2-a3,-(sp)
    move.l  $000c(a6),d4
    move.l  $0008(a6),d5
    movea.l #ROM_BASE+$0d64,a2
    lea     -$0010(a6),a3
    moveq   #$0,d3
    move.b  ($00FF0016).l,d3
    pea     ($0010).w
    move.l  a3,-(sp)
    pea     (ROM_BASE+$00076ACE).l
    jsr     (ROM_BASE+$0045B2).l
    clr.w   d2
.l10128:                                                ; $010128
    cmp.w   d2,d5
    beq.b   .l10130
    cmp.w   d2,d4
    bne.b   .l1014a
.l10130:                                                ; $010130
    move.w  d3,d0
    add.w   d0,d0
    movea.l #$00ff0118,a0
    move.w  (a0,d0.w),d0
    move.w  d2,d1
    ext.l   d1
    add.l   d1,d1
    movea.l d1,a0
    move.w  d0,(a3,a0.l)
.l1014a:                                                ; $01014A
    addq.w  #$1,d2
    cmpi.w  #$7,d2
    blt.b   .l10128
    pea     (ROM_BASE+$0004A63A).l
    pea     ($00FF1804).l
    jsr     (ROM_BASE+$003FEC).l
    clr.l   -(sp)
    clr.l   -(sp)
    pea     ($00FF1804).l
    pea     ($0025).w
    pea     ($0330).w
    jsr     (ROM_BASE+$01D568).l
    pea     ($0001).w
    pea     ($000E).w
    jsr     (a2)
    lea     $0030(sp),sp
    pea     (ROM_BASE+$0004A5DA).l
    pea     ($0006).w
    pea     ($0008).w
    clr.l   -(sp)
    pea     ($0015).w
    clr.l   -(sp)
    pea     ($001B).w
    jsr     (a2)
    pea     ($0001).w
    pea     ($000E).w
    jsr     (a2)
    pea     ($0008).w
    pea     ($0038).w
    move.l  a3,-(sp)
    jsr     (ROM_BASE+$005092).l
    movem.l -$0028(a6),d2-d5/a2-a3
    unlk    a6
    rts
