# Stage 1: Build the Go binary
# Use a Go version that matches or exceeds your go.mod requirement
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG TARGETOS=linux
ARG TARGETARCH=arm64
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /app/binary main.go

# Stage 2: Create a minimal final image
FROM alpine:latest
WORKDIR /
# The binary name in the consumer should be /event-consumer, and /event-publisher for the publisher.
# This generic Dockerfile works because the script renames the output based on the directory.
# Let's make it more explicit for clarity.
COPY --from=builder /app/binary /app-binary
EXPOSE 8080
CMD ["/app-binary"]