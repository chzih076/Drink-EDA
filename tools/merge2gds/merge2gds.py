#!/usr/bin/env python3
"""
merge2gds — DEF + GDS 库 → 完整晶体管级 GDS
用法: merge2gds.py <input.def> <gds_dir> <output.gds>
依赖: python3, klayout (Python API)

将 OpenROAD 输出的 DEF 文件与标准单元 GDS 库合并，
生成包含完整晶体管几何的单文件 GDS。
"""

import os, re, sys
from klayout import db

def main():
    if len(sys.argv) < 4:
        print(f"用法: {sys.argv[0]} <input.def> <gds_dir> <output.gds>", file=sys.stderr)
        sys.exit(1)

    def_path = sys.argv[1]
    gds_dir = sys.argv[2]
    out_path = sys.argv[3]

    # 读 DEF，收集所需 cell
    needed = set()
    for m in re.finditer(r'-\s+\S+\s+(\S+)\s*\+', open(def_path).read()):
        needed.add(m.group(1))

    # 创建目标 layout
    layout = db.Layout()
    top = layout.create_cell("DESIGN")

    # 读标准单元 GDS，只复制需要的
    cache = {}
    for f in os.listdir(gds_dir):
        if not f.endswith('.gds'):
            continue
        ly = db.Layout()
        ly.read(os.path.join(gds_dir, f))
        tc = ly.top_cell()
        short = tc.name
        if short.startswith("sky130_fd_sc_hd__") or short.startswith("sky130_ef_sc_hd__"):
            short = short[17:]
        if short not in needed:
            continue

        ci = layout.add_cell(tc.name)
        for li in range(ly.layers()):
            info = ly.get_info(li)
            tli = layout.layer(info)
            for s in tc.shapes(li).each():
                layout.cell(ci).shapes(tli).insert(s)
        cache[short] = ci

    # 放置 cell 引用
    for inst, cell, x, y in re.findall(
        r'-\s+(\S+)\s+(\S+)\s*\+.*?PLACED\s*\(\s*(\d+)\s+(\d+)\s*\)',
        open(def_path).read(), re.DOTALL):
        if cell in cache:
            top.insert(db.DCellInstArray(cache[cell], db.DTrans(int(x), int(y))))

    layout.write(out_path)
    print(f"GDS: {os.path.getsize(out_path)} bytes, {len(needed)} cell types")

if __name__ == '__main__':
    main()
