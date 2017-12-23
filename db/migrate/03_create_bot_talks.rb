class CreateBotTalks < ActiveRecord::Migration[5.1]
  def change
    create_table :bot_talks do |t|
      t.string :sentence
      t.boolean :sent, default: false

      t.timestamps
    end
  end
end
