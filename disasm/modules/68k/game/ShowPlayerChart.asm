; ============================================================================
; ShowPlayerChart -- builds and displays a player's chart panel by filtering active route/relation bits and drawing tiles
; Called: ?? times.
; 260 bytes | $0101CA-$0102CD
; ============================================================================
ShowPlayerChart:                                                  ; $0101CA
    link    a6,#-$10
    movem.l d2-d3/a2,-(sp)
    move.l  $0008(a6),d3
    lea     -$0010(a6),a2
    pea     ($0010).w
    move.l  a2,-(sp)
    pea     (ROM_BASE+$00076ACE).l
    jsr     (ROM_BASE+$0045B2).l
    clr.w   d2
.l101ee:                                                ; $0101EE
    move.w  d3,d0
    lsl.w   #$2,d0
    movea.l #$00ffa6a0,a0
    move.l  (a0,d0.w),d0
    move.w  d2,d1
    lsl.w   #$2,d1
    movea.l #ROM_BASE+$0005ecdc,a0
    and.l   (a0,d1.w),d0
    beq.b   .l10226
    move.w  d3,d0
    add.w   d0,d0
    movea.l #$00ff0118,a0
    move.w  (a0,d0.w),d0
    move.w  d2,d1
    ext.l   d1
    add.l   d1,d1
    movea.l d1,a0
    move.w  d0,(a2,a0.l)
.l10226:                                                ; $010226
    addq.w  #$1,d2
    cmpi.w  #$7,d2
    blt.b   .l101ee
    pea     ($0008).w
    pea     ($0030).w
    pea     (ROM_BASE+$00076ABE).l
    jsr     (ROM_BASE+$005092).l
    pea     (ROM_BASE+$0004A63A).l
    pea     ($00FF1804).l
    jsr     (ROM_BASE+$003FEC).l
    lea     $0020(sp),sp
    clr.l   -(sp)
    clr.l   -(sp)
    pea     ($00FF1804).l
    pea     ($0025).w
    pea     ($0330).w
    jsr     (ROM_BASE+$01D568).l
    pea     (ROM_BASE+$0004A5DA).l
    pea     ($0006).w
    pea     ($0008).w
    clr.l   -(sp)
    pea     ($0015).w
    clr.l   -(sp)
    pea     ($001B).w
    jsr     (ROM_BASE+$000D64).l
    lea     $0030(sp),sp
    pea     ($0008).w
    pea     ($0038).w
    move.l  a2,-(sp)
    jsr     (ROM_BASE+$005092).l
    pea     ($6330).w
    pea     ($0006).w
    pea     ($000A).w
    clr.l   -(sp)
    pea     ($0014).w
    pea     ($0001).w
    pea     ($001A).w
    jsr     (ROM_BASE+$000D64).l
    movem.l -$001c(a6),d2-d3/a2
    unlk    a6
    rts
