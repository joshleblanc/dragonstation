class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :cartridges, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  # to_s, not a guard: normalizes runs on nil too, and a nil username should
  # fail the presence validation below rather than raise on strip.
  normalizes :username, with: ->(u) { u.to_s.strip.delete_prefix("@").downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true,
    format: {
      with: /\A[a-z0-9_]+\z/i,
      message: "may only contain letters, numbers and underscores"
    },
    length: { in: 3..32 }

# has_secure_password already validates that a password was supplied and that
# the confirmation matched -- adding another :confirmation here would report
# the same problem twice. All this adds is the length floor, which is the one
# rule a public sign-up wants that a password reset should not be able to
# route around.
validates :password, length: { minimum: 8 }, allow_blank: true

  # The first account to register is the operator. A fresh install has no other
  # way to reach an admin screen, because every admin screen is behind a login
  # and there is nobody to log in as.
  def self.promote_first_admin!
    return if where(admin: true).exists?

    order(:id).first&.update!(admin: true)
  end
end
