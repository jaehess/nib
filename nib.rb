require 'rubygems'
require 'aws/s3'
require 'fileutils'
require 'logger'
class Array
  def last_key
    return '' if self.last.nil?
    self.last.gsub(/#{NIB::BACKUP_PATH}\//,'')
  end
end

module NIB
  BUCKET_NAME = "Your S3 Bucket name"
  ACCESS_KEY = "Your S3 Access Key"
  SECRET_ACCESS_KEY = "Your S3 Secret Access Key"
  BACKUP_PATH = "/Path/to/backup"
  BUCKET_PREFIX = "Your Model Prefix" # Restricts the response to only contain results that begin with the specified prefix.
  
  class Filesystem
    attr_accessor :files
    def files
      @files ||= Filesystem.local_files
    end
    class << self
      def local_files
        FileUtils.mkdir_p(BACKUP_PATH)
        Dir["#{BACKUP_PATH}/**/*"].reject{|f| File.directory?(f)}
      end
      def ensure_path(key)
        FileUtils.mkdir_p(File.dirname(key))
      end
    end
  end
  
  class Connection
    attr_accessor :connection
    def connection
      @connection ||= Connection.connect
    end
    class << self
      def connect
        AWS::S3::Base.establish_connection!(
          :access_key_id => ACCESS_KEY,
          :secret_access_key => SECRET_ACCESS_KEY
        )
      end
    end
  end
  
  class Backup
    class << self
      attr_accessor :logger
      def logger
        @logger || Logger.new('nativity.log')
      end
      def ensure_bucket
        AWS::S3::Bucket.find(BUCKET_NAME)
      end
      def stuff(key)
        b_file = File.join(BACKUP_PATH, key)
        Filesystem.ensure_path(b_file)
        begin
          open(b_file, 'w') do |file|
            AWS::S3::S3Object.stream(key, BUCKET_NAME){|chunk|file.write chunk } 
          end
        rescue
          FileUtils.rm_f(b_file)
          logger.info "Error backing up #{key} to #{b_file}. Removing partial file."
        end
        logger.info "Successfully backed up #{key} to #{b_file}"
      end
      def go()
        logger.info "NIB Starting..."
        Connection.new.connection
        ensure_bucket
        loop do
          fs = Filesystem.new
          objs = AWS::S3::Bucket.objects(BUCKET_NAME, :marker => fs.files.last_key, :prefix => BUCKET_PREFIX)
          break if objs.length == 0
          objs.each{|obj| stuff(obj.key)}
        end
        logger.info "NIB Finished."
      end
    end
  end
  
end

NIB::Backup.go
