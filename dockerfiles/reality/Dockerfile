# builder
FROM golang:alpine AS builder

WORKDIR /reality

COPY ./repo/ .

# 构建应用
RUN go mod download -x && \
    go build -v -o xray ./main/ 

# runner
FROM alpine:latest AS runner

WORKDIR /reality

ENV DEST="" \
    SERVERNAMES="" \
    EXTERNAL_PORT="" \
    SOCKS5_ENABLED="false" \
    SOCKS5_LISTEN="0.0.0.0" \
    SOCKS5_PORT="38442" \
    SOCKS5_USER="" \
    SOCKS5_PASS="" \
    SOCKS5_UDP="true" \
    SOCKS5_ALLOW_NO_AUTH="false" \
    TZ=Asia/Shanghai

COPY ./entrypoint.sh /
COPY ./config.json /
COPY --from=builder /reality/xray /

RUN apk add --no-cache tzdata ca-certificates jq curl libqrencode-tools && \
    mkdir -p /var/log/xray && \
    wget -O /geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat && \
    wget -O /geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
