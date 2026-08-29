class AddTokenUsageToDigitiseImports < ActiveRecord::Migration[7.1]
  # Headline token counts per scan, so the digitise index can show usage
  # without joining external_api_logs or digging through parsed_data jsonb.
  # The per-page breakdown lives in parsed_data['_meta']['pages_data'].
  def change
    add_column :digitise_imports, :prompt_tokens, :integer,
               comment: 'Input tokens billed for this scan (prompt + image), summed across pages'
    add_column :digitise_imports, :completion_tokens, :integer,
               comment: 'Output tokens generated, summed across pages'
    add_column :digitise_imports, :total_tokens, :integer,
               comment: 'prompt_tokens + completion_tokens, as reported by the provider'
  end
end
