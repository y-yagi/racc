$VERBOSE = true
require 'minitest/autorun'
require 'racc/static'
require 'fileutils'
require 'tempfile'

module Racc
  class TestCase < Minitest::Test
    PROJECT_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..'))

    TEST_DIR = File.join(PROJECT_DIR, 'test')

    RACC      = File.join(PROJECT_DIR, 'bin', 'racc')
    OUT_DIR   = File.join(TEST_DIR, 'out')
    TAB_DIR   = File.join(TEST_DIR, 'tab') # generated parsers go here
    LOG_DIR   = File.join(TEST_DIR, 'log')
    ERR_DIR   = File.join(TEST_DIR, 'err')
    ASSET_DIR = File.join(TEST_DIR, 'assets') # test grammars
    REGRESS_DIR  = File.join(TEST_DIR, 'regress') # known-good generated outputs

    INC = [
      File.join(PROJECT_DIR, 'lib'),
      File.join(PROJECT_DIR, 'ext'),
    ].join(':')

    def setup
      [OUT_DIR, TAB_DIR, LOG_DIR, ERR_DIR].each do |dir|
        FileUtils.mkdir_p(dir)
      end
    end

    def teardown
      [OUT_DIR, TAB_DIR, LOG_DIR, ERR_DIR].each do |dir|
        FileUtils.rm_rf(dir)
      end
    end

    def assert_compile(asset, args = [])
      file = File.basename(asset, '.y')
      args = ([args].flatten) + [
        "#{ASSET_DIR}/#{file}.y",
        '-Do',
        "-O#{OUT_DIR}/#{file}",
        "-o#{TAB_DIR}/#{file}",
      ]
      racc "#{args.join(' ')}"
    end

    def assert_debugfile(asset, ok)
      file = File.basename(asset, '.y')
      Dir.chdir(TEST_DIR) do
        File.foreach("log/#{file}.y") do |line|
          line.strip!
          case line
          when /sr/ then assert_equal "sr#{ok[0]}", line
          when /rr/ then assert_equal "rr#{ok[1]}", line
          when /un/ then assert_equal "un#{ok[2]}", line
          when /ur/ then assert_equal "ur#{ok[3]}", line
          when /ex/ then assert_equal "ex#{ok[4]}", line
          else
            raise TestFailed, 'racc outputs unknown debug report???'
          end
        end
      end
    end

    def assert_exec(asset)
      file = File.basename(asset, '.y')
      Dir.chdir(TEST_DIR) do
        ruby("#{TAB_DIR}/#{file}")
      end
    end

    def assert_output(asset)
      file = File.basename(asset, '.y')

      expected = File.read("#{REGRESS_DIR}/#{file}")
      actual   = File.read("#{TAB_DIR}/#{file}")
      result   = (expected == actual)

      assert(result, "Output of test/assets/#{file}.y differed from " \
        "expectation. Try compiling it and diff with test/regress/#{file}.")
    end

    def racc(arg)
      ruby "-S #{RACC} #{arg}"
    end

    def ruby(arg)
      Dir.chdir(TEST_DIR) do
        Tempfile.open 'test' do |io|
          executable = ENV['_'] || Gem.ruby
          if File.basename(executable) == 'bundle'
            executable = executable.dup << ' exec ruby'
          end
          cmd = "#{executable} -I #{INC} #{arg} 2>#{io.path}"
          result = system(cmd)
          assert(result, io.read)
        end
      end
    end
  end
end
