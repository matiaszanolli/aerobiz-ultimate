; ===========================================================================
; Aerobiz Ultimate -- 68000 side 32X bring-up
;
; Reached from the Sega initial program once security has passed and the
; adapter is enabled (ADEN = 1).  Lives in the fixed window at $88xxxx so it
; stays addressable whatever the bank register holds.
;
; Responsibilities, in order:
;   1. wait for both SH2s to report ready, then release them
;   2. select the cartridge bank that holds the game image
;   3. leave the 32X layer blanked and the Genesis layer in front
;   4. hand control to the unmodified Aerobiz entry point
; ===========================================================================

; ---------------------------------------------------------------------------
; Security result -- manual 5.2
;
; The initial program does not jump here; it falls through with the carry flag
; carrying its verdict, which is why the manual's own sample listing puts a
; `bcs` immediately after `.include icd_mars.prg`.  This must therefore be the
; very first instruction of the application, before anything disturbs CCR.
; ---------------------------------------------------------------------------
        bcs.w   MarsSecurityFailed              ; cs: ID or self-check failure

        move    #$2700,sr                       ; interrupts off during bring-up
        lea     ($00FFF000).l,sp

; ---------------------------------------------------------------------------
; SH2 handshake -- manual 5.1
;
; The boot ROM has the master write 'M_OK' to comm0 and the slave write 'S_OK'
; to comm4 immediately before the application starts.  Both SH2s then spin
; until the 68000 clears those words.  Clearing them is what actually releases
; the SH2s into our code, so it must happen exactly once and only after both
; have reported.
; ---------------------------------------------------------------------------
.wait_master:
        cmpi.l  #'M_OK',(MARS_COMM_MOK).l
        bne.s   .wait_master
.wait_slave:
        cmpi.l  #'S_OK',(MARS_COMM_SOK).l
        bne.s   .wait_slave

        clr.l   (MARS_COMM_MOK).l               ; release the master
        clr.l   (MARS_COMM_SOK).l               ; release the slave

; ---------------------------------------------------------------------------
; Cartridge banking -- manual 3.2.1
;
; The game image sits at cartridge $100000 and is assembled for $900000, so
; bank 1 must be selected before any game code or data is touched.  Nothing
; below this point may change the bank without restoring it.
; ---------------------------------------------------------------------------
        move.w  #MARS_BANK1,(MARS_BANKSET).l

; ---------------------------------------------------------------------------
; 32X video: blanked, Genesis in front -- manual 3.2 / 3.3
;
; Blank mode is the initial value but is set explicitly so the boot state is
; not assumed.  While the layer is blanked the Genesis VDP is unconstrained,
; which is what lets the stock game run untouched.  PRI = 0 keeps the Genesis
; planes in front for when the layer is later enabled.
;
; Taking FM = 0 first is required before the 68000 may touch the 32X VDP.
; ---------------------------------------------------------------------------
        andi.w  #$7FFF,(MARS_ADAPTER).l         ; FM = 0: VDP authority to the 68000
        move.w  #MARS_MODE_BLANK,(MARS_VDP_BITMAP).l

; ---------------------------------------------------------------------------
; Hand off to the game.
;
; GameEntryPoint is Aerobiz's own reset entry, unmodified, at its rebased
; address.  It performs the TMSS write, loads the Z80 driver and runs the
; stock VDP init table, exactly as it does on a plain Genesis.
; ---------------------------------------------------------------------------
    ifd RVPROBE
; U-020 experiment. Runs before anything else touches the cartridge, then
; parks; read the results out of $FFFD00.
        bsr.w   RvProbeRun
.rv_idle:
        bra.s   .rv_idle
    endif

    ifd MAPTEST
; U-031. Same handover as the U-002 layer test, but the SH2 blits the world map
; out of cartridge ROM instead of a gradient. PRI = 1 so the layer is in front;
; there is nothing on the Genesis planes worth seeing on this cartridge.
        move.w  #MARS_MODE_PACKED|(1<<MARS_BM_PRI),(MARS_VDP_BITMAP).l
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l  ; FM = 1: the SH2 owns the VDP
        move.w  #MARS_SH2_CMD_MAPTEST,(MARS_RPC_CMD).l
.map_wait:
        tst.w   (MARS_RPC_CMD).l
        bne.s   .map_wait
