# One user's credential for publishing carts from outside the browser.
#
# The console cannot hold a session cookie, so this is what lets a cart sent
# from a terminal belong to an account. It is deliberately the same shape as
# Session: an unguessable identifier, looked up by the thing that carries it.
#
# One key per user. Issuing a new one replaces the old, which is also how a
# leaked key is killed -- there is no separate revoke, because "give me a new
# key" and "this key is dead" are the same request when there is only ever one.
class ApiKey < ApplicationRecord
  # Visible in a terminal, in a shell history, and in a screenshot. The prefix
  # is what makes a leaked key recognisable in a log.
  PREFIX = "ds_"

  # Shown in the UI so a key can be identified without storing the secret.
  DISPLAY_LENGTH = 8

  belongs_to :user

  validates :digest, presence: true, uniqueness: true
  validates :prefix, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  # [record, secret]. The secret is returned exactly once and is not
  # recoverable afterwards -- which is the whole reason the download that hands
  # it out can be a plain button with no confirmation step.
  def self.issue!(user)
    secret = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"

    # Through the association, not create!(user:), because that is what makes
    # `has_one` retire the key it replaces. Creating directly would leave the
    # old one working, and "one key per account" would quietly be two.
    record = user.create_api_key!(digest: digest(secret), prefix: secret.first(DISPLAY_LENGTH))

    [ record, secret ]
  end

  # The key a request carries, or nil.
  #
  # A blank secret is a nil digest lookup rather than an exception: a request
  # with no Authorization header is a failed authentication, not a bug.
  def self.authenticate(secret)
    return nil if secret.blank?

    key = find_by(digest: digest(secret.to_s.strip))
    return nil unless key

    key.update_column(:last_used_at, Time.current)
    key
  end

  def self.digest(secret) = OpenSSL::Digest::SHA256.hexdigest(secret)

  # The bearer token out of an Authorization header, if that is the scheme.
  #
  # Accepting only Bearer is deliberate: a header that also accepted the raw
  # secret in some other scheme would be a second thing to get wrong in a
  # script, and every caller that sends it would have to know which one it was.
  def self.from_authorization(header)
    scheme, value = header.to_s.split(" ", 2)

    return nil unless scheme&.casecmp?("Bearer")
    return nil if value.blank?

    authenticate(value)
  end

  # Replaces this user's key with a fresh one. Returns [record, secret].
  def self.rotate!(user)
    transaction do
      user.api_key&.destroy!
      issue!(user)
    end
  end

  # Enough of the key to recognise it in a list, and never enough to use it.
  def display = "#{prefix}..."
end
