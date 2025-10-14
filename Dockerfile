FROM alpine:3.19
RUN apk add --no-cache bash mariadb-client rsync coreutils tzdata util-linux
COPY nextcloud_db_backup.sh /usr/local/bin/
COPY rpi_home_backup.sh /usr/local/bin/
COPY rpi_home_backup.exclude /etc/rsync_exclude
RUN chmod +x /usr/local/bin/nextcloud_db_backup.sh /usr/local/bin/rpi_home_backup.sh
ENTRYPOINT ["/bin/bash", "-c"]
