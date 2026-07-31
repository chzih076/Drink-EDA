// map_synth — 合成后网表 cell 名映射（short → drive-strength，匹配 PnR LIB）
//
// 移植自 scripts/map_synth（Python）。行为保持兼容：
// 逐行匹配 `^\s+<cell>\s+<inst>\(` 形式的实例行，将 cell 名按映射表替换；
// 不在映射表中的 cell 名原样保留（如新版带 sky130_fd_sc_hd__ 前缀的全名）。

use std::fs;
use std::io::Write;

/// 158 cell → PnR 465 cell 映射（最小驱动强度），与 Python 版 MAP 一致。
const MAP: &[(&str, &str)] = &[
    ("a2111o", "a2111o_1"), ("a2111oi", "a2111oi_0"), ("a211o", "a211o_1"),
    ("a211oi", "a211oi_1"), ("a21bo", "a21bo_1"), ("a21boi", "a21boi_0"),
    ("a21o", "a21o_1"), ("a21oi", "a21oi_1"), ("a221o", "a221o_1"),
    ("a221oi", "a221oi_1"), ("a222oi", "a222oi_1"), ("a22o", "a22o_1"),
    ("a22oi", "a22oi_1"), ("a2bb2o", "a2bb2o_1"), ("a2bb2oi", "a2bb2oi_1"),
    ("a311o", "a311o_1"), ("a311oi", "a311oi_1"), ("a31o", "a31o_1"),
    ("a31oi", "a31oi_1"), ("a32o", "a32o_1"), ("a32oi", "a32oi_1"),
    ("a41o", "a41o_1"), ("a41oi", "a41oi_1"),
    ("and2", "and2_1"), ("and2b", "and2b_1"),
    ("and3", "and3_1"), ("and3b", "and3b_1"), ("and4", "and4_1"),
    ("and4b", "and4b_1"), ("and4bb", "and4bb_1"),
    ("buf", "buf_1"), ("clkbuf", "clkbuf_1"), ("clkinv", "clkinv_1"),
    ("conb", "conb_1"), ("decap", "decap_12"),
    ("dfbbn", "dfbbn_1"), ("dfbbp", "dfbbp_1"), ("dfrbp", "dfrbp_1"),
    ("dfrtn", "dfrtn_1"), ("dfrtp", "dfrtp_1"),
    ("dfsbp", "dfsbp_1"), ("dfstp", "dfstp_1"), ("dfxbp", "dfxbp_1"),
    ("dfxtp", "dfxtp_1"), ("diode", "diode_2"),
    ("dlclkp", "dlclkp_1"), ("dlrbn", "dlrbn_1"), ("dlrbp", "dlrbp_1"),
    ("dlrtn", "dlrtn_1"), ("dlrtp", "dlrtp_1"),
    ("dlxbn", "dlxbn_1"), ("dlxbp", "dlxbp_1"), ("dlxtn", "dlxtn_1"),
    ("dlxtp", "dlxtp_1"),
    ("ebufn", "ebufn_1"), ("edfxbp", "edfxbp_1"), ("edfxtp", "edfxtp_1"),
    ("einvn", "einvn_0"), ("einvp", "einvp_1"),
    ("fa", "fa_1"), ("fah", "fah_1"), ("fahcin", "fahcin_1"), ("fahcon", "fahcon_1"),
    ("ha", "ha_1"), ("inv", "inv_1"),
    ("maj3", "maj3_1"), ("mux2", "mux2_1"), ("mux2i", "mux2i_1"), ("mux4", "mux4_1"),
    ("nand2", "nand2_1"), ("nand2b", "nand2b_1"),
    ("nand3", "nand3_1"), ("nand3b", "nand3b_1"),
    ("nand4", "nand4_1"), ("nand4b", "nand4b_1"), ("nand4bb", "nand4bb_1"),
    ("nor2", "nor2_1"), ("nor2b", "nor2b_1"),
    ("nor3", "nor3_1"), ("nor3b", "nor3b_1"),
    ("nor4", "nor4_1"), ("nor4b", "nor4b_1"), ("nor4bb", "nor4bb_1"),
    ("o2111a", "o2111a_1"), ("o2111ai", "o2111ai_1"),
    ("o211a", "o211a_1"), ("o211ai", "o211ai_1"),
    ("o21a", "o21a_1"), ("o21ai", "o21ai_0"),
    ("o21ba", "o21ba_1"), ("o21bai", "o21bai_1"),
    ("o221a", "o221a_1"), ("o221ai", "o221ai_1"),
    ("o22a", "o22a_1"), ("o22ai", "o22ai_1"),
    ("o2bb2a", "o2bb2a_1"), ("o2bb2ai", "o2bb2ai_1"),
    ("o311a", "o311a_1"), ("o311ai", "o311ai_0"),
    ("o31a", "o31a_1"), ("o31ai", "o31ai_1"),
    ("o32a", "o32a_1"), ("o32ai", "o32ai_1"),
    ("o41a", "o41a_1"), ("o41ai", "o41ai_1"),
    ("or2", "or2_1"), ("or2b", "or2b_1"),
    ("or3", "or3_1"), ("or3b", "or3b_1"),
    ("or4", "or4_1"), ("or4b", "or4b_1"), ("or4bb", "or4bb_1"),
    ("sdfbbn", "sdfbbn_1"), ("sdfbbp", "sdfbbp_1"),
    ("sdfrbp", "sdfrbp_1"), ("sdfrtn", "sdfrtn_1"), ("sdfrtp", "sdfrtp_1"),
    ("sdfsbp", "sdfsbp_1"), ("sdfstp", "sdfstp_1"),
    ("sdfxbp", "sdfxbp_1"), ("sdfxtp", "sdfxtp_1"),
    ("sdlclkp", "sdlclkp_1"),
    ("sedfxbp", "sedfxbp_1"), ("sedfxtp", "sedfxtp_1"),
    ("xnor2", "xnor2_1"), ("xnor3", "xnor3_1"),
    ("xor2", "xor2_1"), ("xor3", "xor3_1"),
];

