import os
import sys
import time
import shutil
import subprocess
from datetime import datetime

ROOT_DIR = r"C:\CS2202L\RISCV"
FEATURES = [
    {
        "id": 1,
        "name": "Feature 1: RV32I Base Core",
        "dir": os.path.join(ROOT_DIR, "feature_1"),
        "top": "fpga_top_feature1",
        "xpr": "rv32i_5stage_core.xpr"
    },
    {
        "id": 2,
        "name": "Feature 2: RV32M Multiplier Core",
        "dir": os.path.join(ROOT_DIR, "feature_2"),
        "top": "fpga_top_feature2",
        "xpr": "rv32m_multiplier_fpga.xpr"
    },
    {
        "id": 3,
        "name": "Feature 3: RV32M Divider Core",
        "dir": os.path.join(ROOT_DIR, "feature_3"),
        "top": "fpga_top_feature3",
        "xpr": "rv32m_divider_fpga.xpr"
    },
    {
        "id": 4,
        "name": "Feature 4: RV32IMF FPU Core",
        "dir": os.path.join(ROOT_DIR, "feature_4"),
        "top": "fpga_top_feature4",
        "xpr": "rv32mf_fpu_fpga.xpr"
    },
    {
        "id": 5,
        "name": "Feature 5: RV32IMF + L1 D-Cache Core",
        "dir": os.path.join(ROOT_DIR, "feature_5"),
        "top": "fpga_top_feature5",
        "xpr": "rv32imf_dcache_fpga.xpr"
    },
    {
        "id": 6,
        "name": "Feature 6: RV32IMF + L1 I-Cache Core",
        "dir": os.path.join(ROOT_DIR, "feature_6"),
        "top": "fpga_top_feature6",
        "xpr": "rv32imf_icache_fpga.xpr"
    }
]

def check_existing_bitstream(feat):
    feat_dir = feat["dir"]
    top_name = feat["top"]
    
    # Check top feature dir
    top_bit = os.path.join(feat_dir, f"{top_name}.bit")
    if os.path.exists(top_bit):
        # Must be modified today (within last 4 hours)
        mtime = os.path.getmtime(top_bit)
        if time.time() - mtime < 4 * 3600:
            return top_bit
            
    # Check impl_1 dir
    impl_dir = None
    for root, dirs, files in os.walk(feat_dir):
        if os.path.basename(root) == "impl_1":
            impl_dir = root
            break
    if impl_dir and os.path.exists(impl_dir):
        for f in os.listdir(impl_dir):
            if f.endswith(".bit"):
                bpath = os.path.join(impl_dir, f)
                if time.time() - os.path.getmtime(bpath) < 4 * 3600:
                    shutil.copy2(bpath, top_bit)
                    return top_bit
    return None

def build_feature(feat, force_rebuild=False):
    feat_id = feat["id"]
    feat_name = feat["name"]
    feat_dir = feat["dir"]
    top_name = feat["top"]

    if not force_rebuild:
        existing = check_existing_bitstream(feat)
        if existing:
            size_mb = os.path.getsize(existing) / (1024 * 1024)
            print(f">>> [{feat_id}/6] {feat_name}: Bitstream already verified fresh! ({os.path.basename(existing)}, {size_mb:.2f} MB)")
            return {
                "feat": feat_name,
                "status": "SUCCESS",
                "bit": os.path.basename(existing),
                "size_mb": size_mb,
                "duration": "Cached"
            }

    print(f"\n>>> [{feat_id}/6] Starting Bitstream Generation for: {feat_name}...")
    print(f"    Working Directory: {feat_dir}")
    t0 = time.time()
    sys.stdout.flush()

    cmd = ["vivado.bat", "-mode", "batch", "-source", "build_bitstream.tcl"]
    proc = subprocess.run(
        cmd,
        cwd=feat_dir,
        shell=True,
        capture_output=True,
        text=True
    )
    
    elapsed = time.time() - t0
    elapsed_min = elapsed / 60.0

    # Locate bitstream
    found_bit = check_existing_bitstream(feat)

    if found_bit and os.path.exists(found_bit):
        size_bytes = os.path.getsize(found_bit)
        size_mb = size_bytes / (1024 * 1024)
        print(f"    [+] {feat_name}: SUCCESS!")
        print(f"        Bitstream: {os.path.basename(found_bit)} ({size_mb:.2f} MB)")
        print(f"        Duration : {elapsed_min:.2f} minutes ({elapsed:.1f} s)")
        return {
            "feat": feat_name,
            "status": "SUCCESS",
            "bit": os.path.basename(found_bit),
            "size_mb": size_mb,
            "duration": f"{elapsed_min:.2f} min"
        }
    else:
        print(f"    [-] {feat_name}: FAILED (Return Code: {proc.returncode})")
        print(f"        Duration : {elapsed_min:.2f} minutes")
        log_file = os.path.join(feat_dir, "vivado.log")
        if os.path.exists(log_file):
            with open(log_file, "r") as lf:
                lines = lf.readlines()
                print("".join(lines[-25:]))
        return {
            "feat": feat_name,
            "status": "FAILED",
            "bit": "N/A",
            "size_mb": 0.0,
            "duration": f"{elapsed_min:.2f} min"
        }

def main():
    print("=" * 80)
    print("  AUTOMATED BITSTREAM GENERATION FOR ALL 6 FEATURES (GROUP-13)")
    print(f"  Start Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80)
    sys.stdout.flush()

    overall_start = time.time()
    results = []

    for feat in FEATURES:
        res = build_feature(feat)
        results.append(res)
        sys.stdout.flush()

    total_time = time.time() - overall_start
    total_time_min = total_time / 60.0

    print("\n" + "=" * 80)
    print("                     BITSTREAM GENERATION SUMMARY TABLE")
    print("=" * 80)
    print(f"{'Feature Name':<38} | {'Status':<8} | {'Bitstream File':<22} | {'Size':<8} | {'Time':<10}")
    print("-" * 80)
    for r in results:
        print(f"{r['feat']:<38} | {r['status']:<8} | {r['bit']:<22} | {r['size_mb']:.2f} MB | {r['duration']:<10}")
    print("=" * 80)
    print(f"Total Execution Time: {total_time_min:.2f} minutes ({total_time:.1f} seconds)")
    print(f"Finished At         : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80)
    sys.stdout.flush()

if __name__ == "__main__":
    main()
