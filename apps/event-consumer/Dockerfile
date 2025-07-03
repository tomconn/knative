# Stage 1: Build the Go binary
# Use a Go version that matches or exceeds your go.mod requirement
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG TARGETOS=linux
ARG TARGETARCH=arm64
# Correctly reference the output binary name
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /event-consumer main.go

# Stage 2: Create a minimal final image
FROM alpine:latest
WORKDIR /
COPY --from=builder /event-consumer /event-consumer
EXPOSE 8080
CMD ["/event-consumer"]