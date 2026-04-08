# app/controllers/api/v1/auth_controller.rb
#
# POST /api/v1/auth/login
#
# Authenticates a user with email + password (Devise checks the BCrypt hash).
# Returns a JWT on success. The mobile app stores this and sends it as
# Authorization: Bearer <token> on every subsequent request.
#
# POST /api/v1/auth/logout
# Rotates jti — invalidates all existing tokens for this user.

class Api::V1::AuthController < ActionController::API

  # Login is public — no before_action auth here
  rescue_from JWT::DecodeError, JWT::ExpiredSignature do |e|
    render json: { success: false, error: "Token error: #{e.message}" }, status: :unauthorized
  end

  # POST /api/v1/auth/login
  # Body: { "email": "user@example.com", "password": "secret" }
  def login
    # Extract email and password from params.
    # Handles three request shapes the mobile app might send:
    #   1. Flat JSON:   { "email": "x", "password": "y" }
    #   2. Nested JSON: { "user": { "email": "x", "password": "y" } }
    #   3. Form data:   email=x&password=y
    #
    # IMPORTANT — mobile app MUST send: Content-Type: application/json
    # Without this header Rails does not parse the JSON body and params is empty.
    raw_email    = params[:email] || params.dig(:user, :email)
    raw_password = params[:password] || params.dig(:user, :password)

    # Fail fast with a clear message if credentials missing entirely
    if raw_email.blank? || raw_password.blank?
      return render json: {
        success: false,
        error:   'Email and password are required',
        hint:    'Ensure Content-Type: application/json header is set and body is valid JSON'
      }, status: :bad_request
    end

    user = User.find_by(email: raw_email.to_s.downcase.strip)

    # valid_password? is provided by Devise's :database_authenticatable module.
    # It calls BCrypt::Password.new(encrypted_password).is_password?(plain_password)
    # Returns false (not raises) if the password is wrong.
    if user&.valid_password?(raw_password.to_s)

      unless user.status.to_s == 'active'
        return render json: {
          success: false,
          error:   'Your account is inactive. Contact your administrator.'
        }, status: :forbidden
      end

      # Ensure jti is present (for users created before this migration)
      user.update_column(:jti, SecureRandom.hex(24)) if user.jti.blank?

      token = JsonWebToken.encode(
        user_id: user.id,
        jti:     user.jti,
        role:    user.role,
        org_id:  user.organisation_id
      )

      render json: {
        success: true,
        token:   token,
        expires_in: 86400,   # 24 hours in seconds — mobile app can show session countdown
        user: {
          id:    user.id,
          name:  user.full_name,
          email: user.email,
          role:  user.role
        },
        organisation: {
          id:         user.organisation.id,
          name:       user.organisation.name,
          state:      user.organisation.state,
          state_code: user.organisation.state_code,
          gstin:      user.organisation.gst_number
        }
      }, status: :ok

    else
      render json: {
        success: false,
        error:   'Invalid email or password'
      }, status: :unauthorized
    end
  end

  # POST /api/v1/auth/logout
  # Rotates jti so all existing JWTs for this user are immediately invalid.
  def logout
    header = request.headers['Authorization']
    token  = header&.split(' ')&.last
    return render json: { success: true, message: 'Logged out' } if token.blank?

    begin
      payload = JsonWebToken.decode(token)
      user    = User.find_by(id: payload['user_id'])
      user&.update_column(:jti, SecureRandom.hex(24))
    rescue JWT::DecodeError
      # Token already invalid — that's fine
    end

    render json: { success: true, message: 'Logged out. Token revoked.' }
  end

  # GET /api/v1/auth/me
  # Returns current user details. Useful for mobile to validate stored token.
  def me
    header = request.headers['Authorization']
    token  = header&.split(' ')&.last
    return render json: { success: false, error: 'No token' }, status: :unauthorized if token.blank?

    payload = JsonWebToken.decode(token)
    user    = User.find_by!(id: payload['user_id'], jti: payload['jti'])

    render json: {
      success: true,
      user: {
        id:    user.id,
        name:  user.full_name,
        email: user.email,
        role:  user.role
      },
      organisation: {
        id:         user.organisation.id,
        name:       user.organisation.name,
        state:      user.organisation.state,
        state_code: user.organisation.state_code,
        gstin:      user.organisation.gst_number
      }
    }
  rescue ActiveRecord::RecordNotFound, JWT::DecodeError => e
    render json: { success: false, error: e.message }, status: :unauthorized
  end

end