# db/migrate/20260322000001_enable_pg_trgm.rb
class EnablePgTrgm < ActiveRecord::Migration[7.1]
  def up
    enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')
  end

  def down
    # Leave pg_trgm enabled — other features may depend on it
  end
end