fn lookup(cell: &str) -> Option<&'static str> {
    MAP.iter()
        .find(|(k, _)| *k == cell)
        .map(|(_, v)| *v)
}

/// 判断 token 是否形如 `\w+`（字母/数字/下划线）。
fn is_word(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

pub fn run(infile: &str, outfile: &str) -> Result<(), String> {
    let content = fs::read_to_string(infile)
        .map_err(|e| format!("无法读取 {infile}: {e}"))?;

    let mut out = String::with_capacity(content.len());
    let mut mapped = 0usize;

    for line in content.lines() {
        let ws = line.len() - line.trim_start().len();
        let rest = &line[ws..];

        // 匹配 `^\s+<cell>\s+<inst>\(`
        if ws > 0 {
            if let Some(pidx) = rest.find('(') {
                let head = &rest[..pidx];
                let toks: Vec<&str> = head.split_whitespace().collect();
                if toks.len() == 2 && is_word(toks[0]) && is_word(toks[1]) {
                    let mapped_cell = lookup(toks[0]).unwrap_or(toks[0]);
                    if mapped_cell != toks[0] {
                        mapped += 1;
                    }
                    out.push_str(&line[..ws]);
                    out.push_str(mapped_cell);
                    out.push(' ');
                    out.push_str(toks[1]);
                    out.push_str(&rest[pidx..]);
                    out.push('\n');
                    continue;
                }
            }
        }
        out.push_str(line);
        out.push('\n');
    }

    let mut f = fs::File::create(outfile)
        .map_err(|e| format!("无法写入 {outfile}: {e}"))?;
    f.write_all(out.as_bytes())
        .map_err(|e| format!("写入失败: {e}"))?;

    let short = infile.rsplit('/').next().unwrap_or(infile);
    println!("  {short}: {mapped} cells renamed -> {outfile}");
    Ok(())
}