.map_idle:
        bra.s   .map_idle
    endif

    ifd ZOOMTEST
; U-035. The map again, but scaled: the SH2 rasterizes a zoom of the same asset
; and animates it. Identical handover to MAPTEST -- PRI = 1, FM = 1 -- because
; the only thing that changes is what the SH2 does with the frame buffer.
;
; The SH2 never releases the command, so there is no wait loop to write: the
; zoom runs until reset. Benchmark results are in SDRAM, not the comm ports.
        move.w  #MARS_MODE_PACKED|(1<<MARS_BM_PRI),(MARS_VDP_BITMAP).l
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l  ; FM = 1: the SH2 owns the VDP
        move.w  #MARS_SH2_CMD_ZOOM,(MARS_RPC_CMD).l
.zoom_idle:
        bra.s   .zoom_idle
    endif

    ifd TIMINGTEST
; Acceptance test for the SH2 timing model. The SH2 makes a known number of
; accesses of one kind and halts; the harness reads the model's counters and
; compares them with the manual's arithmetic. FM = 1 because phase 1 writes
; the frame buffer.
        move.w  #MARS_MODE_PACKED,(MARS_VDP_BITMAP).l
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l
        move.w  #MARS_SH2_CMD_TIMING,(MARS_RPC_CMD).l
.timing_idle:
        bra.s   .timing_idle
    endif

    ifd H40PROBE
; U-036 experiment: force H40 and turn the layer on, to find out what actually
; breaks. Same setup as LAYERON below, plus the mode forcing in the V-Blank
; trampoline at the bottom of this file.
        move.w  #MARS_MODE_PACKED,(MARS_VDP_BITMAP).l
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l
        move.w  #MARS_SH2_CMD_FBTEST,(MARS_RPC_CMD).l
.h40_wait:
        tst.w   (MARS_RPC_CMD).l
        bne.s   .h40_wait
    endif

    ifd LAYERON
; U-003 experiment: what actually happens when the 32X layer is live while the
; game is in H32?  Manual 3.3 requires the Genesis VDP to be in a 320-wide mode
; whenever the layer is not blanked, but does not say what fails if it is not.
; This build answers that by measurement instead of by reading.
;
; PRI = 0 leaves the Genesis planes in front, which is exactly the section 4.1
; arrangement being evaluated: the 32X layer shows through wherever the Genesis
; pixel is transparent. The game then runs unmodified on top of it.
        move.w  #MARS_MODE_PACKED,(MARS_VDP_BITMAP).l
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l  ; FM = 1: the SH2 owns the VDP
        move.w  #MARS_SH2_CMD_FBTEST,(MARS_RPC_CMD).l
.layer_wait:
        tst.w   (MARS_RPC_CMD).l
        bne.s   .layer_wait
    endif

    ifd FBTEST
; U-002. The bitmap mode register belongs to the 68000 only while FM = 0, so
; set it before handing the frame buffer over. PRI = 1 puts the 32X layer in
; front; there is no Genesis content on this cartridge to hide behind.
        move.w  #MARS_MODE_PACKED|(1<<MARS_BM_PRI),(MARS_VDP_BITMAP).l
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l  ; FM = 1: the SH2 owns the VDP
        move.w  #MARS_SH2_CMD_FBTEST,(MARS_RPC_CMD).l
.fb_wait:
        tst.w   (MARS_RPC_CMD).l
        bne.s   .fb_wait
.fb_idle:
        bra.s   .fb_idle
    endif

    ifd SH2PROBE
; M5 first slice. Runs after the bank switch, because it calls the game's own
; UnsignedDivide in bank 1 as its reference; parks afterwards so $FFFD00 stays
; intact. Read the results out of $FFFD00.
        bsr.w   Sh2ProbeRun
.sh2_idle:
        bra.s   .sh2_idle
    endif

    ifd LZPROBE
; U-046. Same placement as SH2PROBE and for the same reason: it calls the
; game's own LZ_Decompress in bank 1. It never returns -- the harness supplies
; the clock by running a fixed number of frames and reading $FFFD00.
        bsr.w   LzProbeRun
.lz_idle:
        bra.s   .lz_idle
    endif

    ifd MILESTONE1
