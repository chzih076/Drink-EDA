// pdk_libs — PDK Liberty 维护：生成合成版与 PnR 版两套 LIB
//
// 移植自 scripts/gen_pdk_libs.py：
//   drink pdk-libs copy    从源库 timing/*.lib.json 复制恢复原始 LIB
//   drink pdk-libs expand  读 LEF MACRO 索引，把 lib 中 cell 展开为尺寸变体
//   drink pdk-libs all     两者都做

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

/// copy_original：把源库 timing/*.lib.json 复制为 PDK lib/*.lib（改名）。
fn copy_original(pdk_root: &Path) -> Result<(), String> {
    let src = Path::new("/run/media/lik/git/skywater-pdk/libraries/sky130_fd_sc_hd/latest/timing");
    let rd = fs::read_dir(src).map_err(|e| format!("无法读取源目录 {}: {e}", src.display()))?;
    let mut files: Vec<String> = Vec::new();
    for e in rd.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        if name.ends_with(".lib.json") && !name.contains("common") {
            files.push(name);
        }
    }
    files.sort();
    for ver in ["sky130A", "sky130B"] {
        let dst = pdk_root
            .join(ver)
            .join("libs.ref/sky130_fd_sc_hd/lib");
        fs::create_dir_all(&dst).map_err(|e| format!("创建目录失败: {e}"))?;
        for name in &files {
            let out_name = name
                .trim_start_matches("sky130_fd_sc_hd__")
                .trim_end_matches(".lib.json");
            let out_name = format!("{out_name}.lib");
            let sp = src.join(name);
            let dp = dst.join(&out_name);
            fs::copy(&sp, &dp).map_err(|e| format!("复制 {} 失败: {e}", sp.display()))?;
        }
        println!("  {ver}: 原始 LIB 已恢复 ({} 个文件)", files.len());
    }
    Ok(())
}

/// expand_libs：按 LEF MACRO 索引把 lib cell 展开为尺寸变体 → *_pnr.lib。
fn expand_libs(pdk_root: &Path) -> Result<(), String> {
    let lef_path = pdk_root
        .join("sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef");

    // 1. 读 LEF 建立 base -> [尺寸名] 索引
    let lef_content = fs::read_to_string(&lef_path)
        .map_err(|e| format!("读取 LEF 失败: {e}"))?;
    let mut lef_map: HashMap<String, Vec<String>> = HashMap::new();
    for line in lef_content.lines() {
        let t = line.trim_start();
        if let Some(rest) = t.strip_prefix("MACRO ") {
            let name = rest.split_whitespace().next().unwrap_or("");
            // 匹配 `^(.+)_(\d+)$`；LEF MACRO 名可能带 sky130_fd_sc_hd__ 前缀，
            // 统一去掉前缀，与 lib 的 cell_footprint 无前缀匹配。
            if let Some(us) = name.rfind('_') {
                let (base, suf) = name.split_at(us);
                let suf = &suf[1..];
                if !base.is_empty() && suf.chars().all(|c| c.is_ascii_digit()) {
                    let base = base.trim_start_matches("sky130_fd_sc_hd__");
                    lef_map.entry(base.to_string()).or_default().push(name.to_string());
                }
            }
        }
    }

    // 2. 对每个变体展开 tt_025C_1v80.lib
    for ver in ["sky130A", "sky130B"] {
        let dst = pdk_root
            .join(ver)
            .join("libs.ref/sky130_fd_sc_hd/lib");
        let libfile = dst.join("tt_025C_1v80.lib");
        let content = fs::read_to_string(&libfile)
            .map_err(|e| format!("读取 {} 失败: {e}", libfile.display()))?;

        // 提取 cell 块（cell (...) { ... }，括号配对）
        let bytes = content.as_bytes();
        let mut cells: Vec<(usize, usize)> = Vec::new();
        let mut idx = 0usize;
        while idx < bytes.len() {
            // 找 "cell" 关键字（词边界近似：前后非标识符字符）
            let found = find_cell_start(&content, idx);
            let Some(start) = found else { break };
            // 找 '{'（start 之后第一个）
            let Some(ob) = content[start..].find('{') else { break };
            let mut depth = 1usize;
            let mut end = start + ob + 1;
            while depth > 0 && end < bytes.len() {
                match bytes[end] {
                    b'{' => depth += 1,
                    b'}' => depth -= 1,
                    _ => {}
                }
                end += 1;
            }
            cells.push((start, end));
            idx = end;
        }

        let mut out = String::new();
        let mut last = 0usize;
        let mut expanded = 0usize;
        let mut all_seen: std::collections::BTreeSet<String> = Default::default();

        for (start, end) in &cells {
            out.push_str(&content[last..*start]);
            let block = &content[*start..*end];
            // cell 名：cell (...) 括号内
            let cell_name = {
                let after = block.find("cell").map(|p| &block[p + 4..]);
                match after.and_then(|s| s.find('(')) {
                    Some(p) => {
                        let inner = &after.unwrap()[p + 1..];
                        inner.split(')').next().unwrap_or("").trim().to_string()
                    }
                    None => String::new(),
                }
            };
            // cell_footprint
            let footprint = find_footprint(block);
            if !cell_name.is_empty() {
                if let Some(fp) = &footprint {
                    let short_fp = fp.trim_start_matches("sky130_fd_sc_hd__");
                    if let Some(sizes) = lef_map.get(short_fp) {
                        for lef_cell in sizes {
                            if all_seen.contains(lef_cell) {
                                continue;
                            }
                            all_seen.insert(lef_cell.clone());
                            let mut nb = block
                                .replacen(&format!("cell ({cell_name})"), &format!("cell ({lef_cell})"), 1);
                            nb = nb.replace(&format!("cell_footprint : \"{fp}\""),
                                            &format!("cell_footprint : \"{lef_cell}\""));
                            out.push_str(&nb);
                            expanded += 1;
                        }
                        last = *end;
                        continue;
                    }
                }
            }
            out.push_str(block);
            last = *end;
        }
        out.push_str(&content[last..]);

        let out_path = dst.join("tt_025C_1v80_pnr.lib");
        fs::write(&out_path, &out).map_err(|e| format!("写入失败: {e}"))?;
        let count = out.matches("cell (").count();
        println!("  {ver}: {expanded} -> {count} 个 cell -> {}", out_path.display());
    }
    Ok(())
}

