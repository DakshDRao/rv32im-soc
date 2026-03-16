/* ============================================================
   crt0.S  -  Minimal RISC-V Startup
   Step 20 — Hello World

   Responsibilities:
     1. Set stack pointer to top of DMEM
     2. Copy .data from IMEM load address to DMEM VMA
     3. Zero .bss
     4. Call main()
     5. Spin forever on return (should not happen)

   Trap vector (direct mode, mtvec=0):
     A minimal handler lives at address 0 only if we point mtvec
     elsewhere.  For Step 20 we leave mtvec=0 (reset vector)
     and do not enable interrupts, so no handler is needed yet.
   ============================================================ */

    .section .text.start
    .global  _start
    .type    _start, @function

_start:
    /* ── 1. Set stack pointer ── */
    la      sp, _stack_top

    /* ── 2. Copy .data section from IMEM to DMEM ── */
    la      a0, _data_load    /* source (load address in IMEM) */
    la      a1, _data_start   /* destination start in DMEM     */
    la      a2, _data_end     /* destination end   in DMEM     */
    beq     a0, a1, .Lbss    /* skip if load==vma (no copy needed) */
.Lcopy:
    beq     a1, a2, .Lbss
    lw      t0, 0(a0)
    sw      t0, 0(a1)
    addi    a0, a0, 4
    addi    a1, a1, 4
    j       .Lcopy

    /* ── 3. Zero .bss ── */
.Lbss:
    la      a0, _bss_start
    la      a1, _bss_end
.Lzero:
    beq     a0, a1, .Lcall
    sw      zero, 0(a0)
    addi    a0, a0, 4
    j       .Lzero

    /* ── 4. Call main ── */
.Lcall:
    call    main

    /* ── 5. Spin forever (main should not return) ── */
.Lhalt:
    j       .Lhalt

    .size _start, . - _start
