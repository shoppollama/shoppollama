# Build stage
FROM elixir:1.15-alpine AS builder

# Install build dependencies
RUN apk add --no-cache build-base npm git python3

# Prepare build directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set environment for building
ENV MIX_ENV=prod

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Install assets
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm --prefix ./assets ci
COPY assets/ assets/
RUN npm --prefix ./assets run build
RUN mix assets.deploy

# Copy source code
COPY lib/ lib/
COPY priv/ priv/

# Compile application
RUN mix compile

# Prepare release
COPY config/runtime.exs config/
RUN mix release

# Release stage
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

# Create non-root user
RUN addgroup -g 1000 -S app && \
    adduser -S app -G app

# Copy built application from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/shoppollama ./

# Change user
USER app

# Expose port
EXPOSE 4000

# Start the application
CMD ["bin/shoppollama", "start"]
