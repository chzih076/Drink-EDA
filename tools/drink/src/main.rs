// drink — Drink-EDA 统一工具（零第三方依赖）
//
// 子命令：
//   drink map-synth <in.v> <out.v>  合成网表 cell 名映射（short → drive-strength）
//   drink manifests                 生成 loongarch-eda/manifests/*.toml（ldd 依赖扫描）
//   drink lvs-models [--pdk] [--corner] [--out]  生成自包含 LVS SPICE 模型库

mod cli;
mod lvs_models;
mod manifests;
mod map_synth;
mod package;
mod pdk_libs;

use std::process;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = args.first().map(|s| s.as_str()).unwrap_or("");

    let result = match cmd {
        "map-synth" | "map_synth" => {
            if args.len() < 3 {
                eprintln!("用法: drink map-synth <输入.v> <输出.v>");
                process::exit(1);
            }
            map_synth::run(&args[1], &args[2])
        }
        "manifests" => manifests::run(&args[1..]),
        "lvs-models" | "lvs_models" => lvs_models::run(&args[1..]),
        "pdk-libs" | "pdk_libs" => pdk_libs::run(&args[1..]),
        "package" => package::run(&args[1..]),
        "help" | "-h" | "--help" => {
            print_usage();
            Ok(())
        }
        _ => {
            eprintln!("未知子命令: {cmd}");
            print_usage();
            process::exit(1);
        }
    };

    if let Err(e) = result {
        eprintln!("错误: {e}");
        process::exit(1);
    }
}

fn print_usage() {
    println!("drink — Drink-EDA 统一工具");
    println!("用法: drink <子命令> [参数]");
    println!("  map-synth <in.v> <out.v>   合成网表 cell 名映射");
    println!("  manifests                   生成工具安装清单 manifests/*.toml");
    println!("  lvs-models [--pdk <libs.ref>] [--corner tt|ff|ss] [--out <file>]");
    println!("  pdk-libs <copy|expand|all>  PDK Liberty 维护（copy/expand）");
    println!("  package [--pdk-root <sky130A>] [--out <dir>]  生成 PDK 分包目录树（核心+扩展）");
}
