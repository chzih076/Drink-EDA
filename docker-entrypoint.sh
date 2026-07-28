#!/bin/sh
# Drink Linux container entrypoint
# Runs the full init sequence adapted for container environment

echo ""
echo "  ██████╗ ██████╗ ██╗███╗   ██╗██╗  ██╗"
echo "  ██╔══██╗██╔══██╗██║████╗  ██║██║ ██╔╝"
echo "  ██║  ██║██████╔╝██║██╔██╗ ██║█████╔╝ "
echo "  ██║  ██║██╔══██╗██║██║╚██╗██║██╔═██╗"
echo "  ██████╔╝██║  ██║██║██║ ╚████║██║  ██╗"
echo "  ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝"
echo ""
echo "  Drink Linux v0.1 - Container Edition"
echo "  LoongArch64"
echo ""

# Dynamic linker
ln -sf /usr/lib/ld-linux-loongarch-lp64d.so.1 /lib64/ 2>/dev/null
ln -sf /usr/lib/ld-linux-loongarch-lp64d.so.1 /lib/ld-linux-loongarch-lp64d.so.1 2>/dev/null

hostname drink 2>/dev/null

# Package manager — init and install offline packages
rm -f /var/lib/drink/db.redb 2>/dev/null
DRINK_DB=/var/lib/drink/db.redb drink-pkg init 2>/dev/null
for pkg in /packages/*.drink; do
    [ -f "$pkg" ] && drink-pkg install "$pkg" 2>/dev/null
done

# EDA library paths
export LD_LIBRARY_PATH="/usr/local/lib:/usr/lib:/usr/lib64:$LD_LIBRARY_PATH"

# SSH (dropbear) if port can be bound
echo 'root::0:0:root:/root:/bin/sh' > /etc/passwd 2>/dev/null
/usr/sbin/dropbear -B -p 2222 2>/dev/null &
echo "SSH: ssh root@localhost -p 2222 (空密码)"

echo 'PS1="\[\e[1;32m\]drink\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\\$ "' > /root/.profile 2>/dev/null
echo 'PS1="\[\e[1;32m\]drink\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\\$ "' > /etc/profile 2>/dev/null
exec /bin/sh -l
