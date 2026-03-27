# app/models/tinting_machine_canister.rb
class TintingMachineCanister < ApplicationRecord

  STATUSES  = %w[empty active low critical].freeze
  LOW_PCT   = 30   # % remaining — warn as low
  CRIT_PCT  = 15   # % remaining — critical

  belongs_to :organisation
  belongs_to :brand
  belongs_to :product,   optional: true
  belongs_to :loaded_by, class_name: 'User', optional: true
  has_many   :tinting_machine_logs, dependent: :destroy

  validates :slot_number,       presence: true,
                                numericality: { only_integer: true, greater_than: 0 }
  validates :initial_volume_ml, presence: true,
                                numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :for_org,      ->(org_id) { where(organisation_id: org_id) }
  scope :for_brand,    ->(brand_id) { where(brand_id: brand_id) }
  scope :active,       -> { where(status: %w[active low critical]) }
  scope :ordered,      -> { order(:slot_number) }

  # ── Calculated level ─────────────────────────────────────
  # remaining = initial − total dispensed + total refilled
  def remaining_ml
    [initial_volume_ml.to_f - dispensed_volume_ml.to_f, 0].max
  end

  def level_percent
    return 0 if initial_volume_ml.to_f.zero?
    [(remaining_ml / initial_volume_ml.to_f * 100).round(1), 100].min
  end

  def loaded?
    product_id.present?
  end

  def level_status
    pct = level_percent
    if !loaded?     then :empty
    elsif pct <= 0  then :empty
    elsif pct <= CRIT_PCT then :critical
    elsif pct <= LOW_PCT  then :low
    else :active
    end
  end

  def level_color
    case level_status
    when :active   then '#34d98b'
    when :low      then '#f7c34f'
    when :critical then '#f7614f'
    else '#3a4155'
    end
  end

  # ── Recalculate and persist status ───────────────────────
  def refresh_status!
    update!(status: level_status.to_s)
  end

  # ── Volume helper ─────────────────────────────────────────
  # Derive canister volume from product pack_code (e.g. "500 ML", "1 LT")
  def self.volume_from_pack_code(pack_code)
    return 1000 if pack_code.blank?
    pc = pack_code.to_s.downcase.gsub(/\s+/, '')
    if (m = pc.match(/(\d+(?:\.\d+)?)\s*l(t|tr|itre)?(?!\w)/))
      (m[1].to_f * 1000).to_i   # litres → ml
    elsif (m = pc.match(/(\d+(?:\.\d+)?)\s*ml/))
      m[1].to_f.to_i
    else
      1000  # default 1L
    end
  end
end
