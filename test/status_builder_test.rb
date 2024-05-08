$:.unshift File.join(File.dirname(__FILE__),"..","lib")
$:.unshift File.join(File.dirname(__FILE__))

require 'minitest/autorun'
require 'fileutils'
require 'test_helper'
require 'rim/git'
require 'rim/dirty_check'
require 'rim/status_builder'

class StatusBuilderTest < Minitest::Test

include FileUtils
include TestHelper

def setup
  logger = Logger.new($stdout)
  logger.level = Logger::ERROR unless ARGV.include? "debug"
  RIM::GitSession.logger = logger
end

def test_fs_status
  d = empty_test_dir("rim_info")
  setup_clean_test_module("#{d}/mod1")
  setup_clean_test_module("#{d}/subdir/mod2")

  rs = RIM::StatusBuilder.new.fs_status(d)

  assert_equal 2, rs.modules.size
  assert_equal [], rs.parents
  assert_nil rs.git_rev
  assert rs.modules.all?{|m| !m.dirty?}

  ms = rs.modules.find{|m| m.dir == "mod1"}
  assert ms
  assert_equal "ssh://gerrit-test/mod1", ms.rim_info.remote_url

  ms = rs.modules.find{|m| m.dir == "subdir/mod2"}
  assert ms
  assert_equal "ssh://gerrit-test/mod2", ms.rim_info.remote_url
end

def test_fs_status_dirty
  d = empty_test_dir("rim_info")
  setup_clean_test_module("#{d}/mod1")
  write_file "#{d}/mod1/unwanted", "content"

  rs = RIM::StatusBuilder.new.fs_status(d)
  assert rs.modules.first.dirty?
end

def test_rev_status
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)

    rs = RIM::StatusBuilder.new.rev_status(s, "mod1~1")
    assert_equal s.rev_sha1("mod1~1"), rs.git_rev
    assert_equal [], rs.parents
    assert_equal [], rs.modules

    rs = RIM::StatusBuilder.new.rev_status(s, "mod1")
    assert_equal s.rev_sha1("mod1"), rs.git_rev
    assert_equal [], rs.parents
    assert_equal 1, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url

    rs = RIM::StatusBuilder.new.rev_status(s, "mod2~1")
    assert_equal s.rev_sha1("mod2~1"), rs.git_rev
    assert_equal [], rs.parents
    assert_equal 1, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url

    rs = RIM::StatusBuilder.new.rev_status(s, "mod2")
    assert_equal s.rev_sha1("mod2"), rs.git_rev
    assert_equal [], rs.parents
    assert_equal 2, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url
    assert_equal "ssh://gerrit-test/mod2", rs.modules.find{|m| m.dir == "mod2"}.rim_info.remote_url
  end
end

def test_rev_module_status
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)

    ms = RIM::StatusBuilder.new.rev_module_status(s, "mod1~1", "mod1")
    assert !ms

    ms = RIM::StatusBuilder.new.rev_module_status(s, "mod1", "mod1")
    assert ms
    assert !ms.dirty?
    assert_equal "ssh://gerrit-test/mod1", ms.rim_info.remote_url
  end

end

def test_rev_history_status(fast=false)
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)

    rs = RIM::StatusBuilder.new.rev_history_status(s, "mod2", :fast => fast)
    assert_equal 4, all_status_objects(rs).size

    assert_equal s.rev_sha1("mod2"), rs.git_rev
    assert_equal 1, rs.parents.size
    assert_equal 2, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url
    assert_equal "ssh://gerrit-test/mod2", rs.modules.find{|m| m.dir == "mod2"}.rim_info.remote_url

    rs = rs.parents.first
    assert_equal s.rev_sha1("mod2~1"), rs.git_rev
    assert_equal 1, rs.parents.size
    assert_equal 1, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url

    rs = rs.parents.first
    assert_equal s.rev_sha1("mod2~2"), rs.git_rev
    assert_equal 1, rs.parents.size
    assert_equal 1, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url

    rs = rs.parents.first
    assert_equal s.rev_sha1("mod2~3"), rs.git_rev
    assert_equal 0, rs.parents.size
    assert_equal 0, rs.modules.size
  end
end

def test_rev_history_status_fast
  test_rev_history_status(true)
end

def test_rev_history_status_until_remote(fast=false)
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)

    # fake remote branch
    write_file "#{d}/.git/refs/remotes/origin/master", s.rev_sha1('master~1')

    rs = RIM::StatusBuilder.new.rev_history_status(s, "master", :fast => fast)
    assert_equal 2, all_status_objects(rs).size

    assert_equal 1, rs.parents.size
    assert_equal 2, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url
    assert_equal "ssh://gerrit-test/mod2", rs.modules.find{|m| m.dir == "mod2"}.rim_info.remote_url

    rs = rs.parents.first
    assert_equal 0, rs.parents.size
    assert_equal 1, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url
  end
