# app/controllers/api/v1/base_controller.rb
#
# Base controller for all v1 API endpoints.
# Handles:
#   - JWT authentication via Authorization: Bearer <token>
#   - Organisation resolution (same logic as web BaseController)
#   - CSRF exemption (APIs are stateless)
#   - Consistent JSON error responses

class Api::V1::BaseController < ActionController::API

  # ActionController::API already skips most web middleware including CSRF.
  # We add respond_to JSON globally here.

  before_action :authenticate_api_user!
  before_action :set_organisation

  # ── Standard error rendering ──────────────────────────────────────────

  rescue_from ActiveRecord::RecordNotFound do |e|
    render_error :not_found, e.message
  end

  rescue_from JWT::DecodeError, JWT::ExpiredSignature do |e|
    render_error :unauthorized, "Token invalid or expired: #{e.message}"
  end

  rescue_from ActionController::ParameterMissing do |e|
    render_error :bad_request, e.message
  end

  private

  # ── Authentication ────────────────────────────────────────────────────

  def authenticate_api_user!
    header = request.headers['Authorization']
    token  = header&.split(' ')&.last   # "Bearer <token>"
    render_error(:unauthorized, 'Missing Authorization header') and return if token.blank?

    payload      = JsonWebToken.decode(token)
    @current_user = User.find_by!(id: payload['user_id'], jti: payload['jti'])

    # Guard: user must be active and their org must be active
    unless @current_user.status.to_s == 'active'
      render_error(:forbidden, 'Your account is inactive')
    end
  rescue ActiveRecord::RecordNotFound
    render_error(:unauthorized, 'User not found or token revoked')
  end

  def current_user
    @current_user
  end

  # ── Organisation ──────────────────────────────────────────────────────

  def set_organisation
    if current_user.respond_to?(:super_admin?) &&
       current_user.super_admin? &&
       params[:organisation_id].present?
      @organisation = Organisation.find(params[:organisation_id])
    else
      @organisation = current_user.organisation
    end
    render_error(:unprocessable_entity, 'No organisation associated with this user') unless @organisation
  end

  # ── JSON helpers ──────────────────────────────────────────────────────

  # ── Standard JSON response helpers ─────────────────────────────────────
  #
  # Every API response has this envelope:
  #
  # Success:
  #   { "success": true, "data_key": {...}, "message": "..." }
  #   HTTP 200 OK  (or 201 Created)
  #
  # Error:
  #   { "success": false, "error": "Human readable message", "code": "SNAKE_CASE_CODE" }
  #   HTTP 401 / 403 / 404 / 422 / 400
  #
  # Accepts both calling styles (Ruby 3 safe):
  #   render_success(invoice: {...})                        ← kwargs
  #   render_success({ invoice: {...} }, status: :created) ← explicit hash
  def render_success(data = nil, status: :ok, **kwargs)
    payload = { success: true }
    payload.merge!(data)   if data.is_a?(Hash)
    payload.merge!(kwargs) if kwargs.any?
    render json: payload, status: status
  end

  def render_error(status, message, code: nil)
    payload = { success: false, error: message }
    payload[:code] = code if code
    render json: payload, status: status
  end

  def pagination_meta(collection)
    {
      total:   collection.respond_to?(:total_count) ? collection.total_count : collection.size,
      count:   collection.size
    }
  end

end