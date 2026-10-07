# The console's publishing credential: one per user, so a cart sent from the
# terminal can be attributed to the account that sent it.
#
# The secret itself is never stored. A SHA-256 digest is, because a key has to
# be *looked up* by the thing it authenticates -- a salted bcrypt digest cannot
# answer "is this the key?" without checking every row, which is what a password
# gets away with only because there is exactly one password to check. The
# entropy here is 32 bytes of SecureRandom, so there is nothing to brute-force
# and no reason to make it slow.
class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :digest, null: false
      t.string :prefix, null: false
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :api_keys, :digest, unique: true
  end
end
