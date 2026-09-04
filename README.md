# is-an.ai DNS infrastructure

Authoritative DNS for `is-an.ai`, run as a **hidden master**: PowerDNS holds the
zones, Hurricane Electric's `ns1`–`ns5.he.net` are the public nameservers and
pull over TSIG-authenticated AXFR. This host appears in no NS record, so
resolvers never query it directly.

It does still take inbound DNS from the secondaries: they poll SOA over
**UDP/53** on the zone's refresh timer to decide whether to re-transfer. That
port must stay reachable from them. Restrict it by source IP at the security
group — never by unpublishing it. Blocking that path is invisible until the
zone's `expire` elapses, and then the domain stops resolving entirely.

```
                 NOTIFY ─────────────►
  ┌────────────┐              ┌──────────────┐         ┌─────────┐
  │  pdns-auth │◄──── AXFR ───│ ns1-5.he.net │◄── DNS ─│ resolver│
  │  (hidden)  │   TCP/TSIG   └──────────────┘         └─────────┘
  └─────┬──────┘
        │ data network
  ┌─────▼──────┐   ┌────────┐
  │  pdns-db   │◄──│ backup │  daily pg_dump → $DATA_ROOT/backups
  └────────────┘   └────────┘
        ops network
  ┌────────────┐   ┌───────────────┐
  │   gatus    │   │ github-runner │
  └────────────┘   └───────────────┘
```

## Layout

```
compose.yml           all five services, one project, two networks
deploy.sh             build, start, wait for health
pdns/                 Dockerfile, entrypoint, pdns.conf.template
gatus/config.yaml     monitoring + Slack alerting
runner/               self-hosted GitHub Actions runner
backup/backup.sh      pg_dump loop
```

Post-deploy verification and the packet-capture / trend tools are deployment
specific — they hardcode container names, secondary nameservers and thresholds
for one installation — so they are kept with that installation's runbooks
rather than here.

Persistent data lives at `$DATA_ROOT`, **outside this repo**, so cloning or
cleaning the working tree can never touch the database.

## Deploy

```bash
cd <deploy-dir>
./deploy.sh
```

`deploy.sh` refuses to run against a dirty working tree. Editing files directly
on the server is what produced the drift this layout replaces — change it here,
commit, push, pull.

`docker compose down` takes production DNS with it. For single services use
`docker compose up -d <service>` or `docker compose restart <service>`.

## First-time setup

```bash
cp .env.example .env              # DATA_ROOT, DB creds, API key, gatus auth
cp runner/.env.example runner/.env
```

Both files, not just the first. `runner/.env` is referenced by `env_file:`, and
Compose validates every `env_file` while parsing the project — so without it
even `docker compose up -d pdns-db` fails. The runner cannot be set up after
DNS is running; it has to exist before anything starts.

gatus password hash:

```bash
htpasswd -bnBC 12 "" 'yourpassword' | tr -d ':\n' | base64 -w0
```

### Database schema

An empty `$DATA_ROOT` means an empty database, and nothing about that is
loud: `pg_isready` does not look at tables and `pdns_control rping` only pings
the control socket, so both containers report **healthy** while PowerDNS
serves no zone at all. `deploy.sh` loads the gpgsql schema when
`public.domains` is missing, taking it from inside the PowerDNS image so it
always matches the version being deployed. An existing installation skips it.

That path only runs on a fresh `$DATA_ROOT` — a new host, a moved disk, a
restore. To do it by hand:

```bash
docker run --rm --entrypoint cat is-an-ai/pdns-auth:local \
  /usr/local/share/doc/pdns/schema.pgsql.sql \
  | docker compose exec -T pdns-db psql -U "$PDNS_DB_USER" -d "$PDNS_DB_NAME"
```

### Verifying locally

Two settings exist so that a local run cannot reach production, and both
default to the server's behaviour when unset:

| variable | set it locally to | why |
|---|---|---|
| `PDNS_API_BIND` | `127.0.0.1:18081` | `ssh -L 8081:...` to the server is routine here. If a tunnel already holds 8081, publishing succeeds and `docker port` looks right, but API calls reach **production** |
| `PDNS_ALSO_NOTIFY` | empty | otherwise a local zone change sends NOTIFY to the real secondary |

`webserver-allow-from` may also need widening: the default covers Docker's
`172.16.0.0/12` bridge range, but OrbStack allocates `192.168.x`, and a request
from outside the range is dropped with no response and no log
(`webserver-loglevel=none`). Set `PDNS_WEBSERVER_ALLOW_FROM` to add your range.

## Monitoring

gatus is bound to localhost. Reach it through a tunnel:

```bash
ssh -L 8080:127.0.0.1:8080 <user>@<host>   # then http://localhost:8080
```

It checks the PowerDNS API, local resolution, and — most importantly — that
`ns1.he.net` is actually serving `is-an.ai`, which is the end-to-end contract a
hidden master has to meet. Failures alert to Slack.

Those alerts go to the real channel, so blank `SLACK_WEBHOOK_URL` in the shell
when running gatus locally — its local-resolution check fails until the zone is
loaded, and two failures are enough to page.

## Backups

`backup` dumps daily to `$DATA_ROOT/backups`, keeps 14, writes a `.sha256`
alongside each, and only renames a dump into place once it completes. Restore:

```bash
gzip -dc pdns-YYYY-MM-DD-HHMMSS.sql.gz | \
  docker compose exec -T pdns-db psql -U "$PDNS_DB_USER" -d "$PDNS_DB_NAME"
```

These dumps are not offsite. Copy them off the host — an instance failure takes
the database and every backup with it.

## Before changing anything the secondaries depend on

`allow-axfr-ips`, `also-notify`, UDP/53 reachability and the NOTIFY path are all
load-bearing for zone transfer, and every failure mode on them is delayed by
`expire` — a week, with the SOA above. A mistake here looks fine until it
suddenly isn't.

Do not narrow UDP/53 by guessing which addresses the secondaries use. They are
not necessarily the NS records: a provider may transfer and poll from hosts that
appear nowhere in the zone. Capture the real sources over a window longer than
the SOA refresh interval, compare them against `allow-axfr-ips` and
`also-notify`, and only then touch a firewall rule.

## Stack

| | |
|---|---|
| DNS | PowerDNS Authoritative 5.0 (gpgsql backend) |
| Database | PostgreSQL 17 |
| Secondary | Hurricane Electric, AXFR over TSIG (hmac-sha256) |
| Monitoring | gatus → Slack |
| CI | self-hosted GitHub Actions runner |

DNSSEC is **not** currently enabled: `gpgsql-dnssec=yes` is set but no keys are
provisioned (`cryptokeys` is empty), so zones are served unsigned.
