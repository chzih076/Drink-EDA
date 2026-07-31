// lvs_models — 生成自包含 sky130A LVS SPICE 模型库
//
// 整合自 tools/gen_lvs_models：扫描变体 spice 引用的 pr 器件，
// 拼接 corner pm3（含 subckt/.model），过滤 netgen 不需要的内容，
// 输出单文件 sky130A.lvs.spice（netgen 不支持 .include）。

use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use crate::cli;

const VARIANTS: [&str; 7] = [
    "sky130_fd_sc_hd",
    "sky130_fd_sc_hdll",
    "sky130_fd_sc_hs",
    "sky130_fd_sc_lp",
    "sky130_fd_sc_ls",
    "sky130_fd_sc_ms",
    "sky130_fd_sc_hvl",
];

const DIODE_TEMPLATE: &str = "\
* Template generated for sky130_fd_pr__diode_pw2nd (no official pm3 file)
.subckt  sky130_fd_pr__diode_pw2nd a c
D1 a c sky130_fd_pr__diode_pw2nd__model
.ends
";

/// 过滤变体 spice 中 netgen 不需要的内容：
/// - `.include`/`.lib` 行
/// - `.model` 卡及续行（器件参数，LVS 无用）
/// - 文件级（subckt 外）器件实例（官方生成器层次残片）
fn filter_spice_lib(content: &str) -> String {
    let mut out = String::new();
    let mut in_sub = false;
    let mut in_model = false;
    for line in content.lines() {
        let t = line.trim_start();
        let lt = t.to_ascii_lowercase();

        if lt.starts_with(".include") || lt.starts_with(".lib ")
            || lt.starts_with(".endl") || lt.starts_with(".lib\t")
        {
            continue;
        }
        if in_model {
            if t.starts_with('+') || t.starts_with('*') {
                continue;
            }
            in_model = false;
        }
        if lt.starts_with(".model") {
            in_model = true;
            continue;
        }
        if lt.starts_with(".subckt") {
            in_sub = true;
            out.push_str(line);
            out.push('\n');
            continue;
        }
        if lt.starts_with(".ends") {
            in_sub = false;
            out.push_str(line);
            out.push('\n');
            continue;
        }
        if !in_sub && !t.is_empty() && !t.starts_with('.') && !t.starts_with('*') {
            let c = t.as_bytes()[0] as char;
            if "XMRCDVILBQ".contains(c) {
                continue; // 文件级器件实例：丢弃
            }
        }
        out.push_str(line);
        out.push('\n');
    }
    out
}

/// 过滤 `.include`/`.lib` 行（corner pm3 保留全部定义）。
fn strip_includes(content: &str) -> String {
    let mut out = String::new();
    for line in content.lines() {
        let t = line.trim_start();
        if t.starts_with(".include") || t.starts_with(".lib ")
            || t.starts_with(".endl") || t.starts_with(".lib\t")
        {
            continue;
        }
        out.push_str(line);
        out.push('\n');
    }
    out
}

fn read_opt(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_default()
}

/// 从 diode_pw2nd_05v5.model.spice 提取 .model 卡（改名 <dev>__model）。
fn extract_diode_model(pr_spice: &Path, dev: &str) -> String {
    let src = pr_spice.join("sky130_fd_pr__diode_pw2nd_05v5.model.spice");
    let content = read_opt(&src);
    let mut out = String::new();
    let mut in_model = false;
    for line in content.lines() {
        let t = line.trim_start();
        if t.starts_with(".model") {
            out.push_str(&format!(".model sky130_fd_pr__{}__model d\n", dev));
            in_model = true;
            continue;
        }
        if in_model {
            if t.starts_with('+') {
                out.push_str(line);
                out.push('\n');
            } else {
                break;
            }
        }
    }
    out
}

/// 从一行提取所有 `sky130_fd_pr__<name>` 器件 token。
fn extract_devices(line: &str, set: &mut BTreeSet<String>) {
    let bytes = line.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if line[i..].starts_with("sky130_fd_pr__") {
            let start = i;
            let mut j = i + "sky130_fd_pr__".len();
            while j < bytes.len() && (bytes[j].is_ascii_alphanumeric() || bytes[j] == b'_') {
                j += 1;
            }
            if j > start + "sky130_fd_pr__".len() {
                set.insert(line[start..j].to_string());
            }
            i = j;
        } else {
            i += 1;
        }
    }
}

