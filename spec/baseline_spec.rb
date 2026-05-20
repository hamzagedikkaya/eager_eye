# frozen_string_literal: true

require "json"
require "tempfile"

RSpec.describe EagerEye::Baseline do
  let(:issue1) do
    EagerEye::Issue.new(
      detector: :loop_association,
      file_path: "app/models/a.rb",
      line_number: 10,
      message: "old issue",
      severity: :error
    )
  end

  let(:issue2) do
    EagerEye::Issue.new(
      detector: :pluck_to_array,
      file_path: "app/models/b.rb",
      line_number: 20,
      message: "another old issue",
      severity: :warning
    )
  end

  let(:new_issue) do
    EagerEye::Issue.new(
      detector: :callback_query,
      file_path: "app/models/c.rb",
      line_number: 5,
      message: "new issue",
      severity: :error
    )
  end

  def write_baseline(issues, format: :report)
    file = Tempfile.new(["baseline", ".json"])
    payload = case format
              when :report then { summary: { total: issues.size }, issues: issues.map(&:to_h) }
              when :array  then issues.map(&:to_h)
              when :raw    then issues
              end
    file.write(JSON.generate(payload))
    file.close
    file.path
  end

  describe ".load_issues" do
    it "loads issues from a full report-shaped JSON" do
      path = write_baseline([issue1, issue2])
      loaded = described_class.load_issues(path)
      expect(loaded).to contain_exactly(issue1, issue2)
    end

    it "loads issues from a plain JSON array" do
      path = write_baseline([issue1], format: :array)
      loaded = described_class.load_issues(path)
      expect(loaded).to contain_exactly(issue1)
    end

    it "raises InvalidBaselineError when file is missing" do
      expect { described_class.load_issues("/nonexistent/path.json") }
        .to raise_error(EagerEye::Baseline::InvalidBaselineError, /not found/)
    end

    it "raises InvalidBaselineError on malformed JSON" do
      file = Tempfile.new(["bad", ".json"])
      file.write("{ not valid json")
      file.close
      expect { described_class.load_issues(file.path) }
        .to raise_error(EagerEye::Baseline::InvalidBaselineError, /Invalid JSON/)
    end

    it "raises InvalidBaselineError when issues key missing in object" do
      path = write_baseline({ summary: {} }, format: :raw)
      expect { described_class.load_issues(path) }
        .to raise_error(EagerEye::Baseline::InvalidBaselineError, /missing 'issues' array/)
    end

    it "raises InvalidBaselineError on unsupported top-level type" do
      path = write_baseline("a string", format: :raw)
      expect { described_class.load_issues(path) }
        .to raise_error(EagerEye::Baseline::InvalidBaselineError)
    end
  end

  describe ".filter" do
    it "removes issues that already exist in the baseline" do
      path = write_baseline([issue1, issue2])
      result = described_class.filter([issue1, issue2, new_issue], path)
      expect(result).to contain_exactly(new_issue)
    end

    it "returns all current issues when baseline is empty" do
      path = write_baseline([])
      result = described_class.filter([issue1, new_issue], path)
      expect(result).to contain_exactly(issue1, new_issue)
    end

    it "returns empty array when all current issues are in baseline" do
      path = write_baseline([issue1, issue2])
      result = described_class.filter([issue1, issue2], path)
      expect(result).to eq([])
    end

    it "preserves input order for new issues" do
      path = write_baseline([issue2])
      result = described_class.filter([issue1, issue2, new_issue], path)
      expect(result).to eq([issue1, new_issue])
    end

    it "propagates InvalidBaselineError from a bad path" do
      expect { described_class.filter([issue1], "/nope.json") }
        .to raise_error(EagerEye::Baseline::InvalidBaselineError)
    end
  end
end
