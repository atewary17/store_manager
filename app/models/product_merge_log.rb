# app/models/product_merge_log.rb
class ProductMergeLog < ApplicationRecord

  belongs_to :performed_by, class_name: 'User', foreign_key: :performed_by_id

  # No FK associations to merged_product/target_product intentionally:
  # merged_product is deactivated after merge; log must stay readable.

  def merged_product_snapshot
    snapshot['under_review'] || {}
  end

  def target_product_snapshot
    snapshot['target'] || {}
  end

end
