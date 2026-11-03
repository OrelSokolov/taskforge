# frozen_string_literal: true

require "tmpdir"
require "taskforge"

RSpec.describe Taskforge::Pool do
  let(:cache) { File.join(Dir.tmpdir, "taskforge-spec-cache") }

  it "runs a plain array of command strings" do
    Dir.mktmpdir do |dir|
      commands = 3.times.map { |i| "touch out-#{i}" }
      described_class.new(dir, commands, cache_root: cache).run
      3.times { |i| expect(File.exist?(File.join(dir, "out-#{i}"))).to be(true) }
    end
  end

  it "raises when a command keeps failing after the retry" do
    pool = described_class.new(Dir.pwd, ["true", "false"], cache_root: cache)
    expect { pool.run }.to raise_error(described_class::Error, /false/)
  end

  it "runs sequentially with TASKFORGE_JOBS=1" do
    Dir.mktmpdir do |dir|
      ENV["TASKFORGE_JOBS"] = "1"
      described_class.new(dir, ["touch s-0", "touch s-1"], cache_root: cache).run
      expect(File.exist?(File.join(dir, "s-1"))).to be(true)
    end
  ensure
    ENV.delete("TASKFORGE_JOBS")
  end
end

RSpec.describe Taskforge do
  it "runs an array of commands in the given directory" do
    Dir.mktmpdir do |dir|
      described_class.run(["touch a", "touch b"], dir)
      expect(File.exist?(File.join(dir, "b"))).to be(true)
    end
  end

  it "runs a single command string" do
    Dir.mktmpdir do |dir|
      described_class.run("touch solo", dir)
      expect(File.exist?(File.join(dir, "solo"))).to be(true)
    end
  end

  it "runs the DSL block, with an optional directory" do
    Dir.mktmpdir do |dir|
      described_class.run(dir) do
        job "touch dsl-1"
        job "touch dsl-2"
      end
      2.times { |i| expect(File.exist?(File.join(dir, "dsl-#{i + 1}"))).to be(true) }
    end
  end
end