/// 从 idx 起找 `cell (...)` 块起点（cell 后跟空白/括号）。
fn find_cell_start(content: &str, idx: usize) -> Option<usize> {
    let bytes = content.as_bytes();
    let mut i = idx;
    while i < bytes.len() {
        if bytes[i] == b'c' && content[i..].starts_with("cell") {
            let after = i + 4;
            let next = bytes.get(after).copied().unwrap_or(0);
            let prev = if i > 0 { bytes.get(i - 1).copied().unwrap_or(0) } else { 0 };
            let is_word = |b: u8| b.is_ascii_alphanumeric() || b == b'_';
            if !is_word(prev) && (next == b' ' || next == b'\t' || next == b'(') {
                return Some(i);
            }
        }
        i += 1;
    }
    None
}

/// 在 cell 块内找 `cell_footprint : "..."`。
fn find_footprint(block: &str) -> Option<String> {
    let key = "cell_footprint";
    let pos = block.find(key)?;
    let rest = &block[pos + key.len()..];
    let q = rest.find('"')?;
    let rest2 = &rest[q + 1..];
    let end = rest2.find('"')?;
    Some(rest2[..end].to_string())
}

pub fn run(args: &[String]) -> Result<(), String> {
    let cmd = args.first().map(|s| s.as_str()).unwrap_or("all");
    // 支持 --pdk-root 覆盖（默认与 Python 版一致）
    let mut pdk_root = PathBuf::from("/home/lik/.local/share/pdk");
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--pdk-root" && i + 1 < args.len() {
            pdk_root = PathBuf::from(&args[i + 1]);
            i += 2;
        } else {
            return Err(format!("未知参数: {}", args[i]));
        }
    }

    match cmd {
        "copy" => {
            println!("=== 复制原始 LIB ===");
            copy_original(&pdk_root)?;
        }
        "expand" => {
            println!("=== 展开 PnR LIB ===");
            expand_libs(&pdk_root)?;
        }
        "all" => {
            println!("=== 复制原始 LIB ===");
            copy_original(&pdk_root)?;
            println!("=== 展开 PnR LIB ===");
            expand_libs(&pdk_root)?;
        }
        _ => return Err(format!("未知子命令: {cmd}（可用 copy/expand/all）")),
    }
    println!("Done");
    Ok(())
}
