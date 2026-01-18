# frozen_string_literal: true

require "tempfile"

RSpec.describe EagerEye::AutoFixer do
  describe "#suggest" do
    let(:source_code) do
      <<~RUBY
        Post.where(user_id: User.active.pluck(:id))
      RUBY
    end

    it "shows fix suggestions" do
      file = Tempfile.new(["test", ".rb"])
      file.write(source_code)
      file.close

      issue = EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: file.path,
        line_number: 1,
        message: "test",
        severity: :warning
      )

      fixer = described_class.new([issue])
      expect { fixer.suggest }.to output(/\.pluck.*\.select/m).to_stdout

      file.unlink
    end

    it "outputs message when no fixable issues" do
      fixer = described_class.new([])
      expect { fixer.suggest }.to output(/No auto-fixable issues found/).to_stdout
    end
  end

  describe "#run" do
    context "with force mode" do
      it "applies fixes without prompting" do
        file = Tempfile.new(["test", ".rb"])
        file.write("Post.where(user_id: User.active.pluck(:id))\n")
        file.close

        issue = EagerEye::Issue.new(
          detector: :pluck_to_array,
          file_path: file.path,
          line_number: 1,
          message: "test",
          severity: :warning
        )

        fixer = described_class.new([issue], interactive: false)
        expect { fixer.run }.to output(/Fixed 1 issue/).to_stdout

        expect(File.read(file.path)).to eq("Post.where(user_id: User.active.select(:id))\n")

        file.unlink
      end
    end

    it "outputs message when no fixable issues" do
      fixer = described_class.new([])
      expect { fixer.run }.to output(/No auto-fixable issues found/).to_stdout
    end
  end
end

RSpec.describe EagerEye::Fixers::Base do
  let(:issue) do
    EagerEye::Issue.new(
      detector: :test,
      file_path: "test.rb",
      line_number: 1,
      message: "test",
      severity: :warning
    )
  end

  let(:source) { "line 1\nline 2\n" }
  subject { described_class.new(issue, source) }

  describe "#fixable?" do
    it "returns false by default" do
      expect(subject.fixable?).to be false
    end
  end

  describe "#fix" do
    it "raises NotImplementedError" do
      expect { subject.fix }.to raise_error(NotImplementedError)
    end
  end

  describe "#diff" do
    it "returns nil when not fixable" do
      expect(subject.diff).to be_nil
    end
  end
end

RSpec.describe EagerEye::Fixers::PluckToSelect do
  describe "#fixable?" do
    it "returns true for single-line pluck + where pattern" do
      issue = EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :warning
      )
      source = "Post.where(user_id: User.active.pluck(:id))\n"

      fixer = described_class.new(issue, source)
      expect(fixer.fixable?).to be true
    end

    it "returns false for multi-line pattern" do
      issue = EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: "test.rb",
        line_number: 2,
        message: "test",
        severity: :warning
      )
      source = "ids = User.pluck(:id)\nPost.where(user_id: ids)\n"

      fixer = described_class.new(issue, source)
      expect(fixer.fixable?).to be false
    end

    it "returns false for :info severity (small collections)" do
      issue = EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :info
      )
      source = "Post.where(status: Status.pluck(:id))\n"

      fixer = described_class.new(issue, source)
      expect(fixer.fixable?).to be false
    end

    it "returns false for unsafe pattern (pluck chained after where)" do
      issue = EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :warning
      )
      source = "User.where(active: true).pluck(:id)\n"

      fixer = described_class.new(issue, source)
      expect(fixer.fixable?).to be false
    end
  end

  describe "#diff" do
    it "replaces .pluck with .select" do
      issue = EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :warning
      )
      source = "Post.where(user_id: User.active.pluck(:id))\n"

      fixer = described_class.new(issue, source)
      diff = fixer.diff

      expect(diff[:original]).to eq("Post.where(user_id: User.active.pluck(:id))")
      expect(diff[:fixed]).to eq("Post.where(user_id: User.active.select(:id))")
    end
  end
end

RSpec.describe EagerEye::FixerRegistry do
  describe ".fixer_for" do
    it "returns PluckToSelect fixer for pluck_to_array" do
      issue = EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :warning
      )

      fixer = described_class.fixer_for(issue, "source")
      expect(fixer).to be_a(EagerEye::Fixers::PluckToSelect)
    end

    it "returns nil for unsupported detectors" do
      issue = EagerEye::Issue.new(
        detector: :loop_association,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :warning
      )

      fixer = described_class.fixer_for(issue, "source")
      expect(fixer).to be_nil
    end
  end

  describe ".fixable?" do
    it "returns true when issue is fixable" do
      issue = EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :warning
      )

      expect(described_class.fixable?(issue, "Post.where(user_id: User.pluck(:id))")).to be true
    end

    it "returns false when no fixer available" do
      issue = EagerEye::Issue.new(
        detector: :loop_association,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :warning
      )

      expect(described_class.fixable?(issue, "source")).to be false
    end
  end
end
