; ============================================================================
; DrawLabeledBox -- Draw a labeled dialog box at fixed screen position (10x17 chars at position 1) by calling the text print function with the string pointer.
; Called: ?? times.
; 44 bytes | $02377C-$0237A7
; ============================================================================
DrawLabeledBox:                                                  ; $02377C
    move.l  a2,-(sp)
    movea.l $0008(sp),a2
    pea     ($000A).w
    pea     ($001D).w
    pea     ($0011).w
    pea     ($0001).w
    jsr     (ROM_BASE+$005A04).l
    move.l  a2,-(sp)
    jsr     (ROM_BASE+$03B270).l
    lea     $0014(sp),sp
    movea.l (sp)+,a2
    rts
