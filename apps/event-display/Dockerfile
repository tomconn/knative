# Dockerfile

# --- Stage 1: The Builder ---
# This stage uses the official Go image to compile our application.
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder

# Set the working directory inside the container
WORKDIR /app

# Copy go.mod and go.sum files first to leverage Docker's layer caching.
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the application source code (which is just main.go in this case).
COPY . .

# Build the application. The source is in the current directory (`.`).
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -v -o /app/event-display .


# --- Stage 2: The Final Image ---
# This stage uses a "distroless" image for a minimal, secure final image.
FROM gcr.io/distroless/static-debian12

# Set a non-root user for security best practices.
USER nonroot:nonroot

# Set the working directory
WORKDIR /

# Copy ONLY the compiled binary from the 'builder' stage.
COPY --from=builder /app/event-display .

# Expose the port our application listens on.
EXPOSE 8080

# The command that will be run when the container starts.
ENTRYPOINT ["/event-display"]