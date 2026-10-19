class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :cartridges, dependent: :destroy
  # One at a time, and dependent: the key is worthless without the account, so
  # it should not outlive one. Issuing a new key replaces this one.
  has_one :api_key, dependent: :destroy

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

  # has_secure_password already checks presence and confirmation; this adds
  # the length floor, which a password reset must not be able to bypass.
  validates :password, length: { minimum: 8 }, allow_blank: true

  # A fresh key replacing any old one. Returns the secret, its only appearance.
  def issue_api_key!
    ApiKey.issue!(self).last
  end

  # The first account to register is the operator. A fresh install has no other
  # way to reach an admin screen, because every admin screen is behind a login
  # and there is nobody to log in as.
  def self.promote_first_admin!
    return if where(admin: true).exists?

    order(:id).first&.update!(admin: true)
  end
end
