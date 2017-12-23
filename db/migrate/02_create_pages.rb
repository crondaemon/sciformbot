class CreatePages < ActiveRecord::Migration[5.1]
  def change
    create_table :pages do |t|
      t.timestamps
      t.string :url
      t.string :label
      t.string :md5
      t.integer :bytes
    end
  end
end
