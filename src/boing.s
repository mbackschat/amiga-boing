;==============================================================================
; boing.s -- master assembly file for the Boing demo
;==============================================================================
; The AMICUS Disk 9 polite Boing, as disassembled by Harry "Piru" Sintonen,
; split across multiple files for readability. The five src/*.s files contain
; the original disassembled content in its original order; this file is the
; vasm entry point and just glues them together.
;
; Build pipeline (run from the repository root; see scripts/build.sh):
;     vasmm68k_mot -m68000 -Fhunk -linedebug  src/boing.s  ->  build/boing.o
;     vlink -bamigahunk -Bstatic              build/boing.o  ->  uae/dh0/boing
; (All INCDIR/INCLUDE paths below are relative to the repo root, so the
;  assembler must be invoked from there.)
;
; Splitting decision rationale:
;   - src/startup.s  (~195 lines)  -- Lattice C `c.o` startup boilerplate.
;                                     Not application code. Ignore unless
;                                     debugging argv/WBStartup plumbing.
;   - src/anim.s     (~458 lines)  -- _Boing per-frame entry, _InitBoing /
;                                     _initCleanup audio setup/rollback,
;                                     _CleanUp, plus audio sample DATA.
;   - src/globe.s    (~581 lines)  -- _init_globe and _draw_globe -- the
;                                     mathematical and visual core of the
;                                     demo. Sphere geometry + polygon fill.
;   - src/main.s     (~1236 lines) -- _GoodBye final cleanup, _main entry
;                                     and main loop, application globals.
;   - src/runtime.s  (~840 lines)  -- Lattice C runtime + library glue stubs.
;                                     Not application code.
;
; The original monolithic file is preserved as archive/boing_original.s for
; byte-identity reference against Sintonen's published disassembly.
;
; Cross-reference: docs/DEMO-BACKGROUND.md section 7 (variant lineage of this
; source) and docs/AMIGA-KNOWHOW.md (per-register and per-library reference).
;==============================================================================

                    INCDIR     "vendor/include"
                    INCLUDE    "exec/types.i"
                    INCLUDE    "exec/exec.i"
                    INCLUDE    "exec/exec_lib.i"
                    INCLUDE    "graphics/graphics_lib.i"
                    INCLUDE    "hardware/custom.i"
                    INCLUDE    "libraries/dos.i"
                    INCLUDE    "intuition/intuition.i"
                    INCLUDE    "intuition/intuition_lib.i"
                    INCLUDE    "math/mathffp_lib.i"
                    INCLUDE    "math/mathtrans_lib.i"
                    INCLUDE    "libraries/dosextens.i"
                    INCLUDE    "libraries/dos_lib.i"
                    INCLUDE    "exec/alerts.i"
                    INCLUDE    "devices/audio.i"
                    INCLUDE    "hardware/dmabits.i"
                    INCLUDE    "exec/io.i"

custom = $dff000

                    INCLUDE    "src/startup.s"
                    INCLUDE    "src/anim.s"
                    INCLUDE    "src/globe.s"
                    INCLUDE    "src/main.s"
                    INCLUDE    "src/runtime.s"
