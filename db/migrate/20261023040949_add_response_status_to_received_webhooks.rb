class AddResponseStatusToReceivedWebhooks < ActiveRecord::Migration[8.1]
  def change
    add_column :received_webhooks, :response_status, :integer
  end
end
