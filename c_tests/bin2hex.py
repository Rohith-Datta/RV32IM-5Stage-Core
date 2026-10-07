import os
import struct
import sys

RAMSIZE = 4096

def hex_change(val):
    h = hex(val)[2:]
    return "0" * (8 - len(h)) + h

def bin2hex(in_file, out_file):
    j = 0
    with open(out_file, "w") as out_f:
        if os.path.exists(in_file) and os.path.getsize(in_file) > 0:
            with open(in_file, "rb") as in_f:
                while True:
                    data = in_f.read(4)
                    if not data:
                        break
                    # Pad to 4 bytes if last chunk is smaller
                    if len(data) < 4:
                        data = data.ljust(4, b"\x00")
                    word = struct.unpack("<I", data)[0]
                    out_f.write(f"{hex_change(word)} // 32'h{hex_change(j)}\n")
                    j += 4

        while j < RAMSIZE:
            out_f.write(f"00000000 // 32'h{hex_change(j)}\n")
            j += 4

def main():
    if len(sys.argv) >= 3:
        bin2hex(sys.argv[1], sys.argv[2])
    else:
        imem_bin = sys.argv[1] if len(sys.argv) > 1 else "imem.bin"
        dmem_bin = "dmem.bin"
        bin2hex(imem_bin, "imem.hex")
        bin2hex(dmem_bin, "dmem.hex")

if __name__ == "__main__":
    main()
