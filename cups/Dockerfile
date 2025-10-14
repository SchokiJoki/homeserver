# Custom CUPS image tailored for the Kyocera ECOSYS P2040dn printer
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    CUPS_CONFIG_DIR=/etc/cups \
    LANG=de_DE.UTF-8 \
    LC_ALL=de_DE.UTF-8

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       cups-daemon cups-client \
       cups-filters \
       avahi-daemon dbus \
       locales \
    && sed -i 's/# de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

COPY ["Kyocera_P2040dn.ppd", "/opt/cups/ppd/Kyocera_ECOSYS_P2040dn.ppd"]
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 631
VOLUME ["/etc/cups", "/var/log/cups", "/var/spool/cups"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/cupsd", "-f"]
