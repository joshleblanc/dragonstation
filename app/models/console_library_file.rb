# One file of a console library, in a blob rather than in a directory.
#
# This is the counterpart of CartridgeFile, and it exists for the same reasons:
# the library is versioned by row, so the bytes behind a version should live
# somewhere that moves with the row rather than in a tree somebody has to keep
# in sync by hand. A console release uploaded twice must never edit the first
# one's files, and a row whose files are addressed by path cannot do that by
# accident.
class ConsoleLibraryFile < ApplicationRecord
  belongs_to :console_version

  has_one_attached :blob

  # Containment is enforced here rather than at read time: a stored path is
  # looked up by equality, so a path that escaped the library has no row to
  # resolve to and there is nothing to guard against later.
  validates :path, presence: true,
    format: {
      with: %r{\A(?!/)(?!.*(?:^|/)\.\.(?:/|\z))[^\0]+\z},
      message: "must be a library-relative path with no '..' segment"
    }
  validates :path, uniqueness: { scope: :console_version_id }

  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:path) }

  def size_of = byte_size

  def read = blob.download

  # Whether the bytes behind this row can actually be fetched.
  #
  # The row existing is a different question, and answering the wrong one is what
  # made a broken install look installed. A blob records the service it was
  # written to and reads from that one for the rest of its life, so changing
  # ACTIVE_STORAGE_SERVICE and redeploying leaves every row in place and every
  # object on the disk being left behind -- see lib/tasks/active_storage.rake for
  # the failure that produces. The row count says an install happened; only this
  # says whether there is anything left to serve.
  #
  # A HEAD against the service rather than a download, so the pages that ask
  # whether a version is usable can ask without pulling its entry file down to
  # find out that it is not there.
  def readable?
    object = blob
    return false unless object

    object.service.exist?(object.key)
  rescue ActiveStorage::FileNotFoundError, ActiveRecord::RecordNotFound
    # No blob row at all, which a purged attachment leaves behind. Same answer
    # as an object that is gone: there is nothing here to read.
    false
  end
end
