# Этап сборки
FROM --platform=$BUILDPLATFORM golang:alpine AS builder
ARG TARGETOS
ARG TARGETARCH
ARG TAG   # тэг или коммит
ARG WITH_GVISOR=0  # 1 - включить тег with_gvisor
ARG BUILDTIME
ARG AMD64VERSION

# Устанавливаем зависимости
RUN apk add --no-cache git make

# Клонируем репозиторий
RUN git clone https://github.com/MetaCubeX/mihomo.git /src
WORKDIR /src

# Переключаемся на нужный тэг или коммит
RUN git switch $TAG --detach
RUN echo "Updating version.go with TAG=${TAG}-fakettl and BUILDTIME=${BUILDTIME}" && \
    sed -i "s|Version\s*=.*|Version = \"${TAG}-fakettl\"|" constant/version.go && \
    sed -i "s|BuildTime\s*=.*|BuildTime = \"${BUILDTIME}\"|" constant/version.go

# --- Добавляем helper-файл в пакет dns ---
RUN cat > dns/envttl.go <<'EOF'
package dns

import (
  "os"
  "strconv"
)

func fakeipTTL() int {
  if v := os.Getenv("TTL_FAKEIP"); v != "" {
    if i, err := strconv.Atoi(v); err == nil && i > 0 {
      return i
    }
  }
  return 1
}
EOF

# --- Патчим middleware.go: setMsgTTL(msg, 1) -> setMsgTTL(msg, uint32(fakeipTTL())) ---
RUN awk 'BEGIN{done=0} { \
  if(!done && $0 ~ /setMsgTTL\([[:space:]]*msg,[[:space:]]*1[[:space:]]*\)/){ \
    sub(/setMsgTTL\([[:space:]]*msg,[[:space:]]*1[[:space:]]*\)/, "setMsgTTL(msg, uint32(fakeipTTL()))"); done=1 \
  } \
  print \
} END { if(done==0){ exit 1 } }' dns/middleware.go > /tmp/mw.go && \
    mv /tmp/mw.go dns/middleware.go && \
    grep -q 'setMsgTTL(msg, uint32(fakeipTTL()))' dns/middleware.go

  
# Формируем список build tags и собираем
RUN BUILD_TAGS="" && \
    if [ "$WITH_GVISOR" = "1" ]; then BUILD_TAGS="with_gvisor"; fi && \
    echo "Building with tags: $BUILD_TAGS" && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        echo "Setting GOAMD64=$AMD64VERSION for amd64"; \
        CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH GOAMD64=$AMD64VERSION \
        go build -tags "$BUILD_TAGS" -trimpath -ldflags "-w -s -buildid=" -o /out/mihomo .; \
    else \
        CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
        go build -tags "$BUILD_TAGS" -trimpath -ldflags "-w -s -buildid=" -o /out/mihomo .; \
    fi


# Финальный минимальный образ
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata nftables iptables iptables-legacy && \
    rm -vrf /var/cache/apk/* && \
    # # IPv4
    rm /usr/sbin/iptables /usr/sbin/iptables-save /usr/sbin/iptables-restore && \
    ln -s /usr/sbin/iptables-legacy /usr/sbin/iptables && \
    ln -s /usr/sbin/iptables-legacy-save /usr/sbin/iptables-save && \
    ln -s /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore

# ENV DISABLE_NFTABLES=1

COPY --from=builder /out/mihomo /mihomo
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
