# app/controllers/users/sessions_controller.rb
#
# Overrides Devise's SessionsController to enforce single-session logins.
#
# On sign-in, credentials are validated first. If valid, three paths:
#   1. No existing session  → sign in normally
#   2. Idle elsewhere       → render force_login_confirm (user chooses to kick old session)
#   3. Active elsewhere     → render active_elsewhere (blocked, inform user)
#
# force_login: POST action for the confirmation page. Trusts the user_id
# stashed in the Rails session after credential validation — no password
# is re-transmitted. CSRF-protected.
#
# On sign-out, clears session_token so the column stays clean.

class Users::SessionsController < Devise::SessionsController

  # POST /users/sign_in
  def create
    # Validate credentials without signing the user in yet.
    user = warden.authenticate(auth_options)

    if user.nil?
      # Bad credentials — fall through to Devise's standard failure rendering.
      super
      return
    end

    if user.active_elsewhere?
      @other_active_at = user.last_activity_at
      render :active_elsewhere, layout: false
    elsif user.idle_elsewhere?
      @idle_since = user.last_activity_at
      session[:pending_force_login_user_id] = user.id
      render :force_login_confirm, layout: false
    else
      finalize_sign_in(user)
    end
  end

  # POST /users/force_login
  # Called from the force_login_confirm page. The user_id was stashed in the
  # session after credential validation — no password needed here.
  def force_login
    user_id = session.delete(:pending_force_login_user_id)
    user    = User.find_by(id: user_id)

    unless user
      redirect_to new_user_session_path,
                  alert: 'Session expired. Please sign in again.'
      return
    end

    finalize_sign_in(user)
  end

  # DELETE /users/sign_out
  def destroy
    current_user&.clear_session_token!
    super
  end

  private

  def finalize_sign_in(user)
    token = user.generate_session_token!
    sign_in(resource_name, user)
    session[:session_token] = token
    redirect_to after_sign_in_path_for(user)
  end

end