pub fn run(args: &[String]) -> Result<(), String> {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/lik".to_string());
    let mut pdk = PathBuf::from(&home).join(".local/share/pdk/sky130A/libs.ref");
    let mut corner = "tt".to_string();
    let mut out: Option<PathBuf> = None;

    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--pdk" => pdk = PathBuf::from(cli::next_val(&mut it, "--pdk")?),
            "--corner" => {
                corner = cli::next_val(&mut it, "--corner")?;
                if !matches!(corner.as_str(), "tt" | "ff" | "ss") {
                    return Err("--corner 必须是 tt/ff/ss".into());
                }
            }
            "--out" => out = Some(PathBuf::from(cli::next_val(&mut it, "--out")?)),
            _ => return Err(format!("未知参数: {a}")),
        }
    }

    let out = out.unwrap_or_else(|| {
        pdk.parent()
            .unwrap_or(Path::new("."))
            .join("libs.tech/netgen/sky130A.lvs.spice")
    });

    if !pdk.is_dir() {
        return Err(format!("找不到 PDK libs.ref 目录: {}", pdk.display()));
    }
    let pr_spice = pdk.join("sky130_fd_pr/spice");

    // 1. 扫描变体 spice，收集 pr 器件
    let mut devices: BTreeSet<String> = BTreeSet::new();
    let mut variant_files: Vec<(String, PathBuf)> = Vec::new();
    for v in VARIANTS {
        let agg = pdk.join(v).join("spice").join(format!("{v}.spice"));
        let content = read_opt(&agg);
        if content.is_empty() {
            eprintln!("警告: 变体 {v} 的聚合 spice 缺失");
            continue;
        }
        for line in content.lines() {
            extract_devices(line, &mut devices);
        }
        variant_files.push((v.to_string(), agg));
    }
    if devices.is_empty() {
        return Err("未在任何变体 spice 中发现 pr 器件引用".into());
    }

    // 2. 组装输出
    let mut result = String::new();
    result.push_str("*********************************************************\n");
    result.push_str("* sky130A LVS model library (self-contained)\n");
    result.push_str("* Generated by Drink-EDA tools/drink\n");
    result.push_str(&format!(
        "* Corner: {}\n* Devices: {}\n",
        corner,
        devices.len()
    ));
    result.push_str("* Note: netgen does not support .include; this file is\n");
    result.push_str("*       a fully inlined model set (cells + devices).\n");
    result.push_str("*********************************************************\n\n");

    // corner 模型（<dev>__<corner>.pm3.spice 自包含，后续不再拼普通 pm3）
    let mut corner_done: BTreeSet<String> = BTreeSet::new();
    let mut corner_params = String::new();
    for dev in &devices {
        let cpm3 = pr_spice.join(format!("{dev}__{corner}.pm3.spice"));
        if cpm3.is_file() {
            corner_params.push_str(&format!("\n* ---- corner model: {dev} ----\n"));
            corner_params.push_str(&strip_includes(&read_opt(&cpm3)));
            corner_done.insert(dev.clone());
        }
    }
    if !corner_params.is_empty() {
        result.push_str("** corner parameters **\n");
        result.push_str(&corner_params);
        result.push('\n');
    }

    // 变体 cell 库
    result.push_str("** standard cell libraries **\n");
    for (v, f) in &variant_files {
        result.push_str(&format!("\n*** {v} ***\n"));
        result.push_str(&filter_spice_lib(&read_opt(f)));
        if !result.ends_with('\n') {
            result.push('\n');
        }
    }

    // pr 器件模型
    result.push_str("\n** sky130_fd_pr device models **\n");
    let mut missing: Vec<String> = Vec::new();
    for dev in &devices {
        if corner_done.contains(dev) {
            continue;
        }
        let pm3 = pr_spice.join(format!("{dev}.pm3.spice"));
        if pm3.is_file() {
            result.push_str(&format!("\n*** {dev} ***\n"));
            result.push_str(&strip_includes(&read_opt(&pm3)));
            if !result.ends_with('\n') {
                result.push('\n');
            }
        } else if dev == "sky130_fd_pr__diode_pw2nd" {
            result.push('\n');
            result.push_str(DIODE_TEMPLATE);
            result.push_str(&extract_diode_model(&pr_spice, "diode_pw2nd"));
        } else {
            missing.push(dev.clone());
        }
    }

    if !missing.is_empty() {
        eprintln!("警告: 以下器件无 pm3 定义（netgen 将按 setup.tcl 器件表处理）:");
        for d in &missing {
            eprintln!("  - {d}");
        }
    }

    // 3. 写输出
    if let Some(parent) = out.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("创建目录失败: {e}"))?;
    }
    fs::write(&out, &result).map_err(|e| format!("写入 {} 失败: {e}", out.display()))?;

    println!("已生成: {}", out.display());
    println!("  变体: {}", variant_files.len());
    println!("  pr 器件: {}", devices.len());
    println!("  缺失定义(按器件表处理): {}", missing.len());
    println!("  大小: {} bytes", result.len());
    Ok(())
}
