$:.unshift File.join(File.dirname(__FILE__),"..","lib")
$:.unshift File.join(File.dirname(__FILE__))

require 'minitest/autorun'
require 'fileutils'
require 'test_helper'
require 'rim/git'

class GitTest < Minitest::Test

include FileUtils
include TestHelper

def setup
  logger = Logger.new($stdout)
  logger.level = Logger::ERROR unless ARGV.include? "debug"
  RIM::GitSession.logger = logger
end

def test_export_rev_long_cmdline
  d = empty_test_dir("git_test")

  long_name100 = "a" * 100
  num_files = 100

  RIM.git_session(d) do |s|
    s.execute "git init"
    (1..num_files).each do |i|
      write_file "#{d}/#{i}/#{long_name100}", i.to_s
    end
    s.execute "git add ."
    s.execute "git commit -m \"test files\""

    mkdir "#{d}/out"
    s.export_rev("master", "#{d}/out", (1..num_files).collect{|i| "#{i}/#{long_name100}"})

    (1..num_files).each do |i|
      assert File.read("#{d}/out/#{i}/#{long_name100}") == i.to_s
    end
  end
end

def teardown
  # clean up test dirs created during last test
  remove_test_dirs
end

end

