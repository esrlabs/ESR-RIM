require 'fileutils'
require 'pathname'
require 'rim/file_helper'
require 'rim/git'
require 'rim/rim_exception'
require 'rake'
require 'pathname'
require 'uri'
require 'digest/sha1'

module RIM

class Processor

MaxThreads = 10
GerritServer = "ssh://gerrit/"

def initialize(workspace_root, logger)
  @ws_root = workspace_root
  rim_dir = nil
  rim_dir = File.expand_path(ENV['RIM_HOME']) if ENV.has_key?('RIM_HOME')
  rim_dir = File.join(File.expand_path(ENV['HOME']), ".rim") if rim_dir.nil? && ENV.has_key?('HOME')
  if rim_dir
    @rim_path = File.join(rim_dir, Processor.shorten_path(@ws_root))
  else  
    @rim_path = File.join(@ws_root, ".rim")
  end
  @logger = logger
end

def module_git_path(remote_path)
  # remote url without protocol specifier
  # this way the local path should be unique
  File.join(@rim_path, Processor.shorten_path(remote_path))
end

def module_tmp_git_path(remote_path)
  # remote url without protocol specifier
  # this way the local path should be unique
  File.join(@rim_path, ".tmp", Processor.shorten_path(remote_path))
end

def remote_path(remote_url)
  remote_url.
    # protocol specifier, e.g. ssh://
    sub(/^\w+:\/\//,'').
    # windows drive letter 
    sub(/^\w+:/,'\1').
    # make sure we don't .. up in a filesystem
    gsub(/\.\.[\\\/]/,'')
end

def get_absolute_remote_url(remote_url)
  if remote_url.start_with?("file:")
    remote_url = remote_url.gsub(/^file:(\/\/)?/, "")
    match = remote_url.match(/^\/(\w)\|/)
    if match
      remote_url = "#{match[1]}:#{remote_url[match[0].size..-1]}"
    elsif !remote_url.start_with?(File::SEPARATOR)
      File.expand_path(remote_url, @ws_root)
    else
      remote_url
    end
  else
    URI.parse(GerritServer).merge(URI.parse(remote_url)).to_s
  end
end

def local_changes?(ws_dir, dir=ws_dir)
  stat = nil
  RIM::git_session(ws_dir) do |s|
    stat = s.status(dir)
  end
  stat.lines.all?{|l| l.ignored?}
end

def clone_or_fetch_repository(remote_url, local_path, clone_log = nil)
  FileUtils.mkdir_p local_path
  RIM::git_session(local_path) do |s|
    if !File.exist?(File.join(local_path, ".git"))
      @logger.info(clone_log) if clone_log
      FileHelper.make_empty_dir(local_path)
      s.execute("git clone #{remote_url} .")
      s.execute("git config core.ignorecase false")
    else
      s.execute("git remote set-url origin #{remote_url}") if !s.has_valid_remote_repository?()
      s.execute("git fetch")
    end
  end
  local_path
end

def commit(session, message)
  msg_file = Tempfile.new('message')
  begin
    msg_file << message
    msg_file.close
    session.execute("git add --all")
    session.execute("git commit -F #{msg_file.path}")
  ensure
    msg_file.close(true)
  end
end

def each_module_parallel(task_desc, modules)
  if !modules.empty?
    @logger.debug "starting \"#{task_desc}\" for #{modules.size} modules\r"
    index_queue = Queue.new
    (0...modules.size).each do |i|
      index_queue << i
    end
    result_queue = Queue.new
    (1..MaxThreads).each do
      Thread.new do
        loop do
          i = index_queue.empty? ? nil : index_queue.pop(true) 
          break if i.nil?
          result = []
          begin
            yield(modules[i], i)
          rescue RimException => e
            result = e.messages
          rescue Exception => e
            result = [e.to_s]
          end
          result_queue << result
        end
      end
    end
    messages = []
    (0...modules.size).each do |i|
      messages.concat(result_queue.pop)
    end
    raise RimException.new(messages) if !messages.empty?
  end
end

def self.shorten_path(path)
  if path.length <= 10
    path.gsub(':', '#')
  else
    Digest::SHA1.hexdigest(path || '')[0...10]
  end
end  

end

end
