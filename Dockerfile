# ── Stage 1: Build ─────────────────────────────────────────────────────────
FROM ruby:3.3.5-slim AS builder

# System deps for native gem compilation
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    libvips-dev \
    git \
    curl \
    gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# Node 20 + Yarn (needed for asset pipeline)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems first (layer cache — only rebuilds if Gemfile changes)
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' \
    && bundle install --jobs 4 --retry 3

# Copy app source
COPY . .

# Precompile assets
RUN SECRET_KEY_BASE=placeholder \
    RAILS_ENV=production \
    bundle exec rails assets:precompile

# ── Stage 2: Runtime ────────────────────────────────────────────────────────
FROM ruby:3.3.5-slim AS runtime

# Runtime-only system deps
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libpq-dev \
    libvips-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd --system rails \
    && useradd --system --gid rails --home /app rails

WORKDIR /app

# Copy gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy compiled app from builder
COPY --from=builder --chown=rails:rails /app /app

# Switch to non-root user
USER rails

# Expose Puma port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/up || exit 1

# Start Puma
# Entrypoint: migrate + seed + start
# Seeds are idempotent (guarded at top of seeds.rb) so safe to run on every deploy
CMD ["sh", "-c", "bundle exec rails db:migrate && bundle exec rails db:seed && bundle exec puma -C config/puma.rb"]