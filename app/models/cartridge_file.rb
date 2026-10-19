# One file inside a cartridge, stored cart-relative. byte_size and filetime
# are denormalised because the manifest is built on every page load and must
# be byte-exact; asking storage per file per view would be a fetch each.
class CartridgeFile < ApplicationRecord
  belongs_to :cartridge

  has_one_attached :blob

  validates :path, presence: true, uniqueness: { scope: :cartridge_id }
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Checked here as well as at ingest: this value ends up in URLs and manifests.
  validates :path, format: {
    with: /\A(?!.*(?:^|\/)\.\.(?:\/|\z))[^\0]+\z/,
    message: "must be a cart-relative path"
  }

  scope :ordered, -> { order(:path) }

  # What the name promises before downloading: source, and the data files
  # DragonRuby loads. Anything else is an asset.
  TEXT_EXTENSIONS = %w[rb json txt md yml yaml lua csv].freeze

  def text? = TEXT_EXTENSIONS.include?(File.extname(path).delete_prefix(".").downcase)
  def image? = Marcel::MimeType.for(name: path).to_s.start_with?("image/")
  def previewable? = text? || image?

  def filename = File.basename(path)
end
