# A user's credential for publishing from the console, which has no cookie.
# One per user, stored only as a digest; issuing a new one retires the old,
# which is also how a leaked key is revoked.
class ApiKey < ApplicationRecord
  # Makes a leaked key recognisable in a log or a screenshot.
  PREFIX = "ds_"
  DISPLAY_LENGTH = 8

  belongs_to :user

  validates :digest, presence: true, uniqueness: true
  validates :prefix, presence: true

  # [record, secret]. The secret exists only in this return value.
  def self.issue!(user)
    secret = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"

    # Through the has_one, which destroys the key it replaces.
    record = user.create_api_key!(digest: digest(secret), prefix: secret.first(DISPLAY_LENGTH))

    [ record, secret ]
  end

  def self.authenticate(secret)
    return nil if secret.blank?

    find_by(digest: digest(secret.to_s.strip))&.tap { |key| key.update_column(:last_used_at, Time.current) }
  end

  def self.digest(secret) = OpenSSL::Digest::SHA256.hexdigest(secret)

  # Bearer only: one scheme is one fewer thing for a script to get wrong.
  def self.from_authorization(header)
    scheme, value = header.to_s.split(" ", 2)
    return nil unless scheme&.casecmp?("Bearer")

    authenticate(value)
  end

  def display = "#{prefix}..."
end
