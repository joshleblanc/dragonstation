require "securerandom"

# Move stored files between Active Storage services.
#
# Setting ACTIVE_STORAGE_SERVICE tells the app where to write *new* blobs. It
# moves nothing that is already there, because a blob records the service it was
# written to and reads from that one for the rest of its life. So a deployment
# that switches from local disk to a bucket and redeploys serves every cartridge
# and every console library file out of the local disk it is leaving behind --
# and on Kamal that disk is a fresh empty directory on a fresh container, so the
# failure is not a slow read but a file that is simply not there.
#
# This copies the bytes across and repoints the rows.
#
#   bin/rails active_storage:copy_blobs TO=amazon
#   bin/rails active_storage:copy_blobs TO=amazon DRY_RUN=true
#
# Run it while the blobs still name their old service. No FROM is needed,
# because each blob is read from the service it names -- which is what keeps this
# correct during a mixed period when some blobs have already moved and some have
# not. Interrupt it and run it again whenever: blobs already on the target are
# left alone, so the work resumes rather than repeating.
#
# Keys are preserved rather than regenerated, so a URL handed out yesterday still
# resolves today and no attachment has to be repointed. Only the service_name on
# the blob they already belong to changes.
module CopyBlobs
  # How many blobs to take on at a time. Enough that the round trip is worth
  # paying, few enough that a large library does not run the process out of
  # memory reading it all into one array.
  BATCH = 200

  # The metadata that belongs to the object in the store rather than to the
  # row. `identified` is deliberately left out: it is the result of analysing
  # the bytes locally, the store has no use for it, and recomputing it would
  # cost a download per blob to produce a number nothing here reads back.
  def self.object_metadata(blob)
    blob.metadata.slice("custom").compact_blank
  end

  # One blob's bytes into the target service, under the key it already has.
  #
  # The checksum is passed through rather than recomputed, which is what keeps
  # `verified?` true afterwards. Active Storage verifies a download against the
  # checksum on the row, so a recomputed one that differed by as much as a
  # different gzip level would leave every file failing its own integrity check.
  #
  # No `disposition:` is passed, and that is not an oversight: Active Storage only
  # has a forced disposition to copy if the schema carries the column for it, and
  # this one does not. Nothing here forces one, so nothing here has one to lose.
  def self.copy(blob, target)
    blob.open do |io|
      target.upload(
        blob.key,
        io,
        checksum: blob.checksum,
        content_type: blob.content_type,
        custom_metadata: object_metadata(blob)
      )
    end
  end
end

namespace :active_storage do
  desc "Copy stored files to another Active Storage service (TO=amazon)"
  task copy_blobs: :environment do
    name = ENV["TO"].presence or abort "active_storage: no TO given. Run: bin/rails active_storage:copy_blobs TO=amazon"
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))

    if ENV["FROM"].present?
      # Not an error, but worth saying out loud: honouring FROM would restrict
      # the copy, and a blob whose service_name disagrees with it would be left
      # behind -- which looks like a finished migration and is not one.
      warn "active_storage: ignoring FROM=#{ENV['FROM']} -- every blob is copied from the service it names."
    end

    # The registry the rest of the app resolves blobs through, so `TO=local`
    # hands back the very service those blobs are already reading from rather
    # than a second instance of it. An unknown name raises here, naming the
    # services that do exist.
    target = ActiveStorage::Blob.services.fetch(name)
    elsewhere = ActiveStorage::Blob.where.not(service_name: target.name)
    already = elsewhere.count

    puts "active_storage: #{already} blob#{"s" unless already == 1} not on #{name}" \
         "#{dry_run ? " (dry run -- nothing written)" : ""}"

    return if dry_run || already.zero?

    cursor = 0

    loop do
      blobs = elsewhere.where("id > ?", cursor).order(:id).limit(CopyBlobs::BATCH).to_a
      break if blobs.empty?

      blobs.each do |blob|
        # The row moves only after the bytes are there, so an interrupted copy
        # leaves a blob still naming the service its bytes actually live in,
        # which the next run picks up. The reverse order would lose them.
        CopyBlobs.copy(blob, target)
        blob.update!(service_name: target.name)
        cursor = blob.id
      end

      print "."
      $stdout.flush
    end

    puts
    puts "active_storage: every blob is on #{name}."
  end
end