end

def test_rev_history_status_until_remote_fast
  test_rev_history_status_until_remote(true)
end

# if the commit we request history for has already been pushed to remote
# we just return the status for that commit but don't build up any history
def test_rev_history_status_until_remote_no_local_commit(fast=false)
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)

    # fake remote branch
    write_file "#{d}/.git/refs/remotes/origin/master", s.rev_sha1('master')

    # head of remote branch
    rs = RIM::StatusBuilder.new.rev_history_status(s, "master", :fast => fast)
    assert_equal 1, all_status_objects(rs).size

    # ancestor of remote branch
    rs = RIM::StatusBuilder.new.rev_history_status(s, "master~1", :fast => fast)
    assert_equal 1, all_status_objects(rs).size
  end
end

def test_rev_history_status_until_remote_no_local_commit_fast
  test_rev_history_status_until_remote_no_local_commit(true)
end

def test_rev_history_status_merge_commit(fast=false)
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)
    test_git_add_merge_commit(s, d)

    rs = RIM::StatusBuilder.new.rev_history_status(s, "devel", :fast => fast)
    assert_equal 6, all_status_objects(rs).size

    assert_equal 2, rs.parents.size
    assert_equal 3, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url
    assert_equal "ssh://gerrit-test/mod2", rs.modules.find{|m| m.dir == "mod2"}.rim_info.remote_url
    assert_equal "ssh://gerrit-test/mod3", rs.modules.find{|m| m.dir == "mod3"}.rim_info.remote_url

    mod2_branch_status = rs.parents.find{|p| p.modules.any?{|m| m.dir == "mod2"}}
    mod3_branch_status = rs.parents.find{|p| p.modules.any?{|m| m.dir == "mod3"}}

    # there is one single status object where devel and master branch join
    assert mod2_branch_status.parents[0].parents[0].object_id == 
           mod3_branch_status.parents[0].object_id
  end
end

def test_rev_history_status_merge_commit_fast
  test_rev_history_status_merge_commit(true)
end

#
#                      o     <- devel
#                      |\
#           master ->  o o   <- origin/devel
#                      | |
#    origin/master ->  o |
#                      |/
#                      o     
#                      |
#                      o
#
def test_rev_history_status_merge_commit_until_remote(fast=false)
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)
    test_git_add_merge_commit(s, d)

    # fake remote branch
    write_file "#{d}/.git/refs/remotes/origin/master", s.rev_sha1('master~1')
    write_file "#{d}/.git/refs/remotes/origin/devel", s.rev_sha1('devel~1')

    rs = RIM::StatusBuilder.new.rev_history_status(s, "devel", :fast => fast)
    assert_equal 4, all_status_objects(rs).size
  end
end

def test_rev_history_status_merge_commit_until_remote_fast
  test_rev_history_status_merge_commit_until_remote(true)
end

# in this case we only have a remote branch on master but not on devel;
# when following devel back to the root, we don't hit any remote branch;
# nevertheless, the history must be cut off at commits which have already
# been pushed to some remote
#
#                      o     <- devel
#    master            |\
#    origin/master ->  o o   <= no remote branch here
#                      | |
#                      o |
#                      |/
#                      o     <= status for devel branch must stop here
#                      |
#                      o
#
def test_rev_history_status_merge_commit_bypass_remote_branch(fast=false)
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)
    test_git_add_merge_commit(s, d)

    # fake remote branch
    write_file "#{d}/.git/refs/remotes/origin/master", s.rev_sha1('master')

    rs = RIM::StatusBuilder.new.rev_history_status(s, "devel", :fast => fast)
    assert_equal 4, all_status_objects(rs).size
  end
end

def test_rev_history_status_merge_commit_bypass_remote_branch_fast
  test_rev_history_status_merge_commit_bypass_remote_branch(true)
end

#            o <- mod1 deleted
#            |
# master ->  o
# /mod2      |
#            o
#            |
#   mod1 ->  o
#            |
#            o
#
def test_rev_history_status_module_removed(fast=false)
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)
    s.execute "git rm -r mod1"
    s.execute "git commit -m \"removed mod1\""

    rs = RIM::StatusBuilder.new.rev_history_status(s, "master", :fast => fast)
    assert_equal 5, all_status_objects(rs).size

    assert_equal 1, rs.modules.size
    assert_equal 2, rs.parents.first.modules.size
  end
end

def test_rev_history_status_module_removed_fast
  test_rev_history_status_module_removed(true)
end

