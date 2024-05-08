$:.unshift File.join(File.dirname(__FILE__),"..","lib")
$:.unshift File.join(File.dirname(__FILE__))

require 'minitest/autorun'
require 'fileutils'
require 'test_helper'
require 'rim/rim_info'
require 'rim/dirty_check'

class DirtyCheckTest < Minitest::Test

include FileUtils
include TestHelper

def test_check_empty
  d = empty_test_dir("dirty_check")
  assert RIM::DirtyCheck.dirty?(d)
end

def test_mark_clean_empty
  d = empty_test_dir("dirty_check")
  assert_raises RIM::DirtyCheck::MissingInfoException do
    RIM::DirtyCheck.mark_clean(d)
  end
end

def test_mark_clean
  d = empty_test_dir("dirty_check")
  create_rim_info(d, {
    :remote_url => "ssh://gerrit",
    :revision_sha1 => "4711"
  })
  write_file("#{d}/somefile", "some content")
  RIM::DirtyCheck.mark_clean(d)
  assert !RIM::DirtyCheck.dirty?(d)
  # some whitebox testing
  ri = RIM::RimInfo.from_dir(d)
  assert ri.checksum
end

def test_dirty_add_file
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  write_file("#{d}/otherfile", "bla")
  assert RIM::DirtyCheck.dirty?(d)
end

def test_dirty_add_file_ignored
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  write_file("#{d}/ign_file2", "bla")
  assert !RIM::DirtyCheck.dirty?(d)
end

def test_dirty_change_file
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  File.open("#{d}/file1", "a") do |f|
    f.write("another line\n")
  end
  assert RIM::DirtyCheck.dirty?(d)
end

def test_dirty_change_file_ignored
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  File.open("#{d}/ign_file1", "a") do |f|
    f.write("another line\n")
  end
  assert !RIM::DirtyCheck.dirty?(d)
end

def test_dirty_move_file
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  mv "#{d}/file1", "#{d}/file2"
  assert RIM::DirtyCheck.dirty?(d)
end

def test_dirty_move_file_ignored
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  mv "#{d}/ign_file1", "#{d}/ign_file2"
  assert !RIM::DirtyCheck.dirty?(d)
end

def test_dirty_delete_file
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  rm "#{d}/file1"
  assert RIM::DirtyCheck.dirty?(d)
end

def test_dirty_delete_file_ignored
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  rm "#{d}/ign_file1"
  assert !RIM::DirtyCheck.dirty?(d)
end

def test_dirty_move_file_and_repair
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  mv "#{d}/file1", "#{d}/file2"
  assert RIM::DirtyCheck.dirty?(d)
  mv "#{d}/file2", "#{d}/file1"
  assert !RIM::DirtyCheck.dirty?(d)
end

def test_dirty_corrupt_rim_info
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  File.open("#{d}/.riminfo", "a") do |f|
    f.write("some text")
  end
  assert RIM::DirtyCheck.dirty?(d)
end

def test_dirty_change_info
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  ri = RIM::RimInfo.from_dir(d)
  ri.revision_sha1 = "999"
  ri.to_dir(d)
  assert RIM::DirtyCheck.dirty?(d)
end

def test_dirty_change_info_and_repair
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  ri = RIM::RimInfo.from_dir(d)
  ri.revision_sha1 = "999"
  ri.to_dir(d)
  assert RIM::DirtyCheck.dirty?(d)
  ri.revision_sha1 = "4711"
  ri.to_dir(d)
  assert !RIM::DirtyCheck.dirty?(d)
end

def test_ignore_glob
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  write_file("#{d}/file.ign", "bla")
  assert !RIM::DirtyCheck.dirty?(d)
  write_file("#{d}/dir1/file.ign", "bla")
  assert RIM::DirtyCheck.dirty?(d)
end

def test_ignore_doubleglob
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  write_file("#{d}/file.ign2", "bla")
  assert !RIM::DirtyCheck.dirty?(d)
  write_file("#{d}/dir1/file.ign2", "bla")
  assert !RIM::DirtyCheck.dirty?(d)
end

def test_line_ending_change
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  fn = "#{d}/file1"
  lines = ["a", "b", "c"]
  File.open(fn, "wb") do |f|
    lines.each do |l|
      f.write("#{l}\n")
    end
  end
  RIM::DirtyCheck.mark_clean(d)
  File.open(fn, "wb") do |f|
    lines.each do |l|
      f.write("#{l}\r\n")
    end
  end
  assert !RIM::DirtyCheck.dirty?(d)
  File.open(fn, "wb") do |f|
    lines.each do |l|
      f.write("#{l}\n")
    end
  end
  assert !RIM::DirtyCheck.dirty?(d)
end

def test_empty_dir
  d = empty_test_dir("dirty_check")
  setup_clean_test_module(d)
  mkdir "#{d}/emptydir"
  assert !RIM::DirtyCheck.dirty?(d)
end

def teardown
  # clean up test dirs created during last test
  remove_test_dirs
end

private

def setup_clean_test_module(dir)
  create_rim_info(dir, {
    :remote_url => "ssh://gerrit",
    :ignores => "ign_file1,ign_file2,*.ign,**/*.ign2",
    :revision_sha1 => "4711"
  })
  write_file("#{dir}/file1", "some content")
  write_file("#{dir}/ign_file1", "ignored stuff")
  write_file("#{dir}/dir1/file2", "more content")
  RIM::DirtyCheck.mark_clean(dir)
  assert !RIM::DirtyCheck.dirty?(dir)
end

end
