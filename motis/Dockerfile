FROM alpine:3.20

ARG TARGETARCH=amd64
ARG MOTIS_VERSION=v2.10.2

RUN apk add --no-cache bzip2 ca-certificates curl

RUN curl -fsSL "https://github.com/motis-project/motis/releases/download/${MOTIS_VERSION}/motis-linux-${TARGETARCH}.tar.bz2" \
  | tar -xj -C / \
  && test -x /motis

RUN addgroup -S motis \
  && adduser -S motis -G motis \
  && mkdir -p /data \
  && chown -R motis:motis /data

EXPOSE 8080
VOLUME ["/data"]

USER motis
CMD ["/motis", "server", "/data"]
