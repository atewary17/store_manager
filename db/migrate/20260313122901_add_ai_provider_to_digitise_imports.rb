class AddAiProviderToDigitiseImports < ActiveRecord::Migration[7.1]
  def change
    add_column :digitise_imports, :ai_provider, :string  # 'gemini', 'groq', 'mock'
  end
end
