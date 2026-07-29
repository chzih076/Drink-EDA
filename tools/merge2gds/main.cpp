// merge2gds — DEF → GDS 合并工具
// 读取 DEF + 标准单元 GDS 目录 → 输出完整 GDS（含晶体管）
// 编译: g++ -std=c++17 -O2 main.cpp -lklayout_db -lklayout_tl -o merge2gds
// 用法: merge2gds <input.def> <gds_dir> <output.gds>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include <regex>
#include <fstream>
#include <iostream>
#include <dirent.h>

// 直接写 GDS 二进制格式（零依赖）
// GDS 记录格式: [2字节长度][1字节类型][1字节数据类型][数据]
#pragma pack(push, 1)
struct GDSRecord {
    uint16_t length;
    uint8_t  type;
    uint8_t  data_type;
};
#pragma pack(pop)

class GDSWriter {
    FILE *f;
public:
    GDSWriter(const char *path) { f = fopen(path, "wb"); }
    ~GDSWriter() { if (f) fclose(f); }
    bool ok() const { return f != nullptr; }

    void write_rec(uint8_t type, uint8_t dtype, const void *data, uint16_t len) {
        GDSRecord rec = {uint16_t(len + 4), type, dtype};
        fwrite(&rec, 4, 1, f);
        if (len > 0) fwrite(data, len, 1, f);
        // 对齐到偶数
        if ((len + 4) & 1) { uint8_t pad = 0; fwrite(&pad, 1, 1, f); }
    }

    void write_int2(uint8_t type, uint8_t dtype, uint16_t val) {
        uint16_t be = __builtin_bswap16(val);
        write_rec(type, dtype, &be, 2);
    }

    void write_int4(uint8_t type, uint8_t dtype, uint32_t val) {
        uint32_t be = __builtin_bswap32(val);
        write_rec(type, dtype, &be, 4);
    }

    void write_int8(uint8_t type, uint8_t dtype, uint64_t val) {
        uint64_t be = __builtin_bswap64(val);
        write_rec(type, dtype, &be, 8);
    }

    void write_string(uint8_t type, uint8_t dtype, const std::string &s) {
        // 字符串补齐到偶数长度
        std::string buf = s;
        if (buf.size() & 1) buf += '\0';
        write_rec(type, dtype, buf.data(), buf.size());
    }

    void write_header() {
        write_int2(0x00, 0x02, 600);     // HEADER
        write_int8(0x01, 0x02, 0);       // BGNLIB (time=0)
        write_int8(0x01, 0x02, 0);
        write_string(0x02, 0x06, "LIB"); // LIBNAME
        // UNITS: 1nm DBU, 1e-9 user unit
        write_rec(0x03, 0x05, nullptr, 0);
        double dbu = 0.001;
        double user = 1e-9;
        uint8_t units[16];
        memcpy(units, &dbu, 8);
        memcpy(units+8, &user, 8);
        write_rec(0x03, 0x05, units, 16);
    }

    void write_endlib() { write_rec(0x04, 0x00, nullptr, 0); }

    void begin_struct(const std::string &name) {
        write_int8(0x05, 0x02, 0);       // BGNSTR
        write_int8(0x05, 0x02, 0);
        write_string(0x06, 0x06, name);  // STRNAME
    }

    void end_struct() { write_rec(0x07, 0x00, nullptr, 0); }

    void write_sref(const std::string &cell, int x, int y) {
        write_rec(0x0A, 0x01, nullptr, 0); // SREF
        write_string(0x0C, 0x06, cell);    // SNAME
        int32_t xy[2] = {__builtin_bswap32(x), __builtin_bswap32(y)};
        write_rec(0x10, 0x03, xy, 8);      // XY
        write_rec(0x11, 0x00, nullptr, 0); // ENDEL
    }
};

// 从 DEF 解析组件
struct Component {
    std::string inst, cell;
    int x, y;
};
std::vector<Component> parse_def(const std::string &path) {
    std::ifstream f(path);
    std::string line;
    std::vector<Component> comps;
    std::regex re(R"(^\s*-\s+(\S+)\s+(\S+)\s*\+.*?PLACED\s*\(\s*(\d+)\s+(\d+)\s*\))");
    while (std::getline(f, line)) {
        std::smatch m;
        if (std::regex_match(line, m, re)) {
            comps.push_back({m[1], m[2], std::stoi(m[3]), std::stoi(m[4])});
        }
    }
    return comps;
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "用法: %s <输入.def> <gds目录> <输出.gds>\n", argv[0]);
        fprintf(stderr, "示例: %s routed.def /pdk/gds output.gds\n", argv[0]);
        return 1;
    }

    std::string def_path = argv[1];
    std::string gds_dir = argv[2];
    std::string out_path = argv[3];

    // 1. 解析 DEF
    auto comps = parse_def(def_path);
    printf("DEF: %zu 个组件\n", comps.size());

    // 2. 扫描 GDS 目录，构建 cell 名 → 文件路径的映射
    std::map<std::string, std::string> cell_map;
    DIR *dir = opendir(gds_dir.c_str());
    if (!dir) { perror("opendir"); return 1; }
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        std::string name = entry->d_name;
        if (name.size() > 4 && name.substr(name.size()-4) == ".gds") {
            // sky130: sky130_fd_sc_hd__dfrtp_1.gds → dfrtp_1
            std::string cell = name;
            // 去前缀
            auto p = cell.find("__");
            if (p != std::string::npos) cell = cell.substr(p+2);
            // 去后缀
            p = cell.rfind(".gds");
            if (p != std::string::npos) cell = cell.substr(0, p);
            cell_map[cell] = gds_dir + "/" + name;
        }
    }
    closedir(dir);
    printf("GDS 库: %zu 个 cell\n", cell_map.size());

    // 3. 合并并写出 GDS
    printf("写出: %s\n", out_path.c_str());
    // 简化方案：直接写顶层 SREF 引用（cell 几何需用 KLayout 库读取）
    // 这里用纯 GDS 格式写顶层结构 + 引用
    
    // 实际需要 libklayout_db 来读取/合并 GDS 文件
    // 用 system() 调用 klayout 的 Python 脚本做真正的合并
    
    // 方案 A: 直接用 libklayout_db 链接（需要 KLayout 开发库）
    // 方案 B: 使用 system() 调用外部命令
    
    // 这里采用方案 B 作为临时方案（调用已有的 klayout Python 脚本）
    std::string cmd = "python3 /home/lik/Drink-EDA/examples/loong8-ws2812-rc1/scripts/def2gds.py ";
    cmd += def_path + " " + out_path;
    int ret = system(cmd.c_str());
    
    if (ret == 0) {
        printf("完成: %s\n", out_path.c_str());
    } else {
        fprintf(stderr, "转换失败\n");
    }
    return ret;
}
