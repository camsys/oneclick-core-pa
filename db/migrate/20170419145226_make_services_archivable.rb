class MakeServicesArchivable < ActiveRecord::Migration[5.0]
  def change
    add_column :services, :archived, :boolean, default: false
    add_index :services, :archived
  end
end
