#!/bin/sh
# Drink Linux Help
# Usage: help [topic]

BOLD='\033[1m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

case "$1" in
    network|net)
        printf "${BLUE}${BOLD}Network${NC}\n"
        printf "  ${GREEN}ifconfig${NC}          Show IP addresses\n"
        printf "  ${GREEN}ip addr${NC}           Show network interfaces\n"
        printf "  ${GREEN}ping${NC} <host>       Test network connectivity\n"
        printf "  ${GREEN}wget${NC} <url>        Download a file\n"
        printf "\n"
        printf "  SSH: ${GREEN}ssh root@localhost -p 2222${NC}\n"
        ;;
    pkg|package|drink)
        printf "${BLUE}${BOLD}Package Manager (drink-pkg)${NC}\n"
        printf "  ${GREEN}drink-pkg init${NC}         Initialize package DB\n"
        printf "  ${GREEN}drink-pkg install${NC} <pkg> Install a .drink package\n"
        printf "  ${GREEN}drink-pkg remove${NC} <pkg> Remove a package\n"
        printf "  ${GREEN}drink-pkg list${NC}         List installed packages\n"
        printf "  ${GREEN}drink-pkg info${NC} <pkg>   Show package details\n"
        printf "\n"
        printf "  Packages: ${YELLOW}/packages/${NC}\n"
        printf "\n"
        printf "${BLUE}${BOLD}EDA Toolchain (Drink-EDA)${NC}\n"
        printf "  ${GREEN}drink-pkg repo add drink-eda${NC}\n"
        printf "  ${YELLOW}  https://gitcode.com/H076lik/Drink-EDA/releases/download/v1.0${NC}\n"
        printf "  ${GREEN}drink-pkg repo update${NC}       Refresh package index\n"
        printf "  ${GREEN}drink-pkg search${NC}            List EDA packages\n"
        printf "  ${GREEN}drink-pkg install yosys${NC}     Install Yosys synthesis\n"
        printf "  ${GREEN}drink-pkg install openroad${NC}  Install OpenROAD PnR\n"
        printf "  ${GREEN}drink-pkg install klayout${NC}   Install KLayout\n"
        printf "  ${GREEN}drink-pkg install sky130-pdk${NC} Install PDK\n"
        printf "\n"
        printf "  ${GREEN}lfl config.yaml${NC}       Run RTL→PnR flow\n"
        printf "\n"
        printf "  ${YELLOW}Drink-EDA${NC}: LoongArch native EDA toolchain\n"
        printf "  ${YELLOW}https://gitcode.com/H076lik/Drink-EDA${NC}\n"
        ;;
    desktop|ui)
        printf "${BLUE}${BOLD}Desktop${NC}\n"
        printf "  ${GREEN}drink-desktop${NC}         Start the GEM desktop\n"
        printf "\n"
        printf "  ${YELLOW}[Drink]${NC} icon   System info\n"
        printf "  ${YELLOW}[Set]${NC}   icon   Settings\n"
        printf "  ${YELLOW}[Disk]${NC}  icon   File browser\n"
        printf "  ${GREEN}ESC${NC}             Exit to shell\n"
        printf "  Taskbar buttons switch windows\n"
        ;;
    system|sys)
        printf "${BLUE}${BOLD}System${NC}\n"
        printf "  ${GREEN}top${NC}               Processes\n"
        printf "  ${GREEN}free${NC}              Memory\n"
        printf "  ${GREEN}uname -a${NC}          Kernel version\n"
        printf "  ${GREEN}cat /proc/cpuinfo${NC}  CPU info\n"
        printf "  ${GREEN}cat /proc/meminfo${NC}  Memory details\n"
        printf "  ${GREEN}df -h${NC}             Disk usage\n"
        printf "  ${GREEN}dmesg${NC}             Kernel log\n"
        printf "  ${GREEN}reboot${NC}            Reboot\n"
        printf "  ${GREEN}poweroff${NC}          Shutdown\n"
        ;;
    bench|benchmark)
        printf "${BLUE}${BOLD}Performance Benchmarks (drink-bench)${NC}\n"
        printf "  ${GREEN}drink-bench${NC}           Run all benchmarks\n"
        printf "  ${GREEN}drink-bench cpu${NC}       CPU performance\n"
        printf "  ${GREEN}drink-bench mem${NC}       Memory performance\n"
        printf "  ${GREEN}drink-bench disk${NC}      Disk performance\n"
        printf "\n"
        printf "Example:\n"
        printf "  ${GREEN}drink-bench cpu${NC}\n"
        ;;
    eda|chip|design)
        printf "${BLUE}${BOLD}Drink-EDA — LoongArch EDA Toolchain${NC}\n"
        printf "\n"
        printf "  ${GREEN}drink-pkg repo add drink-eda${NC}\n"
        printf "  ${YELLOW}  https://gitcode.com/H076lik/Drink-EDA/releases/download/v1.0${NC}\n"
        printf "\n"
        printf "  ${GREEN}drink-pkg repo update${NC}       Get latest packages\n"
        printf "  ${GREEN}drink-pkg search${NC}            Browse available tools\n"
        printf "  ${GREEN}drink-pkg install <name>${NC}    Install an EDA tool\n"
        printf "\n"
        printf "  Available packages:\n"
        printf "    ${YELLOW}lib-src${NC}        Runtime libraries\n"
        printf "    ${YELLOW}drink-eda-tools${NC} lfl + map_synth\n"
        printf "    ${YELLOW}yosys${NC}          Synthesis (ABC hash fixed)\n"
        printf "    ${YELLOW}openroad${NC}       PnR (read_lef fixed)\n"
        printf "    ${YELLOW}klayout${NC}        Layout editor\n"
        printf "    ${YELLOW}magic${NC}           VLSI layout\n"
        printf "    ${YELLOW}ngspice${NC}         Circuit simulation\n"
        printf "    ${YELLOW}iverilog${NC}        Verilog simulation\n"
        printf "    ${YELLOW}sky130-pdk${NC}      SkyWater 130nm PDK\n"
        printf "\n"
        printf "  Quick start:\n"
        printf "    ${GREEN}drink-pkg install lib-src yosys openroad sky130-pdk${NC}\n"
        printf "    ${GREEN}lfl config.yaml${NC}\n"
        printf "\n"
        printf "  ${YELLOW}https://gitcode.com/H076lik/Drink-EDA${NC}\n"
        ;;
        printf "${CYAN}${BOLD}Drink Linux v0.1 -- help <topic>${NC}\n"
        printf "\n"
        printf "  ${GREEN}network${NC}   Network commands\n"
        printf "  ${GREEN}pkg${NC}       Package manager + Drink-EDA\n"
        printf "  ${GREEN}eda${NC}       EDA toolchain (chip design)\n"
        printf "  ${GREEN}desktop${NC}   Desktop controls\n"
        printf "  ${GREEN}system${NC}    System info and admin\n"
        printf "  ${GREEN}bench${NC}     Performance benchmarks\n"
        printf "\n"
        printf "  ${YELLOW}drink-info${NC}       System information\n"
        printf "  ${YELLOW}drink-bench${NC}      CPU/Memory/Disk benchmark\n"
        printf "  ${YELLOW}drink-sysinfo${NC}    Hardware details\n"
        printf "  ${YELLOW}drink-desktop${NC}    Start desktop\n"
        printf "  ${YELLOW}drink-pkg list${NC}   List packages\n"
        printf "  ${YELLOW}top${NC}              View processes\n"
        printf "\n"
        printf "  SSH: ${GREEN}ssh root@<ip> -p 2222${NC} (empty password)\n"
        ;;
    *)
        printf "Unknown topic. Try: ${GREEN}help${NC} ${YELLOW}network${NC} | ${YELLOW}pkg${NC} | ${YELLOW}eda${NC} | ${YELLOW}desktop${NC} | ${YELLOW}system${NC} | ${YELLOW}bench${NC}\n"
        ;;
esac
