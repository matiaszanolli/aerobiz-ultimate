; ============================================================================
; RunScreenLoop -- Main game screen state machine loop: process actions, load graphics packs, dispatch to UI screen handlers
; Called: ?? times.
; 336 bytes | $00A006-$00A155
; ============================================================================
RunScreenLoop:                                                  ; $00A006
    movem.l d2-d3/a2,-(sp)
    movea.l #$0004c974,a2
    pea     ($0001).w
    jsr     (ROM_BASE+$01D340).l
    pea     ($0001).w
    pea     ($0001).w
    jsr     (ROM_BASE+$01D3AC).l
    lea     $000c(sp),sp
    dc.w    $4eba,$04f8                                 ; jsr $00A526
    nop
    dc.w    $4eba,$1718                                 ; jsr $00B74C
    nop
    jsr     (ROM_BASE+$03A8D6).l
    clr.w   d2
    clr.w   ($00FF17C4).l
    bra.w   .la12a
.la04a:                                                 ; $00A04A
    dc.w    $4eba,$010a                                 ; jsr $00A156
    nop
    tst.w   d0
    bne.b   .la068
    dc.w    $4eba,$027e                                 ; jsr $00A2D4
    nop
    cmpi.w  #$1,d0
    bne.w   .la12a
    moveq   #$1,d2
    bra.w   .la12a
.la068:                                                 ; $00A068
    pea     ($0010).w
    pea     ($0010).w
    move.l  a2,d0
    addq.l  #$2,d0
    move.l  d0,-(sp)
    jsr     (ROM_BASE+$005092).l
    move.l  a2,d0
    moveq   #$22,d1
    add.l   d1,d0
    move.l  d0,-(sp)
    pea     ($001C).w
    pea     ($0020).w
    clr.l   -(sp)
    clr.l   -(sp)
    pea     ($0001).w
    pea     ($001B).w
    jsr     (ROM_BASE+$000D64).l
    move.l  a2,d0
    addi.l  #$0722,d0
    move.l  d0,-(sp)
    pea     ($00FF1804).l
    jsr     (ROM_BASE+$003FEC).l
    lea     $0030(sp),sp
    pea     ($0001).w
    clr.l   -(sp)
    pea     ($00FF1804).l
    pea     ($0104).w
    pea     ($0001).w
    jsr     (ROM_BASE+$01D568).l
    jsr     (ROM_BASE+$0177C4).l
    clr.l   -(sp)
    jsr     (ROM_BASE+$017566).l
    lea     $0018(sp),sp
    move.w  d0,d3
    jsr     (ROM_BASE+$01D71C).l
    move.w  d3,d0
    ext.l   d0
    moveq   #-$1,d1
    cmp.l   d0,d1
    beq.b   .la12a
    move.w  d3,d0
    ext.l   d0
    move.l  d0,-(sp)
    dc.w    $4eba,$2940                                 ; jsr $00CA3E
    nop
    dc.w    $4eba,$310a                                 ; jsr $00D20E
    nop
    jsr     (ROM_BASE+$02949A).l
    pea     ($0001).w
    jsr     (ROM_BASE+$01819C).l
    addq.l  #$8,sp
    move.w  #$1,($00FF17C4).l
    moveq   #$1,d2
    dc.w    $4eba,$1918                                 ; jsr $00BA3E
    nop
.la12a:                                                 ; $00A12A
    tst.w   d2
    beq.w   .la04a
    clr.w   d2
.la132:                                                 ; $00A132
    moveq   #$0,d0
    move.w  d2,d0
    move.l  d0,-(sp)
    jsr     (ROM_BASE+$01E98E).l
    addq.l  #$4,sp
    addq.w  #$1,d2
    cmpi.w  #$7,d2
    bcs.b   .la132
    andi.w  #$7fff,($00FF0A34).l
    movem.l (sp)+,d2-d3/a2
    rts
; === Translated block $00A156-$00D5B6 ===
; 32 functions, 13408 bytes
