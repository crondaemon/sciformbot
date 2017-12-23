class CreateChats < ActiveRecord::Migration[5.1]
  def change
    create_table :chats do |t|
      t.timestamps
      t.integer :chat_id
      t.string :chat_type
      t.string :title
      t.string :username
      t.string :first_name
      t.string :last_name
      t.boolean :permit
    end
  end
end
