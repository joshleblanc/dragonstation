# One published version of the console library.
#
# The library source lives in ActiveStorage, one blob per file, addressed by
# path through the console_library_files rows this has_many. This row is what
# a cartridge is pinned to; the files are what those pins resolve to.
class ConsoleVersion < ApplicationRecord
  has_many :cartridges, dependent: :restrict_with_error

  # Dependent destroy rather than restrict: a version's files are part of the
  # version, so removing the row should remove them. Cartridges above still
  # refuse the removal, which is the guard that actually matters -- a version
  # somebody is still pinned to must not go away, attached or not.
  has_many :console_library_files, dependent: :destroy

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

  # The library this row points at.
  def library
    @library ||= ConsoleLibrary.new(self)
  end

  def available? = library.available?
end
