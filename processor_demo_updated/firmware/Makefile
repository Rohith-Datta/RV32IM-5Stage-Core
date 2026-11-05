CROSS ?= riscv64-unknown-elf-
CFLAGS = -march=rv32imf_zicsr_zbb -mabi=ilp32f -O1 -ffreestanding -fno-builtin -ffp-contract=off -fno-fast-math -msmall-data-limit=0 -nostdlib -nostartfiles -Wl,--no-relax -T link.ld
all: ../avionics_demo.mem avionics_demo.dis
avionics_demo.elf: avionics_demo.c start.S link.ld
	$(CROSS)gcc $(CFLAGS) start.S avionics_demo.c -o $@
avionics_demo.bin: avionics_demo.elf
	$(CROSS)objcopy -O binary $< $@
../avionics_demo.mem: avionics_demo.bin
	python3 ../tools/bin_to_mem.py $< $@
avionics_demo.dis: avionics_demo.elf
	$(CROSS)objdump -d $< > $@
clean:
	rm -f avionics_demo.elf avionics_demo.bin avionics_demo.dis ../avionics_demo.mem
