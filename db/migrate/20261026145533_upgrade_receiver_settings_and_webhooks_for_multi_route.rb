class UpgradeReceiverSettingsAndWebhooksForMultiRoute < ActiveRecord::Migration[8.1]
  def change
    add_column :receiver_settings, :route_key, :string, default: "default", null: false
    add_column :receiver_settings, :status_code, :integer, default: 200, null: false
    add_column :receiver_settings, :delay_seconds, :integer, default: 0, null: false
    add_column :receiver_settings, :response_body, :text

    add_index :receiver_settings, :route_key, unique: true

    add_column :received_webhooks, :receiver_path, :string
    add_column :received_webhooks, :delay_seconds, :integer, default: 0

    add_index :received_webhooks, :receiver_path
  end
end
