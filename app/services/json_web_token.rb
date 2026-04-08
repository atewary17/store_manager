# app/services/json_web_token.rb
#
# Thin wrapper around the `jwt` gem for encoding/decoding API tokens.
#
# SETUP:
#   1. Add to Gemfile:  gem 'jwt', '~> 2.8'
#   2. Run: bundle install
#   3. Add secret to credentials:
#      rails credentials:edit
#        api_jwt_secret: "generate-with-openssl-rand-hex-64"
#
# Token lifespan: 24 hours by default.
# The `jti` claim ties the token to a specific login — rotating user.jti
# on logout/password-change invalidates all existing tokens.

class JsonWebToken

  EXPIRY      = 24.hours
  ALGORITHM   = 'HS256'.freeze

  def self.secret
    Rails.application.credentials.api_jwt_secret ||
      ENV.fetch('API_JWT_SECRET') { raise 'API_JWT_SECRET not set' }
  end

  # Encode a payload into a signed JWT.
  # Automatically adds exp (expiry) and iat (issued-at) claims.
  # Ruby 3.0+: keyword args are no longer auto-converted to a positional hash.
  # Accept payload as either a plain Hash OR keyword splat — both work:
  #   JsonWebToken.encode({ user_id: 1, jti: "x" })       ← explicit hash
  #   JsonWebToken.encode(user_id: 1, jti: "x")           ← keyword splat
  def self.encode(payload = nil, exp: EXPIRY.from_now, **kwargs)
    # Merge explicit hash + any keyword args into one payload hash
    combined = (payload || {}).merge(kwargs)
    combined = combined.merge(
      exp: exp.to_i,
      iat: Time.current.to_i
    )
    JWT.encode(combined, secret, ALGORITHM)
  end

  # Decode and verify a JWT string.
  # Returns the payload hash (string keys) or raises on any error.
  # Raises JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidJtiError, etc.
  def self.decode(token)
    decoded = JWT.decode(token, secret, true, algorithm: ALGORITHM)
    decoded.first  # [payload, header] — we only need payload
  end

end