; Milestone-1 cartridge: there is no game half to jump to (the image is
; $FF-filled from $100000 on), so idle here instead.  Everything the M1
; acceptance test inspects -- comm ports, bank register, adapter state -- has
; already happened by this point and stays observable while we spin.
.m1_idle:
        bra.s   .m1_idle
    endif

    ifnd MILESTONE1
    ifnd RVPROBE
    ifnd SH2PROBE
    ifnd FBTEST
    ifnd MAPTEST
    ifnd ZOOMTEST
    ifnd LZPROBE
    ifnd TIMINGTEST
        jmp     (GameEntryPoint).l
    endif
    endif
    endif
    endif
    endif
    endif
    endif
    endif

; ---------------------------------------------------------------------------
; Security failure.
;
; The adapter has already refused us, so there is nothing safe to draw with and
; no reason to continue.  Halt somewhere a debugger can identify.
; ---------------------------------------------------------------------------
MarsSecurityFailed:
        move    #$2700,sr
.halt:
        bra.s   .halt

; ---------------------------------------------------------------------------
; The DMA thunk sits at a FIXED cartridge offset ($000900, i.e. $880900) so the
; separately-assembled game half can call it by address.  MARS_DMA_THUNK in
; definitions_32x.asm must match this pad.  A negative fill here means MdMain
; has outgrown the gap.
; ---------------------------------------------------------------------------
        dcb.b   (CART_BASE+$000900)-*,$FF
        include "32x/dma_stub.asm"

; ---------------------------------------------------------------------------
; The SH2 math thunk sits at a FIXED cartridge offset ($000A00, i.e. $880A00)
; for the same reason as the DMA thunk above: the game half is assembled
; separately and can only reach it by address.  MARS_SH2_UDIV in
; definitions_32x.asm must match this pad.
; ---------------------------------------------------------------------------
        dcb.b   (CART_BASE+$000A00)-*,$FF
        include "32x/sh2_math.asm"

    ifd RVPROBE
        include "32x/rv_probe.asm"
    endif

    ifd SH2PROBE
        include "32x/sh2_probe.asm"
    endif

    ifd LZPROBE
        include "32x/lz_probe.asm"
    endif

; ===========================================================================
; Exception and interrupt trampolines
;
; The vector table cannot point straight into bank 1: a vector is a fixed
; address and the bank could in principle be switched.  Each trampoline sits
; in the fixed window and jumps on to the stock handler in the game image.
; Addresses are the original Genesis ones plus GAME_BASE.
; ===========================================================================
GameBusError:           jmp     (GAME_BASE+$000F84).l
GameAddressError:       jmp     (GAME_BASE+$000F8A).l
GameIllegal:            jmp     (GAME_BASE+$000F90).l
GameZeroDivide:         jmp     (GAME_BASE+$000F96).l
GameChk:                jmp     (GAME_BASE+$000F9C).l
GameTrapv:              jmp     (GAME_BASE+$000FA2).l
GamePrivilege:          jmp     (GAME_BASE+$000FA8).l
GameTrace:              jmp     (GAME_BASE+$000FAE).l
GameLineA:              jmp     (GAME_BASE+$000FB4).l
GameLineF:              jmp     (GAME_BASE+$000FBA).l
GameReserved:           jmp     (GAME_BASE+$000FC0).l
GameUninitialized:      jmp     (GAME_BASE+$000FD2).l

GameExtInt:             jmp     (GAME_BASE+$001480).l   ; level 2, stub in stock game
GameHBlankInt:          jmp     (GAME_BASE+$001484).l   ; level 4, raster scroll
    ifd H40PROBE
; Force H40 once per frame, preserving whatever else the game has put in
; register 12. CmdSetVDPReg shadows every register at A5+reg, so $FFF01C holds
; the game's own idea of register 12 and only RS1|RS0 need adding.
; d0 must survive: this is an interrupt trampoline, not a call.
GameVBlankInt:
        move.l  d0,-(sp)
        moveq   #0,d0
        move.b  ($00FFF01C).l,d0
        ori.b   #$81,d0                         ; RS1 | RS0 = H40
        ori.w   #$8C00,d0                       ; VDP register 12 write
        move.w  d0,($00C00004).l
        move.l  (sp)+,d0
        jmp     (GAME_BASE+$0014E6).l
    else
GameVBlankInt:          jmp     (GAME_BASE+$0014E6).l
    endif   ; level 6, per-frame handler
