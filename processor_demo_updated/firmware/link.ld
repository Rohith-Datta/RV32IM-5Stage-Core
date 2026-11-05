OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0, LENGTH = 64K }
SECTIONS {
 .text : { KEEP(*(.text.start)) *(.text*) } > RAM
 .rodata : { *(.rodata*) *(.srodata*) } > RAM
 .data : { *(.data*) *(.sdata*) } > RAM
 . = ALIGN(4);
 __global_pointer$ = . + 0x800;
 .bss (NOLOAD) : { __bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > RAM
 __stack_top = ORIGIN(RAM) + LENGTH(RAM);
 ASSERT(__bss_end < __stack_top - 4096, "Not enough stack space")
}
