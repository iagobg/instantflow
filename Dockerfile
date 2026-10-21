FROM hexpm/elixir:1.19.5-erlang-28.5.0.2-debian-bookworm-20260623-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod --check-locked
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile
RUN mix assets.setup
COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.deploy
COPY config/runtime.exs config/runtime.exs
RUN mix release

# Same Debian release as the builder for native library compatibility.
FROM debian:bookworm-20260623-slim AS runner
RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV LANG=C.UTF-8 MIX_ENV=prod PHX_SERVER=true PORT=4000
COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/instantflow ./
USER nobody:nogroup
EXPOSE 4000
CMD ["/app/bin/instantflow", "start"]
