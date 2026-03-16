/* ============================================================
   link.ld  -  Linker Script for RV32IM SoC
   Step 20 — Hello World

   Memory Map
   ──────────────────────────────────────────────────────────
   IMEM  0x0000_0000  64 KB  code + rodata (in LUTRAM)
   DMEM  0x2000_0000  64 KB  data + bss + stack

   Stack grows downward from top of DMEM.
   ============================================================ */

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}

ENTRY(_start)

SECTIONS
{
    /* ── Code + read-only data → IMEM ── */
    .text : {
        *(.text.start)      /* crt0 _start must be first */
        *(.text*)
        *(.rodata*)
    } > IMEM

    /* ── Initialised data: stored in IMEM, copied to DMEM at boot ── */
    .data : {
        _data_start = .;
        *(.data*)
        _data_end = .;
    } > DMEM AT > IMEM

    _data_load = LOADADDR(.data);   /* source address in IMEM */

    /* ── Uninitialised data: zeroed at boot ── */
    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > DMEM

    /* ── Stack: top of DMEM ── */
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}
