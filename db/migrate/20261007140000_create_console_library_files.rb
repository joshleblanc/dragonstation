class CreateConsoleLibraryFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :console_library_files do |t|
      t.references :console_version, null: false, foreign_key: true

      # Library-relative, always forward-slashed, never absolute and never
      # containing '..'. Stored per file rather than as one archive for the
      # same reason cartridge_files is: the manifest reports an exact byte size
      # for every library file it lists, and the release bundle walks the tree
      # by path rather than by unpacking something.
      t.string :path, null: false

      # Denormalised from the blob at install. The manifest is built on every
      # page load, and asking ActiveStorage for the size of every library file
      # on every request would be a metadata round trip per file per page --
      # against a library that is the same size for every cartridge.
      t.bigint :byte_size, null: false

      t.timestamps
    end

    add_index :console_library_files, %i[console_version_id path], unique: true
  end
end