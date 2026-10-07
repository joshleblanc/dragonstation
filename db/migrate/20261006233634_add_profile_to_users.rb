class AddProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    # A username is the public identity a cartridge is published under. It is
    # nullable so the existing rows (none yet, but the generator shipped a
    # table) do not force a backfill, and required at the model level once
    # there is somewhere to require it.
    add_column :users, :username, :string
    add_index :users, :username, unique: true

    add_column :users, :admin, :boolean, null: false, default: false
  end
end
