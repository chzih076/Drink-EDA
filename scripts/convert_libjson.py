#!/usr/bin/env python3
"""Batch convert skywater-pdk .lib.json to .lib using official converter."""
import sys, os, glob
sys.path.insert(0, os.environ.get("SKYWATER_PDK_TOOLS", "/run/media/lik/git/skywater-pdk/scripts/python-skywater-pdk"))
from skywater_pdk import liberty

import os
LIBS = os.environ.get("PDK_LIBS", "/run/media/lik/git/skywater-pdk-libs")
variants = ["sky130_fd_sc_hd", "sky130_fd_sc_hdll", "sky130_fd_sc_hs",
            "sky130_fd_sc_lp", "sky130_fd_sc_ls", "sky130_fd_sc_ms",
            "sky130_fd_sc_hvl"]

for lib in variants:
    libdir = f"{LIBS}/{lib}"
    outdir = f"{libdir}/timing"
    os.makedirs(outdir, exist_ok=True)
    for mode in ("basic", "ccsnoise", "leakage"):
        flags = ['--' + mode] if mode != "basic" else []
        sys.argv = ['liberty', libdir, 'all'] + flags + ['-o', outdir]
        try:
            rc = liberty.main()
        except SystemExit as e:
            rc = e.code or 0
        print(f"  [{lib}] {mode}: rc={rc}")
    # Strip "{lib}__" prefix from generated .lib filenames
    for f in glob.glob(f"{outdir}/{lib}__*.lib"):
        nf = os.path.join(outdir, os.path.basename(f).replace(lib + "__", "", 1))
        if nf != f:
            os.rename(f, nf)
            print(f"  [{lib}] rename -> {os.path.basename(nf)}")
print("DONE")
