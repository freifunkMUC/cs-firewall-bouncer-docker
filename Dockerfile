# syntax=docker/dockerfile:1

# The upstream release binary (static) on distroless: no shell, no package
# manager. The fetch stage runs on the build platform and only downloads and
# checks the tarball for the target architecture.
FROM --platform=$BUILDPLATFORM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS fetch

# Bumped together, from the release's asset digests (see upstream-watch).
ARG VERSION=v0.0.38
ARG SHA256_AMD64=3cb7ca302438ede690849218d585dee6cbba7915982f79f3dd45024a9eced31e
ARG SHA256_ARM64=5da2f17c05d042748fbc8eed9b8c3dfaeeac571c81b087a600fa2ba226c2116c
ARG TARGETARCH

RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) sum=$SHA256_AMD64 ;; \
      arm64) sum=$SHA256_ARM64 ;; \
      *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    wget -q -O /tmp/bouncer.tgz \
      "https://github.com/crowdsecurity/cs-firewall-bouncer/releases/download/$VERSION/crowdsec-firewall-bouncer-linux-$TARGETARCH.tgz"; \
    echo "$sum  /tmp/bouncer.tgz" | sha256sum -c -; \
    mkdir /tmp/x; \
    tar -xzf /tmp/bouncer.tgz -C /tmp/x; \
    install -m 0755 "/tmp/x/crowdsec-firewall-bouncer-$VERSION/crowdsec-firewall-bouncer" /crowdsec-firewall-bouncer

FROM gcr.io/distroless/static-debian13@sha256:448810357cc8e67b7208988abdba0f5ec3d3aebee0a5b13eb624979792cffc0f

COPY --from=fetch /crowdsec-firewall-bouncer /usr/local/bin/crowdsec-firewall-bouncer

ENTRYPOINT ["/usr/local/bin/crowdsec-firewall-bouncer", "-c", "/config/crowdsec-firewall-bouncer.yaml"]
