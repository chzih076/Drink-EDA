FROM scratch
ADD rootfs-eda.tar.gz /
ADD docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENV PDK_ROOT=/home/user/.local/share/pdk
ENV PDK=sky130A
ENV PATH="/usr/local/bin:/usr/bin:/bin:/sbin"
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/lib:/usr/lib64"
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/bin/sh"]
