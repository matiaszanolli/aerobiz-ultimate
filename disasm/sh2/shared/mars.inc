! ==========================================================================
! Aerobiz Ultimate -- SH2 side 32X definitions
!
! Cited to docs/32x-hardware-manual.md and docs/sh7604-hardware-manual.md.
! System and VDP registers are the cache-through ($2000xxxx) addresses:
! manual 3.4 states cache cannot be used for them.
! ==========================================================================

        .equ    SYSREG,         0x20004000      ! FM/ADEN/CART/HEN/V/H/CMD/PWM
        .equ    HCOUNT,         0x20004004
        .equ    DREQCTL,        0x20004006
        .equ    DREQ_SRC,       0x20004008
        .equ    DREQ_DST,       0x2000400C
        .equ    DREQ_LEN,       0x20004010
        .equ    DREQ_FIFO,      0x20004012
        .equ    VRES_CLR,       0x20004014
        .equ    VINT_CLR,       0x20004016
        .equ    HINT_CLR,       0x20004018
        .equ    CMD_CLR,        0x2000401A
        .equ    PWM_CLR,        0x2000401C

        .equ    COMM0,          0x20004020      ! 8 words, shared with the 68000
        .equ    COMM2,          0x20004024
        .equ    COMM4,          0x20004028
        .equ    COMM6,          0x2000402C

        .equ    PWM_CTL,        0x20004030
        .equ    PWM_CYCLE,      0x20004032
        .equ    PWM_LCH,        0x20004034
        .equ    PWM_RCH,        0x20004036
        .equ    PWM_MONO,       0x20004038

        .equ    VDP_BITMAP,     0x20004100      ! PAL/PRI/240/M1/M0
        .equ    VDP_SHIFT,      0x20004102
        .equ    VDP_FILL_LEN,   0x20004104
        .equ    VDP_FILL_ADDR,  0x20004106
        .equ    VDP_FILL_DATA,  0x20004108
        .equ    VDP_FBCTL,      0x2000410A      ! VBLK/HBLK/PEN/FEN/FS
        .equ    PALETTE,        0x20004200      ! 256 words, word access only

        .equ    FRAMEBUFFER,    0x24000000      ! line table then pixel data
        .equ    OVERWRITE,      0x24020000      ! zero bytes are skipped
        .equ    ROM,            0x22000000      ! unreadable while RV = 1
        .equ    SDRAM,          0x26000000      ! cache-through view
        .equ    SDRAM_CACHED,   0x06000000      ! cached view -- use this for code

! Interrupt mask register bits -- manual 3.2.2
        .equ    SYSREG_PWM,     0x0001
        .equ    SYSREG_CMD,     0x0002
        .equ    SYSREG_H,       0x0004
        .equ    SYSREG_V,       0x0008
        .equ    SYSREG_HEN,     0x0080
        .equ    SYSREG_CART,    0x0100
        .equ    SYSREG_ADEN,    0x0200
        .equ    SYSREG_FM,      0x8000

! Bitmap mode values -- manual 3.2
        .equ    MODE_BLANK,     0x0000
        .equ    MODE_PACKED,    0x0001
        .equ    MODE_DIRECT,    0x0002
        .equ    MODE_RUNLEN,    0x0003
        .equ    BM_PRI,         0x0080          ! 1 = 32X in front of the Genesis

! SDRAM map.  The 32X boot ROM copies the whole SH2 image here from the
! cartridge using the parameters in the MARS user header (manual 5.1).
        .equ    MASTER_VBR,     0x06000000      ! 0x120 bytes of vector table
        .equ    SLAVE_VBR,      0x06000140
        .equ    MASTER_STACK,   0x0603F000
        .equ    SLAVE_STACK,    0x0603F800

! IRL auto-vector offsets from VBR -- sh7604-hardware-manual.md table 4.3.
! IRL pairs share a vector, so level 6/7 -> 67, 8/9 -> 68, and so on.
        .equ    VEC_PWM,        0x10C           ! level 6,  vector 67
        .equ    VEC_CMD,        0x110           ! level 8,  vector 68
        .equ    VEC_HINT,       0x114           ! level 10, vector 69
        .equ    VEC_VINT,       0x118           ! level 12, vector 70
        .equ    VEC_VRES,       0x11C           ! level 14, vector 71
