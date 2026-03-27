# app/models/tinting_machine_log.rb
class TintingMachineLog < ApplicationRecord

  ACTIONS = %w[loaded dispensed refilled removed adjusted].freeze

  belongs_to :tinting_machine_canister
  belongs_to :organisation
  belongs_to :user, optional: true

  validates :action,    inclusion: { in: ACTIONS }
  validates :volume_ml, presence: true

  scope :for_org,  ->(org_id) { where(organisation_id: org_id) }
  scope :recent,   -> { order(created_at: :desc) }

end
