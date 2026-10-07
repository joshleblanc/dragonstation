# A game uploaded as a console cart, pinned to the console version it was
# built against.
#
# The cart's files are stored cart-relative, exactly as the console resolves
# them: 'app/main.rb', 'sprites/hero/run/0.png'. Nothing here knows which
# console version it belongs to -- the pinned ConsoleVersion is what the
# runtime serves alongside it.
class Cartridge < ApplicationRecord
  belongs_to :user
  belongs_to :console_version

  has_many :cartridge_files, dependent: :destroy

  validates :title, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "may only contain lowercase letters, numbers and dashes" }
  validates :cart_name, presence: true,
    format: {
      # Console::CartLoader turns this into the constant the cart defines, so
      # it has to be a constant name: no dashes, no leading digit.
      with: /\A[a-zA-Z][a-zA-Z0-9_]*\z/,
      message: "must be a valid Ruby constant name"
    }
  validates :entry_path, presence: true

  scope :published, -> { where.not(published_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  def published? = published_at.present?
  def draft? = !published?

  def publish! = update!(published_at: Time.current)
  def unpublish! = update!(published_at: nil)

  def to_param = slug

  # The exact file set this cartridge serves, with byte-exact sizes.
  def stager = @stager ||= CartridgeStager.new(self)
  def manifest = stager.manifest

  # Files are addressed under this prefix in the served tree, because
  # Console::CartLoader looks for carts/<name>/ and the cart never hardcodes
  # its own name.
  def cart_prefix = "carts/#{cart_name}"

  # The console reads TITLE out of the cart's entry file; fall back to the
  # title the uploader typed.
  def display_title
    title.presence || cart_name
  end

  def to_s = title
end
