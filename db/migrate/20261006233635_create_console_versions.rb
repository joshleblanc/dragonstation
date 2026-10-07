class CreateConsoleVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :console_versions do |t|
      # Matches the directory under vendor/console/ that holds this version's
      # library, and Console::Version::STRING in app/console/version.rb. The
      # two are checked against each other on load rather than trusted, so a
      # mislabelled directory fails loudly instead of serving a library under
      # the wrong version.
      t.string :version, null: false
      t.string :title
      t.text :notes

      # Which version a new upload is pinned to. Exactly one is expected to be
      # set; ConsoleVersion.default picks it, falling back to the newest when
      # an admin has not chosen one yet.
      t.boolean :default, null: false, default: false

      t.timestamps
    end

    add_index :console_versions, :version, unique: true
    add_index :console_versions, :default
  end
end
