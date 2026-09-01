FROM powerdns/pdns-auth-50:latest

# Rebuild with `docker compose build --pull` (deploy.sh does this) so the base
# image is refreshed. A stale cached layer is why the server ran a build with
# an open "PowerDNS Security Update Mandatory" advisory for 42 log cycles.

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends gettext-base \
 && rm -rf /var/lib/apt/lists/*

COPY pdns.conf.template /etc/pdns/pdns.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
