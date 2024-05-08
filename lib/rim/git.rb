require 'tmpdir'
require 'logger'

module RIM

# raised when there is an error emitted by git call
class GitException < Exception
  attr_reader :cmd, :exitstatus, :out
  def initialize(cmd, exitstatus, out)
    super("git \"#{cmd}\" => #{exitstatus}\n#{out}")
    @cmd = cmd
    @exitstatus = exitstatus
    @out = out
  end
end

class GitSession

  attr_reader :execute_dir

  def initialize(logger, execute_dir, arg = {})
    @execute_dir = execute_dir
    if arg.is_a?(Hash)
      @work_dir = arg.has_key?(:work_dir) ? arg[:work_dir] : ""
      @git_dir = arg.has_key?(:git_dir) ? arg[:git_dir] : ""
    end
    @logger = logger
  end

  def self.logger=(logger)
    @logger = logger
  end

  def self.open(execute_dir, options = {})
    log = @logger || Logger.new($stdout)
    new(log, execute_dir, options)
  end

  def self.next_invocation_id
    @invocation_id ||= 0
    @invocation_id += 1
  end

  class Status
    attr_accessor :lines

    # X          Y     Meaning
    # -------------------------------------------------
    #           [MD]   not updated
    # M        [ MD]   updated in index
    # A        [ MD]   added to index
    # D         [ M]   deleted from index
    # R        [ MD]   renamed in index
    # C        [ MD]   copied in index
    # [MARC]           index and work tree matches
    # [ MARC]     M    work tree changed since index
    # [ MARC]     D    deleted in work tree
    # -------------------------------------------------
    # D           D    unmerged, both deleted
    # A           U    unmerged, added by us
    # U           D    unmerged, deleted by them
    # U           A    unmerged, added by them
    # D           U    unmerged, deleted by us
    # A           A    unmerged, both added
    # U           U    unmerged, both modified
    # -------------------------------------------------
    # ?           ?    untracked
    # !           !    ignored
    # -------------------------------------------------
    class Line
      attr_accessor :istat, :wstat, :file, :rename

      def untracked?
        istat == "?" && wstat == "?"
      end

      def ignored?
        istat == "!" && wstat == "!"
      end

      def unmerged?
        istat == "D" && wstat == "D" ||
        istat == "A" && wstat == "A" ||
        istat == "U" ||
        wstat == "U"
      end

    end
  end

  # returns the current branch
  def current_branch
    out = execute "git branch"
    out.split("\n").each do |l| 
      if !l.include?('(') && (l =~ /^\*\s+(\S+)/)
        return $1
      end
    end
    nil
  end

  # check whether a commit exists
  def commit_exists?(sha)
    execute("git rev-parse --quiet --verify #{sha}^{commit}") do |b, e|
      return !e
    end
  end
  
  # check whether branch exists
  def has_branch?(branch)
    execute("git show-ref refs/heads/#{branch}") do |b, e|
      return !e
    end
  end
  
  # check whether remote branch exists
  def has_remote_branch?(branch)
    out = execute("git ls-remote --heads")
    out.split("\n").each do |l|
      return true if l.split(/\s+/)[1] == "refs/heads/#{branch}"
    end
    false
  end 
  
  # check whether remote repository is valid
  def has_valid_remote_repository?()
    execute("git ls-remote") do |b, e|
      return !e
    end
  end 

  # checks whether the first (ancestor) revision is is ancestor of the second (child) revision
  def is_ancestor?(ancestor, child)
    execute("git merge-base --is-ancestor #{ancestor} #{child}") do |b, e|
      return !e
    end
  end

  # returns the parent commits of rev as SHA-1s 
  # returns an empty array if there are no parents (e.g. orphan or initial)
  def parent_revs(rev)
    out = execute "git rev-list -n 1 --parents #{rev} --"
    out.strip.split[1..-1]
  end

  # returns the SHA-1 representation of rev
  def rev_sha1(rev)
    sha1 = nil
    execute "git rev-list -n 1 #{rev} --" do |out, e|
      sha1 = out.strip if !e
    end
    sha1
  end

  # returns some informations about a revision
  def rev_infos(rev, desired)
    info = {}
    desired.each_pair do |key, value|
      execute "git log -1 --format=#{value} #{rev} --" do |out, e|
        info[key] = out.strip if !e
      end
    end
    info
  end
  
  # returns the SHA-1 representations of the heads of all remote branches
  def remote_branch_revs
    out = execute "git show-ref"
    out.split("\n").collect { |l|
      if l =~ /refs\/remotes\//
        l.split[0]
      else
        nil
      end
    }.compact
  end

  # all commits reachable from rev which are not ancestors of remote branches
  def all_reachable_non_remote_revs(rev)
    out = execute "git rev-list #{rev} --not --remotes --"
    out.split("\n")
  end

  # export file contents of rev to dir
  # if +paths+ is given and non-empty, checks out only those parts of the filesystem tree
  # does not remove any files from dir which existed before
  def export_rev(rev, dir, paths=[])
    paths = paths.dup
    loop do
      path_args = ""
      # max command line length on Windows XP and higher is 8191
      # consider the following extra characters which will be added:
      # up to 3 paths in execute, 1 path for tar, max path length 260 = 1040
      # plus some "glue" characters, plus the last path item with 260 max;
      # use 6000 to be on the safe side
      while !paths.empty? && path_args.size < 6000
        path_args << " "
        path_args << paths.shift
      end
      execute "git archive --format tar #{rev} #{path_args} | tar -C #{dir} -xf -"
      break if paths.empty?
    end
  end

  # checks out rev to a temporary directory and yields this directory to the given block
  # if +paths+ is given and non-empty, checks out only those parts of the filesystem tree
  # returns the value returned by the block
  def within_exported_rev(rev, paths=[])
    Dir.mktmpdir("rim") do |d|
      d = Dir.glob(d)[0]
      c = File.join(d, "content")
      FileUtils.mkdir(c)
      export_rev(rev, c, paths)
      # return contents of yielded block
      # mktmpdir returns value return by our block
      yield c
      FileUtils.rm_rf(c)
      # retry to delete if it hasn't been deleted yet
      # this could be due to Windows keeping the files locked for some time
      # this is especially a problem if the machine is at its limits
      retries = 600
      while File.exist?(c) && retries > 0
        sleep(0.1)
        FileUtils.rm_rf(c)
        retries -= 1
      end
      if File.exist?(c)
        @logger.warn "could not delete temp dir: #{c}"
      end
    end
  end
    
  def uncommited_changes?
    # either no status lines are all of them due to ignored items
    !status.lines.all?{|l| l.ignored?}
  end

  def current_branch_name
    out = execute "git rev-parse --abbrev-ref HEAD"
    out.strip
  end

  ChangedFile = Struct.new(:path, :kind)

  # returns a list of all files which changed in commit +rev+
  # together with the kind of the change (:modified, :deleted, :added)
  #
  # if +from_rev+ is given, lists changes between +from_rev and +rev+
  # with one argument only, no changes will be returned for merge commits
  # use the two argument variant for merge commits and decide for one parent
  def changed_files(rev, rev_from=nil)
    out = execute "git diff-tree -r --no-commit-id #{rev_from} #{rev}"
    out.split("\n").collect do |l|
      cols = l.split
      path = cols[5]
      kind = case cols[4]
        when "M"
          :modified
        when "A"
          :added
        when "D"
          :deleted
        else
          nil
        end
      ChangedFile.new(path, kind)
    end
  end

  # 3 most significant numbers of git version of nil if it can't be determined
  def git_version
    out = execute("git --version")
    if out =~ /^git version (\d+\.\d+\.\d+)/
      $1
    else
      nil
    end
  end

  def status(dir = nil)
    # -s            short format
    # --ignored     show ignored
    out = execute "git status -s --ignored #{dir}"
    parse_status(out)
  end

  def execute(cmd)
    raise "git command has to start with 'git'" unless cmd.start_with? "git "
    cmd.slice!("git ")
    # remove any newlines as they will cause the command line to end prematurely
    cmd.gsub!("\n", "")
    options = ((!@execute_dir || @execute_dir == ".") ? "" : " -C #{@execute_dir}") \
        + (@work_dir.empty? ? "" : " --work-tree=#{File.expand_path(@work_dir)}") \
        + (@git_dir.empty? ? "" : " --git-dir=#{File.expand_path(@git_dir)}") 
    cmd = "git#{options} #{cmd} 2>&1"

    out = `#{cmd}`
    # make sure we don't run into any encoding misinterpretation issues
    out.force_encoding("binary")

    exitstatus = $?.exitstatus

    invid = self.class.next_invocation_id.to_s.ljust(4)
    @logger.debug "git##{invid} \"#{cmd}\" => #{exitstatus}" 

    out.split(/\r?\n/).each do |ol|
      @logger.debug "git##{invid} out : #{ol}"
    end

    exception = exitstatus != 0 ? GitException.new(cmd, exitstatus, out) : nil
    
    if block_given?
      yield out, exception  
    elsif exception
      raise exception
    end

    out
  end

  private

  def parse_status(out)
    status = Status.new
    status.lines = []
    out.split(/\r?\n/).each do |l|
      sl = Status::Line.new
      sl.istat, sl.wstat = l[0], l[1]
      f1, f2 = l[3..-1].split(" -> ")
      f1 = unquote(f1)
      f2 = unquote(f2) if f2
      sl.file = f1
      sl.rename = f2
      status.lines << sl
    end
    status
  end

  def unquote(s)
    if s[0] == "\"" && s[-1] == "\""
      s = s[1..-2]
      s.gsub!("\\\\", "\\")
      s.gsub!("\\\"", "\"")
      s.gsub!("\\t", "\t")
      s.gsub!("\\r", "\r")
      s.gsub!("\\n", "\n")
    end
    s
  end

end

def RIM.git_session(execute_dir, options = {})
  s = GitSession.open(execute_dir, options)
  yield s
end

end
