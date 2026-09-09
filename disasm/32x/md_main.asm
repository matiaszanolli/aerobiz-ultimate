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
    ifd MILESTONE1
; Milestone-1 cartridge: there is no game half to jump to (the image is
; $FF-filled from $100000 on), so idle here instead.  Everything the M1
; acceptance test inspects -- comm ports, bank register, adapter state -- has
; already happened by this point and stays observable while we spin.
.m1_idle:
        bra.s   .m1_idle
    else
        jmp     (GameEntryPoint).l
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
GameVBlankInt:          jmp     (GAME_BASE+$0014E6).l   ; level 6, per-frame handler
