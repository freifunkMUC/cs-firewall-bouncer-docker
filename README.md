# cs-firewall-bouncer-docker

The [CrowdSec firewall bouncer](https://github.com/crowdsecurity/cs-firewall-bouncer)
as a container image, for blocking banned addresses in the network namespace
of a container or pod, e.g. as a sidecar next to a service that binds its
ports itself.

```
ghcr.io/freifunkmuc/cs-firewall-bouncer-docker:v0.0.38
```

- The upstream release binary, checked against the SHA-256 that GitHub
  computed for the release asset, on `gcr.io/distroless/static-debian13`:
  no shell, no package manager, about 24 MB. `linux/amd64` and `linux/arm64`.
- **nftables mode only.** The bouncer talks netlink itself; the iptables and
  ipset tools are not in the image.
- Needs `NET_ADMIN` and nothing else; runs with a read-only root filesystem.
- Configuration: `/config/crowdsec-firewall-bouncer.yaml`. The bouncer expands
  `${VAR}` from its environment, so the API key can come from a secret
  (`example/crowdsec-firewall-bouncer.yaml`).

## Tags

| Tag | Moves |
|---|---|
| `v0.0.38-r1`, `sha-<commit>` | never |
| `v0.0.38`, `latest` | with every rebuild |

Pin `<version>@sha256:<digest>`.

## Verify an image

Every published image has a signed build provenance attestation:

```sh
gh attestation verify oci://ghcr.io/freifunkmuc/cs-firewall-bouncer-docker@sha256:<digest> \
  --repo freifunkMUC/cs-firewall-bouncer-docker
```

## Run

```sh
docker run -d --name bouncer \
  --network container:<service> \
  --cap-drop ALL --cap-add NET_ADMIN --read-only --security-opt no-new-privileges \
  -e API_URL=http://crowdsec:8080/ -e API_KEY=<bouncer key> \
  -v ./crowdsec-firewall-bouncer.yaml:/config/crowdsec-firewall-bouncer.yaml:ro \
  ghcr.io/freifunkmuc/cs-firewall-bouncer-docker:v0.0.38
```

Kubernetes (sidecar):

```yaml
securityContext:
  runAsUser: 0
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
    add: ["NET_ADMIN"]
  seccompProfile:
    type: RuntimeDefault
```

Key with `cscli bouncers add <name>`. The bouncer fails open: without the
LAPI it keeps the last list.

## Updates

- New upstream release: `upstream-watch` opens an issue with the three `ARG`
  values for the Dockerfile.
- Base image and action digests: Dependabot.
- A push to `main` that changes the Dockerfile or the workflow publishes
  `<version>-r<n+1>`; `test/smoke.sh <image>` runs first (fake LAPI with two
  bans, checks the nftables sets).

## Licence

MIT. The bouncer itself is MIT, © CrowdSec.
