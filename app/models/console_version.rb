# One version of the console library, which a cartridge is pinned to forever.
# Its files are blobs, one per path, through console_library_files.
class ConsoleVersion < ApplicationRecord
  has_many :cartridges, dependent: :restrict_with_error
  has_many :console_library_files, dependent: :destroy

  validates :version, presence: true, uniqueness: true,
    format: { with: /\A\d+\.\d+\.\d+\z/, message: "must look like 0.1.0" }

  scope :newest_first, -> { order(created_at: :desc) }
  scope :default_first, -> { order(default: :desc, created_at: :desc) }

  def to_s = version

  # What a new upload is pinned to. A flagged default is honoured even if
  # broken -- an admin chose it, and the admin page shows it broken. The
  # fallback skips unreadable versions, because a pin nobody chose to a library
  # that cannot boot is permanent.
  def self.default
    newest_first.find_by(default: true) || newest_first.find(&:available?)
  end

  def make_default!
    transaction do
      ConsoleVersion.where.not(id: id).where(default: true).update_all(default: false)
      update!(default: true)
    end
  end

  def library = @library ||= ConsoleLibrary.new(self)

  def available? = library.available?

  # @library memoizes what it read; a version repaired in place must re-read.
  def reload(...)
    @library = nil
    super
  end
end
