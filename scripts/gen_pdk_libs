#!/usr/bin/env python3
"""PDK Liberty 维护工具：生成合成版和 PnR 版两套 LIB"""
import os, sys, re, glob, shutil

PDK_ROOT = "/home/lik/.local/share/pdk"
LEF_PATH = f"{PDK_ROOT}/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef"
LIB_DIR = f"{PDK_ROOT}/sky130A/libs.ref/sky130_fd_sc_hd/lib"
SRC_DIR = "/run/media/lik/git/skywater-pdk/libraries/sky130_fd_sc_hd/latest"

def copy_original():
    """复制原始 158 cell LIB（来自 open_pdks）"""
    for ver in ["sky130A", "sky130B"]:
        dst = f"{PDK_ROOT}/{ver}/libs.ref/sky130_fd_sc_hd/lib"
        for f in glob.glob(f"{SRC_DIR}/timing/*.lib.json"):
            if "common" in f: continue
            name = os.path.basename(f).replace("sky130_fd_sc_hd__", "").replace(".lib.json", ".lib")
            shutil.copy2(f, f"{dst}/{name}")
        print(f"  {ver}: 原始 LIB 已恢复")

def expand_libs():
    """展开 LIB 使其 cell 名匹配 LEF MACRO 名"""
    # 读 LEF 建立索引
    lef_map = {}
    with open(LEF_PATH) as f:
        for line in f:
            if line.startswith('MACRO '):
                name = line.split()[1]
                m = re.match(r'^(.+)_(\d+)$', name)
                if m:
                    lef_map.setdefault(m.group(1), []).append(name)
    
    for ver in ["sky130A", "sky130B"]:
        dst = f"{PDK_ROOT}/{ver}/libs.ref/sky130_fd_sc_hd/lib"
        for libfile in glob.glob(f"{dst}/tt_025C_1v80.lib"):
            base = os.path.splitext(libfile)[0]
            out = f"{base}_pnr.lib"
            
            with open(libfile) as f:
                content = f.read()
            
            cells = []
            idx = 0
            while True:
                cm = re.search(r'\bcell\s*\([^)]+\)\s*\{', content[idx:])
                if not cm: break
                start = idx + cm.start()
                depth = 1
                end = content.index('{', start) + 1
                while depth > 0 and end < len(content):
                    if content[end] == '{': depth += 1
                    elif content[end] == '}': depth -= 1
                    end += 1
                cells.append((start, end))
                idx = end
            
            parts = []
            last = 0
            expanded = 0
            all_seen = set()
            for start, end in cells:
                parts.append(content[last:start])
                block = content[start:end]
                nm = re.search(r'cell\s*\(([^)]+)\)', block)
                fp = re.search(r'cell_footprint\s*:\s*"([^"]+)"', block)
                if nm and fp:
                    lib_name = nm.group(1)
                    footprint = fp.group(1)
                    # LEF 已去掉 sky130_fd_sc_hd__ 前缀
                    short_fp = footprint.replace('sky130_fd_sc_hd__', '', 1)
                    if short_fp in lef_map:
                        for lef_cell in lef_map[short_fp]:
                            if lef_cell in all_seen:
                                continue
                            all_seen.add(lef_cell)
                            new_block = re.sub(r'cell\s*\([^)]+\)', f'cell ({lef_cell})', block)
                            new_block = re.sub(r'cell_footprint\s*:\s*"[^"]*"', f'cell_footprint : "{lef_cell}"', new_block)
                            parts.append(new_block)
                            expanded += 1
                    else:
                        parts.append(block)
                else:
                    parts.append(block)
                last = end
            parts.append(content[last:])
            
            with open(out, 'w') as f:
                f.write(''.join(parts))
            
            new_count = len(re.findall(r'\bcell\s*\(', ''.join(parts)))
            print(f"  {ver}: {expanded} → {new_count} 个 cell -> {os.path.basename(out)}")

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if cmd in ('copy', 'all'):
        print("=== 复制原始 LIB ===")
        copy_original()
    if cmd in ('expand', 'all'):
        print("=== 展开 PnR LIB ===")
        expand_libs()
    if cmd == 'both':
        copy_original()
        expand_libs()
    print("Done")
