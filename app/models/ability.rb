# app/models/ability.rb
class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new # guest user (not logged in)

    if user.super_admin?
      can :manage, :setup
      can :manage, :api_preferences   # AI provider config — super_admin only
      can :manage, :favorites         # Dashboard shortcuts
    end

    if user.admin? || user.super_admin?
      can :manage, :favorites         # Dashboard shortcuts
    end
  end
end
