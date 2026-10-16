ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "fileutils"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/cartridge_test_helper"
require_relative "test_helpers/console_library_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # The highest blob id before the test body runs. Fixtures are already
    # loaded at this point, so everything above it belongs to this test.
    setup { @blob_floor = ActiveStorage::Blob.maximum(:id) || 0 }

    # Erase the blobs this test wrote.
    #
    # The install helpers put the whole console checkout into ActiveStorage
    # per test -- font.ttf at 3.4MB is the largest single file -- so a run
    # writes tens of thousands of blobs. The wrapping transaction rolls the
    # blob rows back, but the bytes are already on disk: rollback cannot undo
    # a write, so without this a run leaves tens of gigabytes in tmp/storage
    # and the next run stacks another copy on top.
    #
    # Rows are read rather than files scanned, which is what keeps this safe
    # under parallel workers. They share tmp/storage but not the database, so
    # a worker only ever sees its own test's blobs and cannot delete bytes
    # another worker is still serving.
    teardown do
      ActiveStorage::Blob.where("id > ?", @blob_floor).find_each { |blob| blob.service.delete(blob.key) }

      # Same leak, smaller files: console_library_upload has to write a real
      # file for the multipart round trip, and only the admin test remembered
      # to clean up after itself.
      cleanup_uploads
    end

    # Add more helper methods to be used by all tests here...
  end
end

# Every worker has finished by now, so the whole tree is ours to clear --
# including whatever a killed run left behind. The glob skips dotfiles, so
# the tracked tmp/storage/.keep survives.
Minitest.after_run { FileUtils.rm_rf(Dir[Rails.root.join("tmp/storage/*")]) }
