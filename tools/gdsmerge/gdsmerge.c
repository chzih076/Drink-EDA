#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <stdint.h>

static uint32_t fsize(FILE *f) {
    long p = ftell(f), e; fseek(f, 0, SEEK_END); e = ftell(f); fseek(f, p, SEEK_SET);
    return (uint32_t)e;
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "用法: %s <input.def> <gds_dir> <output.gds>\n", argv[0]); return 1; }
    
    // 收集 DEF 中出现的 cell 名
    FILE *f = fopen(argv[1], "r"); fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    char *buf = malloc(sz + 1); fread(buf, 1, sz, f); fclose(f); buf[sz] = 0;
    
    char def_cells[256][256]; int ndef = 0;
    char *p = buf;
    while ((p = strstr(p, "PLACED"))) {
        char *s = p; while (s > buf && *s != '\n') s--; if (*s == '\n') s++;
        char a[256], b[256]; int x, y;
        if (sscanf(s, " - %255s %255s", a, b) >= 2) {
            int found = 0;
            for (int i = 0; i < ndef; i++) if (strcmp(def_cells[i], b) == 0) { found = 1; break; }
            if (!found && ndef < 256) strcpy(def_cells[ndef++], b);
        }
        p++;
    }
    free(buf);
    printf("DEF: %d 种 cell\n", ndef);
    
    // 扫描 GDS 目录
    DIR *dir = opendir(argv[2]); if (!dir) { perror("opendir"); return 1; }
    struct dirent *e;
    
    // 输出 GDS 头部
    FILE *out = fopen(argv[3], "wb"); if (!out) { perror("fopen"); return 1; }
    uint8_t hdr[] = {0x00,0x06,0x00,0x02,0x02,0x58}; fwrite(hdr, 1, 6, out); // HEADER 600
    uint8_t lib[28] = {0x00,0x1C,0x01,0x02}; fwrite(lib, 1, 28, out); // BGNLIB
    uint8_t lnam[] = {0x00,0x13,0x02,0x06,'w','s','2','8','1','2','b','_','c','t','r','l',0}; fwrite(lnam, 1, 18, out); // LIBNAME ws2812b_ctrl
    uint8_t u[24] = {0x00,0x18,0x03,0x05}; double dbu=0.001,usr=1e-9; memcpy(u+4,&dbu,8); memcpy(u+12,&usr,8); fwrite(u,24,1,out); // UNITS
    
    int nloaded = 0, nplaced = 0;
    while ((e = readdir(dir)) != NULL) {
        char *n = e->d_name; int nl = strlen(n);
        if (nl < 5 || strcmp(n+nl-4,".gds") != 0) continue;
        
        // 提取短名
        char sn[256]; strcpy(sn, n); sn[nl-4]=0;
        char *ss = sn;
        if (strncmp(ss,"sky130_fd_sc_hd__",17)==0) ss+=17;
        else if (strncmp(ss,"sky130_ef_sc_hd__",17)==0) ss+=17;
        
        int needed = 0;
        for (int i=0;i<ndef;i++) if(strcmp(ss,def_cells[i])==0) { needed=1; break; }
        if (!needed) continue;
        
        // 读取整个 GDS 文件并写出（跳过头部）
        char path[1024]; snprintf(path,1024,"%s/%s",argv[2],n);
        FILE *in = fopen(path,"rb"); if(!in) continue;
        uint32_t len = fsize(in);
        uint8_t *data = malloc(len);
        fread(data,1,len,in); fclose(in);
        
        // 跳过 HEADER+BGNLIB+LIBNAME+UNITS，找 BGNSTR
        int off = 0;
        while (off < (int)len-4) {
            uint16_t rlen = (data[off]<<8)|data[off+1];
            if (rlen < 4) break;
            if (data[off+2]==5) break; // BGNSTR
            off += rlen;
        }
        
        if (off < (int)len) {
            fwrite(data+off, 1, len-off, out);
            nloaded++;
        }
        free(data);
    }
    closedir(dir);
    
    // 顶层 cell
    uint8_t bgn[12] = {0,12,5,2}; fwrite(bgn,12,1,out); // BGNSTR
    uint8_t snm[] = {0,16,6,6,'w','s','2','8','1','2','b','_','c','t','r','l'};
    fwrite(snm,1,16,out); // STRNAME ws2812b_ctrl
    
    // 放置所有 cell 引用
    p = buf; // re-use
    while ((p = strstr(p, "PLACED"))) {
        char *s = p; while (s > buf && *s != '\n') s--; if (*s == '\n') s++;
        char a[256], b[256]; int x, y;
        if (sscanf(s, " - %255s %255s %*s %*s %*s %*s ( %d %d )", a, b, &x, &y) >= 4) {
            uint8_t sref[4] = {0,4,0x0A,1}; fwrite(sref,4,1,out); // SREF
            
            char fn[256]; snprintf(fn,256,"sky130_fd_sc_hd__%s",b);
            int fl = strlen(fn);
            uint8_t sh[4] = {(fl+4)>>8,(fl+4)&0xFF,0x0C,6};
            if (fl & 1) { fn[fl]=0; fl++; }
            sh[0]=(fl+4)>>8; sh[1]=(fl+4)&0xFF;
            fwrite(sh,4,1,out); fwrite(fn,1,fl,out); // SNAME
            
            int32_t xy[2] = {__builtin_bswap32(x), __builtin_bswap32(y)};
            uint8_t xyh[4] = {0,12,0x10,3}; fwrite(xyh,4,1,out); fwrite(xy,8,1,out); // XY
            uint8_t endel[4] = {0,4,0x11,0}; fwrite(endel,4,1,out); // ENDEL
            nplaced++;
        }
        p++;
    }
    
    uint8_t endstr[4]={0,4,7,0}; fwrite(endstr,4,1,out); // ENDSTR
    uint8_t endlib[4]={0,4,4,0}; fwrite(endlib,4,1,out); // ENDLIB
    fclose(out);
    
    printf("GDS: loaded=%d placed=%d\n", nloaded, nplaced);
    return 0;
}
