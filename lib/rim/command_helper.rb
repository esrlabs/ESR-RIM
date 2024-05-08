require 'rim/file_helper'
require 'rim/processor'
require 'rim/module_info'
require 'rim/rim_info'
require 'rim/manifest/json_reader'
require 'rim/status_builder'
require 'pathname'

module RIM

class CommandHelper < Processor

  include Manifest

  def initialize(workspace_root, logger, module_infos = nil)
    super(workspace_root, logger)
    @paths = []
    @logger = logger
    if module_infos
      module_infos.each do |m|
        add_module_info(m)
      end
    end
  end

  # check whether workspace is not touched
  def check_ready
    raise RimException.new("The workspace git contains uncommitted changes.") if !local_changes?(@ws_root)
  end

  def check_arguments
    raise RimException.new("Unexpected command line arguments.") if !ARGV.empty?
  end

  def create_module_info(remote_url, local_path, target_revision, ignores, subdir)
    ModuleInfo.new(
        remote_url,
        FileHelper.get_relative_path(local_path),
        target_revision,
        ignores,
        remote_url ? get_remote_branch_format(remote_url) : nil,
        subdir)
  end

  def modules_from_manifest(path)
    manifest = read_manifest(path)
    manifest.modules.each do |mod|
      add_unique_module_info(create_module_info(mod.remote_path, mod.local_path, mod.target_revision, mod.ignores, mod.subdir))
    end
    true
  end

  def modules_from_paths(paths, opts = {})
    if paths.empty?
      module_from_path(nil, opts)
    elsif paths.length == 1 || !opts.has_key?(:remote_url)
      while !paths.empty?
        module_from_path(paths.shift, opts)
      end
    else
      raise RimException.new("Multiple modules cannot be used with URL option.")
    end
  end

  def module_from_path(path, opts = {})
    module_path = find_file_dir_in_workspace(path || ".", RimInfo::InfoFileName)
    if module_path
      rim_info = RimInfo.from_dir(module_path)
      module_info = create_module_info(
        opts.has_key?(:remote_url) ? opts[:remote_url] : rim_info.remote_url,
        module_path,
        opts.has_key?(:target_revision) ? opts[:target_revision] : rim_info.target_revision,
        opts.has_key?(:ignores) ? opts[:ignores] : rim_info.ignores,
        opts.has_key?(:subdir) ? opts[:subdir] : rim_info.subdir)
      if module_info.valid?
        add_unique_module_info(module_info)
        module_path
      else
        raise RimException.new("Invalid .riminfo file found in directory '#{module_path}'.")
      end
    else
      raise RimException.new(path ? "No module info found in '#{path}'." : "No module info found.")
    end
  end

  def module_paths(paths, exclude_paths = nil)
    module_paths = []
    (paths.empty? ? ['.'] : paths).each do |p|
      module_paths.concat(all_module_paths_from_path(p))
    end
    paths.clear
    if exclude_paths
      exclude_paths.each do |e|
        all_module_paths_from_path(e).each do |p|
          module_paths.delete(p)
        end
      end
    end
    module_paths.sort
  end

  def all_module_paths_from_path(path)
    Dir.glob(File.join(path, "**/.riminfo")).map { |f| Pathname.new(File.expand_path(File.dirname(f))).relative_path_from(Pathname.pwd).to_s }
  end

  def add_unique_module_info(module_info)
    if !@paths.include?(module_info.local_path)
      @paths.push(module_info.local_path)
      add_module_info(module_info)
    else
      raise RimException.new("Module '#{module_info.local_path}' specified more than once.")
    end
  end

  def get_remote_branch_format(remote_url)
    get_absolute_remote_url(remote_url).start_with?(GerritServer) ? "refs/for/%s" : nil
    #"refs/for/%s"
  end

  def find_file_dir_in_workspace(start_dir, file)
    path = File.expand_path(start_dir)
    loop do
      if File.exist?(File.join(path, file))
        return path
      elsif path != @ws_root
        parent = File.dirname(path)
        if parent != path
          path = parent
        else
          return nil
        end
      else
        return nil
      end
    end
  end

protected
  def add_module_info(module_info)
  end

end

end
