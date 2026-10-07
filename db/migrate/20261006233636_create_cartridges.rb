class CreateCartridges < ActiveRecord::Migration[8.1]
  def change
    create_table :cartridges do |t|
      t.references :user, null: false, foreign_key: true

      # The pin. A cartridge never floats: it runs against the console library
      # version it was uploaded against, forever. Updating the library
      # therefore cannot change the behaviour of an already-published game,
      # and a leaderboard run stays comparable with the run beside it.
      t.references :console_version, null: false, foreign_key: true

      t.string :title, null: false
      t.string :slug, null: false
      t.text :description

      # The cart is staged as carts/<cart_name>/ and the generated entry point
      # pins exactly that path. It is recorded here because it is a directory
      # name the uploader chose, and Console::CartLoader derives the cart's
      # class name from it -- so it has to survive upload verbatim.
      t.string :cart_name, null: false
      t.string :entry_path, null: false

      t.datetime :published_at

      t.timestamps
    end

    add_index :cartridges, :slug, unique: true
    add_index :cartridges, %i[console_version_id cart_name]
  end
end
