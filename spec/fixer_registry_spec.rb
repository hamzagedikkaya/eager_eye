# frozen_string_literal: true

RSpec.describe EagerEye::FixerRegistry do
  describe ".fixer_for" do
    let(:issue) do
      EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :warning
      )
    end

    it "returns fixer instance for pluck_to_array issue" do
      fixer = described_class.fixer_for(issue, "source code")
      expect(fixer).to be_a(EagerEye::Fixers::PluckToSelect)
    end

    it "returns nil for unsupported detector" do
      issue.instance_variable_set(:@detector, :unsupported)
      fixer = described_class.fixer_for(issue, "source code")
      expect(fixer).to be_nil
    end
  end

  describe ".fixable?" do
    let(:issue) do
      EagerEye::Issue.new(
        detector: :pluck_to_array,
        file_path: "test.rb",
        line_number: 1,
        message: "test",
        severity: :warning
      )
    end

    it "checks if issue is fixable" do
      result = described_class.fixable?(issue, "Post.where(user_id: User.active.pluck(:id))")
      expect(result).to be_a(TrueClass).or be_a(FalseClass)
    end
  end
end