#            o <- mod1 made dirty
#            |
# master ->  o
# /mod2      |
#            o
#            |
#   mod1 ->  o
#            |
#            o
#
def test_rev_history_status_module_modified_dirty(fast=false)
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)
    write_file("#{d}/mod1/newfile", "nothing")
    s.execute "git add ."
    s.execute "git commit -m \"new file making mod1 dirty\""

    rs = RIM::StatusBuilder.new.rev_history_status(s, "master", :fast => fast)
    assert_equal 5, all_status_objects(rs).size

    assert_equal 2, rs.modules.size
    ms = rs.modules.find{|m| m.dir == "mod1"}
    assert ms.dirty?
    ms = rs.modules.find{|m| m.dir == "mod2"}
    assert !ms.dirty?
  end
end

def test_rev_history_status_module_modified_dirty_fast
  test_rev_history_status_module_modified_dirty(true)
end

#            o <- mod1 modified but clean
#            |
# master ->  o
# /mod2      |
#            o
#            |
#   mod1 ->  o
#            |
#            o
#
def test_rev_history_status_module_modified_clean(fast=false)
  d = empty_test_dir("rim_info")

  RIM.git_session(d) do |s|
    test_git_setup(s, d)
    write_file("#{d}/mod1/newfile", "nothing")
    RIM::DirtyCheck.mark_clean("#{d}/mod1")
    s.execute "git add ."
    s.execute "git commit -m \"new file making mod1 dirty\""

    rs = RIM::StatusBuilder.new.rev_history_status(s, "master", :fast => fast)
    assert_equal 5, all_status_objects(rs).size

    assert_equal 2, rs.modules.size
    ms = rs.modules.find{|m| m.dir == "mod1"}
    assert !ms.dirty?
    ms = rs.modules.find{|m| m.dir == "mod2"}
    assert !ms.dirty?
  end
end

def test_rev_history_status_module_modified_clean_fast
  test_rev_history_status_module_modified_clean(true)
end

def test_status_works_on_bare_repository
  src = empty_test_dir("rim_info")
  RIM.git_session(src) do |s|
    test_git_setup(s, src)
  end
  d = empty_test_dir("rim_info_bare")
  RIM.git_session(d) do |s|
    s.execute("git clone --bare file://#{src} .")
    rs = RIM::StatusBuilder.new.rev_status(s, "mod1")
    assert_equal s.rev_sha1("mod1"), rs.git_rev
    assert_equal [], rs.parents
    assert_equal 1, rs.modules.size
    assert rs.modules.all?{|m| !m.dirty?}
    assert_equal "ssh://gerrit-test/mod1", rs.modules.find{|m| m.dir == "mod1"}.rim_info.remote_url
  end
end

def teardown
  # clean up test dirs created during last test
  remove_test_dirs
end

private

def all_status_objects(rs)
  [rs] | rs.parents.collect{|p| all_status_objects(p)}.flatten
end

# master ->  o
# /mod2      |
#            o
#            |
#   mod1 ->  o
#            |
#            o
#
def test_git_setup(gs, dir)
  gs.execute "git init"

  write_file "#{dir}/unrelated_file", "anything"
  gs.execute "git add ."
  gs.execute "git commit -m \"initial\""

  setup_clean_test_module("#{dir}/mod1")
  gs.execute "git add ."
  gs.execute "git commit -m \"added mod1\""
  gs.execute "git tag mod1"

  write_file "#{dir}/unrelated_file", "anything changes"
  gs.execute "git add ."
  gs.execute "git commit -m \"some unrelated change\""

  setup_clean_test_module("#{dir}/mod2")
  gs.execute "git add ."
  gs.execute "git commit -m \"added mod2\""
  gs.execute "git tag mod2"
end

# creates devel branch branching of at tag mod1
# creates a merge commit on branch "devel"
# to be called after test_git_setup
#
#            o     <- devel
#            |\
# master ->  o o   <- mod3
# /mod2      | |
#            o |
#            |/
#   mod1 ->  o
#            |
#            o
#
def test_git_add_merge_commit(gs, dir)
  gs.execute "git checkout -b devel mod1"
  setup_clean_test_module("#{dir}/mod3")
  gs.execute "git add ."
  gs.execute "git commit -m \"added mod3\""
  gs.execute "git tag mod3"
  gs.execute "git merge master"
end

# create a module in dir complete with rim info
def setup_clean_test_module(dir)
  create_rim_info(dir, {
    :remote_url => "ssh://gerrit-test/#{File.basename(dir)}",
    :revision_sha1 => "12345"
  })
  write_file "#{dir}/file1", "some content"
  write_file "#{dir}/dir1/file2", "some other content"
  RIM::DirtyCheck.mark_clean(dir)
  assert !RIM::DirtyCheck.dirty?(dir)
end

end

