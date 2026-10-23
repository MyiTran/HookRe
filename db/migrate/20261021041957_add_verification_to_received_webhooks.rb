class AddVerificationToReceivedWebhooks < ActiveRecord::Migration[8.1]
  def change
    add_column :received_webhooks, :verification_status, :string
    add_column :received_webhooks, :verification_error, :text
  end
end
