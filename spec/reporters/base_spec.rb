# frozen_string_literal: true

RSpec.describe EagerEye::Reporters::Base do
  def create_issue(attrs = {})
    EagerEye::Issue.new(
      detector: attrs[:detector] || :loop_association,
      file_path: attrs[:file_path] || "test.rb",
      line_number: attrs[:line_number] || 1,
      message: attrs[:message] || "Test",
      severity: attrs[:severity] || :warning,
      suggestion: nil
    )
  end

  describe "#initialize" do
    it "stores issues" do
      issues = [create_issue]
      reporter = described_class.new(issues)

      expect(reporter.issues).to eq(issues)
    end
  end

  describe "#report" do
    it "raises NotImplementedError" do
      reporter = described_class.new([])

      expect { reporter.report }.to raise_error(NotImplementedError)
    end
  end
end
