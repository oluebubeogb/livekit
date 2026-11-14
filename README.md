# livekit-server

A reusable, self-hosted [LiveKit](https://livekit.io) SFU (WebRTC audio, video and screen share)
packaged for **Coolify** on a **Contabo** VPS. It is not tied to any one app: 1venue uses it today,
and any other app can connect with its own API key and secret.

- Deploys from `main`: push and Coolify redeploys.
- No secrets in git. The LiveKit config is generated from Coolify environment variables.
- Pinned to LiveKit `v1.13.11`, the latest stable release as of Nov 2026. Bump `LIVEKIT_VERSION` to upgrade.

```
.
├── docker-compose.yml      # the Coolify resource (LiveKit, host networking, healthcheck)
├── .env.example            # every variable, with comments
├── livekit.yaml.example    # what the generated config looks like (reference only)
└── scripts/
    ├── generate-keys.sh    # make an API key + secret for an app
    └── check.sh            # health + credential check
```

---

## 1. Pick a server

LiveKit's load is CPU and bandwidth, not RAM. Give it **its own VPS** so video never competes with
your app's CPU.

| Use | Contabo suggestion |
|---|---|
| A few small meetings | Cloud VPS 10 (4 vCPU / 8 GB) |
| Webinars, many cameras | Cloud VPS 20/30, or a **Cloud VDS** (dedicated cores) for steady CPU |

Install Coolify on it (or add it as a **server** to your existing Coolify).

## 2. DNS

Create these records at your DNS provider. If you use Cloudflare, set them to **DNS only (grey cloud)**,
because Cloudflare's proxy cannot carry WebRTC/UDP.

| Name | Type | Value | Needed for |
|---|---|---|---|
| `rtc.1venue.live` | A | the VPS public IPv4 | signalling (`wss://`), always |
| `turn.1venue.live` | A | the VPS public IPv4 | TURN/TLS only (optional, section 7) |

(These are 1venue's production names. Another app reusing this server can point its own `wss://` name at it the same way.)

## 3. Firewall (Contabo has no cloud firewall by default, so this is the VPS's own firewall)

| Port | Protocol | Purpose |
|---|---|---|
| 80, 443 | TCP | Coolify proxy: HTTPS signalling and Let's Encrypt (usually already open) |
| 7881 | TCP | ICE over TCP when UDP is blocked |
| 50000–60000 | UDP | WebRTC media (the main path) |
| 3478 | UDP | TURN/UDP (relay for strict NATs) |
| 30000–30100 | UDP | TURN relay ports |

```bash
sudo ufw allow 80,443/tcp
sudo ufw allow 7881/tcp
sudo ufw allow 50000:60000/udp
sudo ufw allow 3478/udp
sudo ufw allow 30000:30100/udp
sudo ufw status
```

Do **not** open 7880 or 5349. Only Coolify's proxy talks to them, locally.
If you ever add a Contabo firewall (or move to Hetzner, AWS and so on), open the same ports there too.
A closed port here is the #1 cause of "it connects but nobody sees video".

## 4. Create keys (one pair per app)

```bash
./scripts/generate-keys.sh
# API Key:     APIxxxxxxxxxxxx
# API Secret:  xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Or: `docker run --rm livekit/livekit-server:v1.13.11 generate-keys`.

Put every app's pair into **one** `LIVEKIT_KEYS` variable:

```
# one app
LIVEKIT_KEYS=APIxxxxxxxxxxxx: <secret>
# several apps (a YAML map on one line, the space after each colon is required)
LIVEKIT_KEYS={APIxxxxxxxxxxxx: <secret-for-1venue>, APIyyyyyyyyyyyy: <secret-for-other-app>}
```

Giving each app its own pair means you can revoke one app (remove its pair, redeploy) without touching the others.

## 5. Deploy on Coolify

1. Push this folder to its own git repo (for example `livekit-server`, branch `main`).
2. In Coolify: **Projects → (your project) → + New → Private/Public Repository**, pick the repo and branch `main`.
3. **Build Pack: Docker Compose**, **Docker Compose Location:** `/docker-compose.yml`.
4. **Environment Variables:** copy them from `.env.example`. At minimum set:
   ```
   LIVEKIT_KEYS=APIxxxxxxxxxxxx: <secret>
   NODE_IP=<your VPS public IPv4>
   LIVEKIT_DOMAIN=rtc.1venue.live
   ```
5. **Domains:** on the `livekit` service, set `https://rtc.1venue.live:7880`.
   In Coolify, `:7880` means "proxy this domain to port 7880". The public URL stays `https://rtc.1venue.live` on 443.
6. **Deploy.** The logs should show `starting LiveKit server … "portHttp": 7880` and `Starting TURN server`.
7. Turn on **Auto Deploy** (webhook) so every push to `main` redeploys.

**If Coolify won't attach a domain to a host-network service**, use one of these:

- **Option A: published ports.** Remove `network_mode: host` and add
  `ports: ["7881:7881", "3478:3478/udp", "50000-60000:50000-60000/udp", "30000-30100:30000-30100/udp"]`.
  It works, but Docker creates a NAT rule for each port. For small events shrink the range,
  for example to 50000–50500 in both the env (`RTC_PORT_END`) and `ports` (about 2 ports per participant).
- **Option B: Traefik dynamic config.** Keep host mode and add a file under **Servers → Proxy → Dynamic Configurations**:
  ```yaml
  http:
    routers:
      livekit:
        entryPoints: [https]
        rule: "Host(`rtc.1venue.live`)"
        service: livekit
        tls:
          certResolver: letsencrypt
    services:
      livekit:
        loadBalancer:
          servers:
            - url: "http://host.docker.internal:7880"
  ```

WebSockets pass through Coolify's Traefik (or Caddy) by default.

## 6. Health check

- The container has its own healthcheck (`GET http://127.0.0.1:7880/` returns `OK`). Coolify shows it as healthy or unhealthy.
- From anywhere:
  ```bash
  ./scripts/check.sh rtc.1venue.live                      # signalling + TLS
  ./scripts/check.sh rtc.1venue.live APIxxxx <secret>     # also proves that key/secret pair works
  ```
- Media (UDP, TCP and TURN) can only be tested from a browser: open <https://livekit.io/connection-test>,
  enter `wss://rtc.1venue.live` and a token (or just open a room in your app). Then test from a phone on **mobile data**.

## 7. TURN over TLS (optional)

TURN/UDP (3478) plus ICE/TCP (7881) covers almost everyone. TURN/TLS is for networks that only allow
HTTPS, such as some corporate or hotel Wi-Fi. LiveKit always tells clients to use `turns:<TURN_DOMAIN>:443`,
so port 443 on a **separate** name (`turn.1venue.live`) must reach LiveKit:

1. Add the `turn.1venue.live` A record (grey cloud).
2. In the LiveKit resource env set `TURN_DOMAIN=turn.1venue.live` and `TURN_TLS_PORT=5349`, then redeploy.
   LiveKit now accepts plain TCP on 5349 (`external_tls: true`). Keep 5349 closed on the firewall.
3. In Coolify go to **Servers → Proxy → Dynamic Configurations** and add `turn.yaml`. Traefik terminates TLS
   with a Let's Encrypt cert and passes the stream to LiveKit:
   ```yaml
   tcp:
     routers:
       livekit-turn:
         entryPoints: [https]
         rule: "HostSNI(`turn.1venue.live`)"
         service: livekit-turn
         tls:
           certResolver: letsencrypt
     services:
       livekit-turn:
         loadBalancer:
           servers:
             - address: "host.docker.internal:5349"
   ```
   Coolify's default entrypoint and resolver names are `https` and `letsencrypt`. Check yours under **Proxy → Configuration**.
4. Test it on the connection-test page with "TURN/TLS". If it fails, check that `host.docker.internal` resolves inside
   the proxy container. Otherwise use the server's Docker bridge IP (usually `172.17.0.1`).

## 8. Connect an app

Every app needs three values. They are the same for 1venue and anything else:

```
LIVEKIT_URL=wss://rtc.1venue.live
LIVEKIT_API_KEY=APIxxxxxxxxxxxx        # this app's own pair from LIVEKIT_KEYS
LIVEKIT_API_SECRET=<secret>
```

The app's server mints a short-lived JWT access token with a LiveKit server SDK (`livekit-server-sdk` for Node,
`livekit-api` for Python, …). The browser connects to `LIVEKIT_URL` with that token. Rooms are created
automatically when the first person joins (`auto_create: true`), so there is no per-app setup on this server.

**1venue:** set the three variables on the 1venue Coolify resource, redeploy, and check `https://<1venue>/api/config`.
It should show `"livekitConfigured": true`. In the 1venue container you can also run `npm run livekit:check`.

## 9. Scaling later

- **Up first:** more vCPU (or a VDS) carries more video. Raise `LIVEKIT_MEM_LIMIT` only if the logs say so.
- **Out later:** run this same repo on a second VPS, point both at one shared Redis
  (uncomment the `redis:` blocks in `docker-compose.yml` and set `LIVEKIT_REDIS_ADDRESS` and `LIVEKIT_REDIS_PASSWORD`),
  and put the nodes behind one signalling domain. LiveKit then places each room on one node automatically.

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `check.sh` says signalling FAILED | DNS or the Coolify domain is wrong | A record, and domain `https://rtc.1venue.live:7880` (or Option B) |
| Credentials rejected (401) | That key/secret isn't in `LIVEKIT_KEYS` | Fix `LIVEKIT_KEYS` (note the space after `:`), redeploy |
| Deploy fails: "Set NODE_IP…" or "Set LIVEKIT_KEYS…" | A required env var is missing | Add it in Coolify |
| Joins, but video stays black | UDP 50000–60000 or TCP 7881 closed, or wrong `NODE_IP` | Section 3; set `NODE_IP` to the public IPv4 |
| Works for ~10 s, then drops | A private IP is being advertised | `NODE_IP` = public IPv4 (`USE_EXTERNAL_IP=false`) |
| Works on Wi-Fi but not on mobile data | Strict NAT | Open 3478/udp and 30000–30100/udp. Optionally TURN/TLS (section 7) |
| Browser: `/rtc/v1 … 404`, negotiation timeout | Server too old for the client SDK | Keep `LIVEKIT_VERSION` ≥ v1.13.10 |
| High CPU | Many video publishers | Lower the app's video bitrate/fps, or move to more or dedicated cores |
