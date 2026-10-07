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
end