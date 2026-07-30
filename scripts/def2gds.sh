#!/bin/sh
# def2gds.sh — DEF→GDS conversion using KLayout
# Usage: scripts/def2gds.sh <input.def> [output.gds]
#
# Environment:
#   KLAYOUT_PATH  — path to klayout binary (default: from PATH)
#   PDK           — sky130 PDK path (auto-detected)
#   SKY130_MAP    — layer map file path

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <input.def> [output.gds]"
    exit 1
fi

INDEF="$1"
OUTGDS="${2:-${INDEF%.def}.gds}"

# PDK auto-detect
detect_pdk() {
    for d in "$PDK" \
        "$HOME/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd" \
        "/usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"; do
        [ -f "$d/techlef/sky130_fd_sc_hd.tlef" ] && { echo "$d"; return 0; }
    done
    echo "Error: sky130 PDK not found" >&2
    exit 1
}
PDK_DIR="$(detect_pdk)"

# KLayout
KLAYOUT="${KLAYOUT_PATH:-$(command -v klayout)}"
if [ -z "$KLAYOUT" ]; then
    echo "Error: klayout not found" >&2
    exit 1
fi

# Layer map
MAP_FILE="${SKY130_MAP:-$HOME/.local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map}"

# Write conversion script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/_def2gds.lym"
cat > "$SCRIPT" << 'PYEOF'
import os, sys, glob
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
import klayout.db as db

def_path = os.environ.get('INDEF', '')
gds_path = os.environ.get('OUTGDS', '')
pdk_dir = os.environ.get('PDK_DIR', '/usr/local/share/pdk/sky130A')
map_file = os.environ.get('SKY130_MAP', '')
techlef = os.path.join(pdk_dir, 'techlef/sky130_fd_sc_hd.tlef')
macrolef = os.path.join(pdk_dir, 'lef/sky130_fd_sc_hd.lef')
gds_lib = os.path.join(pdk_dir, 'gds')

layout = db.Layout()
layout.read(techlef)
layout.read(macrolef)

load_opts = db.LoadLayoutOptions()
lc = load_opts.lefdef_config
lc.macro_resolution_mode = 2
for f in sorted(glob.glob(os.path.join(gds_lib, '*.gds'))):
    lc.add_macro_layout_file(f)
if map_file and os.path.exists(map_file):
    lc.map_file = map_file

layout2 = db.Layout()
layout2.read(def_path, load_opts)
layout2.write(gds_path)
print("GDS: %d bytes" % os.path.getsize(gds_path))
PYEOF

INDEF="$INDEF" OUTGDS="$OUTGDS" PDK_DIR="$PDK_DIR" SKY130_MAP="$MAP_FILE" \
  "$KLAYOUT" -b -r "$SCRIPT"
rm -f "$SCRIPT"

echo "GDS: $(ls -lh "$OUTGDS" | awk '{print $5}')"
