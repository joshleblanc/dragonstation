# A game uploaded as a console cart, pinned to the console version it was
# uploaded against. Files are stored cart-relative ('app/main.rb'), exactly as
# the console resolves them.
class Cartridge < ApplicationRecord
  belongs_to :user
  belongs_to :console_version

  has_many :cartridge_files, dependent: :destroy

  validates :title, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "may only contain lowercase letters, numbers and dashes" }
  # Console::CartLoader resolves the cart's class from this name.
  validates :cart_name, presence: true,
    format: { with: /\A[a-zA-Z][a-zA-Z0-9_]*\z/, message: "must be a valid Ruby constant name" }
  validates :entry_path, presence: true

  scope :published, -> { where.not(published_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  def published? = published_at.present?
  def draft? = !published?

  def publish! = update!(published_at: Time.current)
  def unpublish! = update!(published_at: nil)

  def to_param = slug
  def to_s = title

  def stager = @stager ||= CartridgeStager.new(self)
  def manifest = stager.manifest

  # Where the cart's files live in the served tree: Console::CartLoader looks
  # under carts/<name>/, and a cart never hardcodes its own name.
  def cart_prefix = "carts/#{cart_name}"
end
