class CreateReceivedWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :received_webhooks do |t|
      t.string :request_id
      t.string :webhook_id
      t.string :event_type
      t.text :headers
      t.text :body
      t.datetime :received_at

      t.timestamps
    end
  end
end
