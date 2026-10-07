class CreateCartridgeFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :cartridge_files do |t|
      t.references :cartridge, null: false, foreign_key: true

      # Cart-relative, always forward-slashed, never absolute and never
      # containing '..'. Stored per file rather than as one archive because the
      # manifest has to report an exact byte size for every file it lists, and
      # because the runtime serves them one request at a time.
      t.string :path, null: false

      # Denormalised from the blob at ingest. The manifest is built on every
      # page load and asking ActiveStorage for the size of every file each
      # time would be a download of metadata per file per request.
      t.bigint :byte_size, null: false

      # Stable per file, and never recomputed: the loader compares it against
      # its IndexedDB cache and re-downloads when it moves. A value that
      # changed on every request would defeat caching without ever telling the
      # loader anything true about the content.
      t.bigint :filetime, null: false

      t.timestamps
    end

    add_index :cartridge_files, %i[cartridge_id path], unique: true
  end
end
