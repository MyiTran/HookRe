class AddSequenceModeToReceiverSettingsAndWebhooks < ActiveRecord::Migration[8.1]
  def change
    add_column :receiver_settings, :sequence_steps, :text, default: "[]", null: false
    add_column :receiver_settings, :sequence_index, :integer, default: 0, null: false
    add_column :received_webhooks, :scenario_step, :integer
  end
end
