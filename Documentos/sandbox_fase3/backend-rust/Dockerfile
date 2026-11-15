FROM rust:1-slim AS build
ENV CARGO_NET_RETRY=10 CARGO_HTTP_TIMEOUT=120
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && touch src/lib.rs \
    && cargo build --release && rm -rf src
COPY src ./src
RUN touch src/main.rs src/lib.rs && cargo build --release
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/release/backend-rust /usr/local/bin/backend-rust
EXPOSE 8080
CMD ["backend-rust"]
