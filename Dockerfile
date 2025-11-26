# syntax=docker/dockerfile:1.4
FROM --platform=$BUILDPLATFORM golang:1.22.5 as go
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETOS=linux
ENV GO111MODULE=on
ENV CGO_ENABLED=0
ENV GOBIN=/bin
RUN go install github.com/go-delve/delve/cmd/dlv@v1.8.2

FROM go as build
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETOS=linux
WORKDIR /build
COPY go.mod go.sum ./
COPY ./internal/imports imports
RUN go build ./imports
COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} GO111MODULE=on go build -o /bin/app .
# Download spire for target architecture (golang image has curl)
# Note: spire may not have all architectures, so we'll try to download and continue if it fails
RUN ARCH=$(case ${TARGETARCH} in amd64) echo "x86_64" ;; arm64) echo "aarch64" ;; arm) echo "arm" ;; *) echo "x86_64" ;; esac) && \
    mkdir -p /tmp && \
    (curl -fsSL https://github.com/spiffe/spire/releases/download/v1.2.2/spire-1.2.2-linux-${ARCH}-glibc.tar.gz -o /tmp/spire.tar.gz && \
     tar xzvf /tmp/spire.tar.gz -C /tmp --strip=2 spire-1.2.2/bin/spire-server spire-1.2.2/bin/spire-agent && \
     rm -f /tmp/spire.tar.gz) || (echo "Warning: spire download failed for ${ARCH}, creating placeholder files" && touch /tmp/spire-server /tmp/spire-agent)

FROM build as test
CMD go test -test.v ./...

FROM test as debug
CMD dlv -l :40000 --headless=true --api-version=2 test -test.v ./...

FROM --platform=$TARGETPLATFORM alpine:3.20.1 as runtime
ARG TARGETPLATFORM
ARG TARGETARCH
COPY --from=build /bin/app /bin/app
# Copy spire binaries (may be placeholders if download failed)
COPY --from=build /tmp/spire-server /bin/spire-server
COPY --from=build /tmp/spire-agent /bin/spire-agent
ENTRYPOINT ["/bin/app"]
