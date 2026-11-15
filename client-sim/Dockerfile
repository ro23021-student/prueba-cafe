# Contexto de construcción: la carpeta sandbox_fase3/ (ver docker-compose.yml: build.context = ..)
# Así el cliente simulado usa el MISMO núcleo que la app Flutter (cliente/trazabilidad_core).
FROM dart:stable AS build
WORKDIR /src
COPY cliente/trazabilidad_core ./cliente/trazabilidad_core
COPY client-sim ./client-sim
WORKDIR /src/client-sim
RUN mkdir -p /out && dart pub get && dart compile exe bin/client_sim.dart -o /out/client_sim

# iproute2 aporta `tc`, que el cliente usa para cortar la red (modo self; requiere NET_ADMIN)
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends iproute2 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/client_sim /usr/local/bin/client_sim
ENTRYPOINT ["client_sim"]
