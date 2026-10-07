# One file inside a cartridge, stored cart-relative.
#
# byte_size and filetime are denormalised because the runtime builds a
# manifest on every page load. Asking ActiveStorage for the metadata of every
# file on every request would be one metadata fetch per file per page view,
# and the manifest must report sizes that are exactly right -- a wrong
# filesize makes the loader write a padded or truncated file into the
# virtual filesystem rather than failing loudly.
class CartridgeFile < ApplicationRecord
  belongs_to :cartridge

  has_one_attached :blob

  validates :path, presence: true, uniqueness: { scope: :cartridge_id }
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Every stored path is cart-relative and safe: no leading slash, no '..'
  # segment, no backslash, no empty segment. Enforced here as well as at
  # ingest, because this is the value that ends up in a URL and in a manifest.
  validates :path, format: {
    with: /\A(?!.*(?:^|\/)\.\.(?:\/|\z))[^\0]+\z/,
    message: "must be a cart-relative path"
  }

  scope :ordered, -> { order(:path) }

  def ruby? = path.end_with?(".rb")
  def binary? = !ruby?
  def filename = File.basename(path)
end
