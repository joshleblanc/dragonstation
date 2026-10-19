# One file of a console library. Library-relative and looked up by equality,
# so a path cannot escape anything; the format check keeps it that way.
class ConsoleLibraryFile < ApplicationRecord
  belongs_to :console_version

  has_one_attached :blob

  validates :path, presence: true,
    format: {
      with: %r{\A(?!/)(?!.*(?:^|/)\.\.(?:/|\z))[^\0]+\z},
      message: "must be a library-relative path with no '..' segment"
    }
  validates :path, uniqueness: { scope: :console_version_id }
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:path) }

  def read = blob.download

  # Whether the bytes can be fetched, not whether the row exists. A blob reads
  # from the service it was written to forever, so switching services leaves
  # rows pointing at nothing (see lib/tasks/active_storage.rake). A HEAD, not
  # a download.
  def readable?
    blob.present? && blob.service.exist?(blob.key)
  rescue ActiveStorage::FileNotFoundError, ActiveRecord::RecordNotFound
    false
  end
end
