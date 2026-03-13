class AddAttemptsToDigitiseImports < ActiveRecord::Migration[7.1]
  def change
    add_column :digitise_imports, :attempt_count, :integer, null: false, default: 0
    # jsonb array — each entry: { attempt: N, status: ok/fail, error: "...", response: "...", at: "ISO8601" }
    add_column :digitise_imports, :attempt_log,   :jsonb,   null: false, default: []
  end
end
