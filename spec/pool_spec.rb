# frozen_string_literal: true

require "tmpdir"
require "taskforge"

RSpec.describe Taskforge::Pool do
  let(:cache) { File.join(Dir.tmpdir, "taskforge-spec-cache") }

  it "runs commands as subprocesses" do
    Dir.mktmpdir do |dir|
      jobs = 3.times.map { |i| described_class::Job.new("touch-#{i}", "touch out-#{i}") }
      described_class.new(dir, jobs, cache_root: cache).run
      3.times { |i| expect(File.exist?(File.join(dir, "out-#{i}"))).to be(true) }
    end
  end

  it "raises when a command keeps failing after the retry" do
    jobs = [described_class::Job.new("ok", "true"), described_class::Job.new("bad", "false")]
    pool = described_class.new(Dir.pwd, jobs, cache_root: cache)
    expect { pool.run }.to raise_error(described_class::Error, /bad/)
  end

  it "runs sequentially with TASKFORGE_JOBS=1" do
    Dir.mktmpdir do |dir|
      ENV["TASKFORGE_JOBS"] = "1"
      jobs = 2.times.map { |i| described_class::Job.new("seq-#{i}", "touch s-#{i}") }
      described_class.new(dir, jobs, cache_root: cache).run
      2.times { |i| expect(File.exist?(File.join(dir, "s-#{i}"))).to be(true) }
    end
  ensure
    ENV.delete("TASKFORGE_JOBS")
  end
end
