; ===========================================================================
; U-020 experiment -- what stays readable while RV = 1?
;
; docs/32x-hardware-manual.md:237 says what appears at $000100-$3FFFFF when
; RV = 1, and :238 says what $880000-$9FFFFF holds when RV = 0.  Neither says
; whether the high windows survive an RV = 1 window.  PORT_ARCHITECTURE.md §5.3
; carries that as the one genuinely open question behind the DMA stub.
;
; The stub is designed to be RAM-resident either way, so the answer does not
; decide whether the plan works -- only how much else has to move out of the
; cartridge.  Measure it rather than assume it.
;
; The probe itself runs from work RAM, because if the answer is "no" then any
; code sitting in a cartridge window disappears mid-routine.  Interrupts are
; already masked by MdMain, which docs/32x-technical-info.md:103 requires for
; the duration of RV = 1 regardless.
; ===========================================================================

RV_PROBE_CODE   equ $00FFFC80           ; free work RAM, see PORT_ARCHITECTURE.md §2.1
RV_PROBE_RESULT equ $00FFFD00

; Probed longword: far enough into each window to be real content rather than
; header.  Cartridge $000800 is MdMain in the fixed window and game code in the
; bank window, so the two baselines differ and cannot be confused.
RV_PROBE_FIXED  equ $00880800           ; cartridge $000800 via the fixed window
RV_PROBE_BANK   equ $00900800           ; cartridge $100800 via bank 1
RV_PROBE_DIRECT equ $00100800           ; cartridge $100800 at its own offset

RvProbeRun:
        lea     (RvProbeBody).l,a0
        lea     (RV_PROBE_CODE).l,a1
        move.w  #(RvProbeBodyEnd-RvProbeBody)/2-1,d0
.copy:
        move.w  (a0)+,(a1)+
        dbra    d0,.copy
        jmp     (RV_PROBE_CODE).l       ; its rts returns to MdMain

; --- Copied to work RAM; every operand is absolute, so it needs no relocation.
RvProbeBody:
        lea     (RV_PROBE_RESULT).l,a1

        move.l  (RV_PROBE_FIXED).l,(a1)+        ; +$00 fixed window, RV = 0
        move.l  (RV_PROBE_BANK).l,(a1)+         ; +$04 bank window,  RV = 0

        move.w  (MARS_DREQCTL).l,d1
        bset    #MARS_RV,d1
        move.w  d1,(MARS_DREQCTL).l             ; RV = 1

        move.l  (RV_PROBE_FIXED).l,(a1)+        ; +$08 fixed window, RV = 1
        move.l  (RV_PROBE_BANK).l,(a1)+         ; +$0C bank window,  RV = 1
        move.l  (RV_PROBE_DIRECT).l,(a1)+       ; +$10 cartridge at its own offset

        move.w  (MARS_DREQCTL).l,d1
        bclr    #MARS_RV,d1
        move.w  d1,(MARS_DREQCTL).l             ; RV = 0

        move.l  (RV_PROBE_FIXED).l,(a1)+        ; +$14 fixed window, RV = 0 again
        rts
RvProbeBodyEnd:
