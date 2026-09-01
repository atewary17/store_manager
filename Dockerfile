# syntax=docker/dockerfile:1
#
# Store Manager — production image.
#
# Base is ruby:3.3.5-slim (Debian 12 "bookworm"). That matters on ARM: the
# wkhtmltopdf-binary gem ships a debian_12_arm64 build, so this base matches the
# binary exactly on OCI Ampere. Builds natively on arm64 and amd64.
#
#   docker build -t store-manager .
#   docker build --platform linux/arm64 -t store-manager .   # cross-build

# ── Stage 1: Build ──────────────────────────────────────────────────────────
# Compiles native gems and precompiles assets. None of this tooling ships in
# the final image.
FROM ruby:3.3.5-slim AS builder

# build-essential + libpq-dev: compiling pg and other native extensions.
# git: some gems resolve from git sources.
# No Node/Yarn: the app uses importmap-rails, so assets need no JS runtime.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      git \
      pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Gems first, in their own layer: this only rebuilds when the Gemfile changes,
# not on every source edit.
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' \
    && bundle install --jobs 4 --retry 3 \
    && rm -rf /usr/local/bundle/cache

COPY . .

# SECRET_KEY_BASE is only needed to satisfy boot during precompile; the real one
# comes from the environment at runtime.
RUN SECRET_KEY_BASE=placeholder RAILS_ENV=production \
    bundle exec rails assets:precompile

# ── Stage 2: Runtime ────────────────────────────────────────────────────────
FROM ruby:3.3.5-slim AS runtime

# Runtime system dependencies. Each one is load-bearing:
#
#   imagemagick      InvoiceScan::ImagePreprocessor shells out via mini_magick.
#                    NOT libvips — that is a different library, and MiniMagick
#                    fails *silently* without ImageMagick, degrading every scan.
#   poppler-utils    provides pdftoppm; InvoiceScan::Document raises without it.
#   libxrender1 …    wkhtmltopdf's shared libraries (wicked_pdf).
#   fonts-dejavu-core  wkhtmltopdf renders blank boxes with no fonts installed.
#   libpq5           Postgres client library (runtime only, not libpq-dev).
#   curl             used by HEALTHCHECK below.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      imagemagick \
      poppler-utils \
      libpq5 \
      libxrender1 \
      libfontconfig1 \
      libxext6 \
      libjpeg62-turbo \
      fonts-dejavu-core \
      tzdata \
      curl \
    && rm -rf /var/lib/apt/lists/*

# Debian's ImageMagick policy caps memory at 256MiB. One A4 page at 300 DPI
# through ImagePreprocessor (2x upscale to ~4030x5700) peaks at ~513MB, so the
# defaults make it spill to disk or fail outright. Raise the limits that the
# preprocessing pipeline actually touches.
RUN set -eux; \
    POLICY=/etc/ImageMagick-6/policy.xml; \
    if [ -f "$POLICY" ]; then \
      sed -i \
        -e 's/name="memory" value="[^"]*"/name="memory" value="1GiB"/' \
        -e 's/name="map" value="[^"]*"/name="map" value="2GiB"/' \
        -e 's/name="area" value="[^"]*"/name="area" value="512MP"/' \
        -e 's/name="disk" value="[^"]*"/name="disk" value="4GiB"/' \
        -e 's/name="width" value="[^"]*"/name="width" value="64KP"/' \
        -e 's/name="height" value="[^"]*"/name="height" value="64KP"/' \
        "$POLICY"; \
    fi

# Run as a non-root user.
RUN groupadd --system rails \
    && useradd --system --gid rails --home /app rails

WORKDIR /app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder --chown=rails:rails /app /app

# Active Storage writes here (config/storage.yml -> Disk, Rails.root/storage),
# as does the tmp dir. Both must be writable by the rails user.
RUN mkdir -p /app/tmp/pids /app/storage && chown -R rails:rails /app/tmp /app/storage

USER rails

ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    BUNDLE_WITHOUT=development:test

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/up || exit 1

# Start Puma only. Migrations are run as an explicit deploy step, not on every
# container start — a crash-looping container must not repeatedly migrate, and
# seeding on boot is not something you want happening unattended.
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
