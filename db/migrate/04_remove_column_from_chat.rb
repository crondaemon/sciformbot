class AddColumnToChat < ActiveRecord::Migration[5.1]
  def change
  	remove_column :chats, :all_members_are_admins
  end
end
