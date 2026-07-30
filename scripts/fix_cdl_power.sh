#!/bin/bash
#
# fix_cdl_power.sh - Fix _unconnected_ power pins in OpenROAD CDL output
#
# OpenROAD's write_cdl outputs _unconnected_ for global power pins
# (VGND, VPWR, VNB, VPB) because the Verilog netlist doesn't explicitly
# connect them. This script reads the PDK SPICE/CDL model to determine
# pin order and replaces _unconnected_ with the correct power/ground.
#
# Rules:
#   - Model pin VGND or VNB → output VGND
#   - Model pin VPWR or VPB → output VPWR
#   - Other pins keep their original net name
#   - Also converts debug[0] → debug_0 (SPICE doesn't support [])
#
# Usage: fix_cdl_power.sh <input.cdl> <pdk_spice.cdl> [output.cdl]

set -euo pipefail

INPUT_FILE="$1"
PDK_SPICE="$2"
OUTPUT_FILE="${3:-}"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <input.cdl> <pdk_spice.cdl> [output.cdl]" >&2
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE" >&2
    exit 1
fi

if [ ! -f "$PDK_SPICE" ]; then
    echo "Error: PDK SPICE file not found: $PDK_SPICE" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# awk script: two-pass
#   Pass 1 (NR==FNR): Read PDK SPICE file, build cell→pins map
#   Pass 2:           Read the raw CDL, fix X_ instances
# ---------------------------------------------------------------------------
awk '
# --------------------------------------------------------------------------
# Pass 1: Build cell pin map from PDK SPICE file
# --------------------------------------------------------------------------
NR == FNR {
    # Handle continuation lines in .subckt definitions
    if (pending_subckt != "") {
        if ($1 == "+") {
            # Continuation line: append everything after "+"
            sub(/^\+[[:space:]]*/, "")
            pending_subckt = pending_subckt " " $0
            next
        } else {
            # End of continuation: process the accumulated subckt
            process_pdk_subckt(pending_subckt)
            pending_subckt = ""
        }
    }

    if (tolower($1) == ".subckt") {
        # Check if this subckt needs continuation
        if ($NF ~ /\\$/) {
            # Line ends with backslash - continuation needed
            # Remove trailing backslash and store
            line = $0
            sub(/\\$/, "", line)
            pending_subckt = line
            next
        }
        process_pdk_subckt($0)
    }
    next
}

# --------------------------------------------------------------------------
# Pass 2: Process CDL file - join continuations, fix X_ instances
# --------------------------------------------------------------------------
{
    # Line continuation handling
    if ($1 == "+") {
        # Continuation of previous instance line - keep merging
        sub(/^\+[[:space:]]*/, "")
        current_line = current_line " " $0
        next
    }

    # If we have a pending line, process it first
    if (current_line != "") {
        process_cdl_line(current_line)
    }

    # Start new accumulation
    current_line = $0
}

END {
    # Process final accumulated line
    if (current_line != "") {
        process_cdl_line(current_line)
    }
}

# --------------------------------------------------------------------------
# Helper: process one .subckt definition from the PDK
# --------------------------------------------------------------------------
function process_pdk_subckt(line,    nf, fields, cell, i, pin_str) {
    nf = split(line, fields)
    if (nf < 3) return
    cell = fields[2]
    # Remove sky130_fd_sc_hd__ prefix (common in SkyWater PDK)
    gsub(/^sky130_fd_sc_hd__/, "", cell)
    # Build pin list (fields 3..NF)
    pin_str = fields[3]
    for (i = 4; i <= nf; i++) {
        pin_str = pin_str " " fields[i]
    }
    cell_pins[cell] = pin_str
}

# --------------------------------------------------------------------------
# Helper: process one CDL line (fully assembled, no continuations)
# --------------------------------------------------------------------------
function process_cdl_line(line,    fields, nf, cell, pin_str, np, model_pins,
                          i, new_line, model_pin, orig_net) {
    # Split line into fields
    nf = split(line, fields)

    # Handle .SUBCKT header: fix bracket net names
    if (tolower(fields[1]) == ".subckt") {
        gsub(/\[/, "_", line)
        gsub(/\]/, "", line)
        print line
        return
    }

    # Handle comment / control lines starting with *
    if (line ~ /^[[:space:]]*\*/) {
        print line
        return
    }

    # Handle .ENDS
    if (tolower(fields[1]) == ".ends") {
        print line
        return
    }

    # Handle *.BUSDELIMITER
    if (fields[1] ~ /^\*\./) {
        print line
        return
    }

    # Handle empty lines
    if (nf == 0) {
        print ""
        return
    }

    # Process X_ instances
    if (fields[1] ~ /^X_/) {
        cell = fields[nf]
        if (cell in cell_pins) {
            pin_str = cell_pins[cell]
            np = split(pin_str, model_pins)
            # Reconstruct the instance line
            new_line = fields[1]
            for (i = 2; i < nf; i++) {
                model_pin = model_pins[i-1]
                orig_net = fields[i]
                if (model_pin == "VGND" || model_pin == "VNB") {
                    new_line = new_line " VGND"
                } else if (model_pin == "VPWR" || model_pin == "VPB") {
                    new_line = new_line " VPWR"
                } else {
                    # Keep original net, but fix brackets
                    gsub(/\[/, "_", orig_net)
                    gsub(/\]/, "", orig_net)
                    new_line = new_line " " orig_net
                }
            }
            new_line = new_line " " cell
            print new_line
        } else {
            # Cell not found in PDK - print as-is with bracket fix
            gsub(/\[/, "_", line)
            gsub(/\]/, "", line)
            print line
        }
        return
    }

    # Fallback: print line as-is
    print line
}
' "$PDK_SPICE" "$INPUT_FILE" > "/tmp/fix_cdl_power.tmp.$$"

# If output file specified, move; otherwise cat to stdout
if [ -n "$OUTPUT_FILE" ]; then
    mv "/tmp/fix_cdl_power.tmp.$$" "$OUTPUT_FILE"
    echo "Fixed CDL written to: $OUTPUT_FILE" >&2
else
    cat "/tmp/fix_cdl_power.tmp.$$"
    rm -f "/tmp/fix_cdl_power.tmp.$$"
fi
