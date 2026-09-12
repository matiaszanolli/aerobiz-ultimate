/* Aerobiz Ultimate -- SH2 image link map.
 *
 * The 32X boot ROM copies this image from the cartridge to SDRAM offset 0
 * using the MARS user header (docs/32x-hardware-manual.md section 5.1), so
 * the image is linked at the cached SDRAM base 0x06000000.  Code runs cached;
 * only registers are touched cache-through.
 *
 * Master and slave vector tables are placed at the two addresses named in the
 * user header.  Keep the three constants here, disasm/sh2/shared/mars.inc and
 * disasm/32x/mars_user_header.inc in agreement.
 */
OUTPUT_FORMAT("elf32-sh")
OUTPUT_ARCH(sh)
ENTRY(master_start)

MEMORY
{
    sdram (rwx) : ORIGIN = 0x06000000, LENGTH = 256K
}

SECTIONS
{
    . = 0x06000000;

    .master_vectors 0x06000000 : { *(.master_vectors) } > sdram
    .slave_vectors  0x06000140 : { *(.slave_vectors)  } > sdram

    .text 0x06000280 :
    {
        *(.master_text)
        . = ALIGN(4);
        *(.slave_text)
        . = ALIGN(4);
        *(.text*)
        . = ALIGN(4);
        *(.rodata*)
        . = ALIGN(4);
    } > sdram

    .data : { *(.data*) . = ALIGN(4); } > sdram

    /* objcopy -O binary does not emit NOBITS, so .bss is absent from the
     * cartridge image and SDRAM arrives holding whatever the boot ROM left.
     * master_start zeroes the range between these two symbols before any C
     * code runs. */
    .bss  :
    {
        __bss_start = .;
        *(.bss*) *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > sdram

    /DISCARD/ : { *(.comment) *(.note*) }
}
