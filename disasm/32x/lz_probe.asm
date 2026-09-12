; ===========================================================================
; U-046 -- what does the 68000 actually spend on LZ decompression?
;
; The offload arithmetic needs a rate, not a share.  U-045 measured the
; decompressor at 11.93% of gameplay frames by PC sampling, which says where
; the time goes but not what a byte costs -- and the whole U-046 decision is a
; comparison of cost per output byte against cost per transported byte.
;
; Method, the same shape as U-035's SH2 benchmark: run the real routine in a
; loop over a table of real blocks, accumulate output bytes and calls, and let
; the harness supply the clock by running a fixed number of frames.  One NTSC
; frame is 7,670,454 / 59.92 = 128,020 68000 cycles, so
;
;     cycles per output byte = frames * 128020 / bytes
;
; Addresses are GAME_BASE-relative: the compressed data lives in the game
; half at $900000, which is what ROM_BASE resolves to when that half is
; assembled. The boot half does not define ROM_BASE.
;
; The eight blocks span the measured size distribution (192 to 27,872 bytes,
; median 1,952), so the rate is a mix rather than one lucky block.
;
; The probe parks instead of starting the game, exactly as the RV and SH2
; probes do.  That is what makes $FFFD00 and the $FF1804 scratch buffer safe
; to write: PORT_ARCHITECTURE.md section 2.1 records that no work RAM is
; permanently free, and this range is only untouched because the game never
; runs here.  $FF1804 + 27,872 ends at $FF8524, clear of the decompressor's
; own scratch at $FFA78C and $FFBD56.
; ===========================================================================

LZP_RESULT      equ $00FFFD00
LZP_DEST        equ $00FF1804           ; the buffer every real call site uses
LZP_BLOCKS      equ 8

; The game's own decompressor, at its rebased address.  Arguments are on the
; stack: source pushed first, destination second.  Returns D0.L = bytes
; written, which is what makes the byte tally exact rather than a table
; lookup that could drift from the data.
GameLzDecompress equ GAME_BASE+$003FEC


LzProbeRun:
        movem.l d2-d7/a2-a3,-(sp)

        lea     (LZP_RESULT).l,a3
        move.l  #'LZP0',(a3)                    ; +$00 magic
        clr.l   $04(a3)                         ; +$04 calls completed
        clr.l   $08(a3)                         ; +$08 output bytes, low 32
        clr.l   $0C(a3)                         ; +$0C passes over the table

.pass:
        lea     (LzProbeBlocks,pc),a2
        moveq   #LZP_BLOCKS-1,d7

.block:
        move.l  (a2)+,-(sp)                     ; source
        pea     (LZP_DEST).l                    ; destination
        jsr     (GameLzDecompress).l
        addq.l  #8,sp

        addq.l  #1,$04(a3)                      ; one more call
        add.l   d0,$08(a3)                      ; D0 = bytes written

        dbra    d7,.block

        addq.l  #1,$0C(a3)                      ; one more full pass
        bra.s   .pass                           ; runs until the harness stops

; Never reached; kept so the register discipline is honest if it ever is.
        movem.l (sp)+,d2-d7/a2-a3
        rts

; ---------------------------------------------------------------------------
; Eight real compressed blocks, spanning the measured distribution of the 46
; distinct sources reachable from the 92 static call sites.
; ---------------------------------------------------------------------------
LzProbeBlocks:
        dc.l    GAME_BASE+$0004E0CE              ;    192 bytes out
        dc.l    GAME_BASE+$0009FB08              ;    576
        dc.l    GAME_BASE+$0009CC24              ;   1024
        dc.l    GAME_BASE+$0004A25E              ;   1984
        dc.l    GAME_BASE+$0009F410              ;   3520
        dc.l    GAME_BASE+$0004D096              ;   8320
        dc.l    GAME_BASE+$000B22C8              ;  23136
        dc.l    GAME_BASE+$000AF194              ;  27872
