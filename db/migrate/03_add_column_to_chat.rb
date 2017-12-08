class AddColumnToChat < ActiveRecord::Migration[5.1]
  def change
  	add_column :chats, :all_members_are_administrators, :boolean
  end
end
