ENTRY(main)

SECTIONS
{
    . = 0x00000000;
    .text : {
        *(.text.main)
        *(.text.entry)
        *(.text*)
    }
    .rodata : {
        *(.rodata*)
    }
    . = ALIGN(4);
    .data : {
        *(.data*)
    }
    .bss : {
        *(.bss*)
    }
}
