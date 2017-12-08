class CreateChats < ActiveRecord::Migration[5.1]
  def change
    create_table :chats do |t|
      t.integer :chat_id
      t.string :chat_type
      t.string :title
      t.string :username
      t.string :first_name
      t.string :last_name
      t.boolean :all_members_are_admins
      t.boolean :permit

      t.timestamps
    end
  end
end
