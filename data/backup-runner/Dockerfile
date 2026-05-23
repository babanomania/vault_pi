FROM alpine:3.20

# Tools needed by the backup-runner:
#   borgbackup  - deduplicating encrypted archives
#   rclone      - sync to dropbox / s3 / etc
#   sqlite      - online .backup of the vaultwarden DB for a consistent snapshot
#   curl        - telegram notifications
#   bash        - scripting (alpine ships ash; bash gives us trap + arrays)
#   tini        - PID 1 signal handling so `docker compose run --rm` exits clean
RUN apk add --no-cache \
      borgbackup \
      rclone \
      sqlite \
      curl \
      bash \
      tini

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# All long-lived configuration is supplied via Docker secrets at /run/secrets.
# These env vars wire borg/rclone into the secret files without ever placing
# the values in the process environment.
ENV BORG_REPO=/repo
ENV BORG_PASSCOMMAND="cat /run/secrets/borg_passphrase"
ENV RCLONE_CONFIG=/run/secrets/rclone.conf

ENTRYPOINT ["/sbin/tini", "--", "/scripts/entrypoint.sh"]
CMD ["backup"]
