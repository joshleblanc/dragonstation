# One published version of the console library.
#
# The library source lives on disk under vendor/console/<version>/. This row is
# the pointer to it plus the metadata a gallery needs. Splitting the two means
# the version is a first-class thing a cartridge can be pinned to, and the
# files stay reviewable in the repository rather than hiding in a blob.
class ConsoleVersion < ApplicationRecord
  has_many :cartridges, dependent: :restrict_with_error

  validates :version, presence: true, uniqueness: true,
    format: { with: /\A\d+\.\d+\.\d+\z/, message: "must look like 0.1.0" }

  scope :newest_first, -> { order(created_at: :desc) }
  scope :default_first, -> { order(default: :desc, created_at: :desc) }

  def to_s = version

  # What a new upload gets pinned to. The flag wins; otherwise the newest
  # version, so a fresh install with no flag set still uploads something.
  def self.default
    default_first.where(default: true).first || newest_first.first
  end

  # The library this row points at, or nil when the directory is missing.
  #
  # Returning nil rather than raising is deliberate: an admin can add a row
  # before the files land, and a gallery listing should degrade to "library
  # missing" instead of taking the whole page down.
  def library
    @library ||= ConsoleLibrary.new(self)
  end

  def available? = library.available?
end
