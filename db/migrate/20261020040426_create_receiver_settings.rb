class CreateReceiverSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :receiver_settings do |t|
      t.string :response_mode, default: "200", null: false

      t.timestamps
    end
  end
end
