class AddScenariosToReceiverSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :receiver_settings, :scenario_mode, :string, default: "static", null: false
    add_column :receiver_settings, :scenario_threshold, :integer, default: 2, null: false
    add_column :receiver_settings, :request_count, :integer, default: 0, null: false
  end
end

