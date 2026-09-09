; ============================================================================
; ShowPlayerInfo -- Display player info screen with formatted data
; Called: 12 times.
; 274 bytes | $01C43C-$01C54D
; ============================================================================
ShowPlayerInfo:                                                  ; $01C43C
    movem.l d2/a2,-(sp)
    move.l  $000c(sp),d2
    move.w  d2,d0
    mulu.w  #$24,d0
    movea.l #$00ff0018,a0
    lea     (a0,d0.w),a0
    movea.l a0,a2
    pea     ($0001).w
    pea     ($000F).w
    move.w  d2,d0
    add.w   d0,d0
    movea.l #ROM_BASE+$00076520,a0
    pea     (a0,d0.w)
    jsr     (ROM_BASE+$005092).l
    pea     (ROM_BASE+$0004975E).l
    pea     ($00FF1804).l
    jsr     (ROM_BASE+$003FEC).l
    pea     ($0001).w
    clr.l   -(sp)
    pea     ($00FF1804).l
    pea     ($0008).w
    pea     ($0328).w
    jsr     (ROM_BASE+$01D568).l
    lea     $0028(sp),sp
    clr.l   -(sp)
    pea     ($0002).w
    pea     ($0016).w
    pea     ($0019).w
    pea     ($0009).w
    clr.l   -(sp)
    pea     ($001A).w
    jsr     (ROM_BASE+$000D64).l
    lea     $001c(sp),sp
    pea     (ROM_BASE+$00049706).l
    pea     ($0002).w
    pea     ($0016).w
    pea     ($0019).w
    pea     ($0009).w
    pea     ($0001).w
    pea     ($001B).w
    jsr     (ROM_BASE+$000D64).l
    pea     ($0020).w
    pea     ($0020).w
    clr.l   -(sp)
    clr.l   -(sp)
    jsr     (ROM_BASE+$03A942).l
    lea     $002c(sp),sp
    pea     ($0019).w
    pea     ($000A).w
    jsr     (ROM_BASE+$03AB2C).l
    move.w  d2,d0
    lsl.w   #$4,d0
    movea.l #$00ff00a8,a0
    pea     (a0,d0.w)
    pea     (ROM_BASE+$00041158).l
    jsr     (ROM_BASE+$03B270).l
    pea     ($0019).w
    pea     ($0013).w
    jsr     (ROM_BASE+$03AB2C).l
    move.l  $0006(a2),-(sp)
    pea     (ROM_BASE+$00041152).l
    jsr     (ROM_BASE+$03B270).l
    lea     $0020(sp),sp
    movem.l (sp)+,d2/a2
    rts
; === Translated block $01C54E-$01D310 ===
; 6 functions, 3522 bytes
