# frozen_string_literal: true

require "json"

RSpec.describe EagerEye::Reporters::Json do
  def create_issue(attrs = {})
    EagerEye::Issue.new(
      detector: attrs[:detector] || :loop_association,
      file_path: attrs[:file_path] || "app/controllers/posts_controller.rb",
      line_number: attrs[:line_number] || 15,
      message: attrs[:message] || "Potential N+1 query",
      severity: attrs[:severity] || :warning,
      suggestion: attrs[:suggestion]
    )
  end

  describe "#report" do
    context "with no issues" do
      it "returns empty issues array" do
        reporter = described_class.new([])
        result = JSON.parse(reporter.report)

        expect(result["issues"]).to eq([])
        expect(result["summary"]["total"]).to eq(0)
      end
    end

    context "with issues" do
      let(:issues) do
        [
          create_issue(
            file_path: "app/controllers/posts_controller.rb",
            line_number: 15,
            message: "Potential N+1 query",
            suggestion: "Use includes(:author)"
          ),
          create_issue(
            file_path: "app/serializers/post_serializer.rb",
            line_number: 8,
            detector: :serializer_nesting,
            severity: :error
          )
        ]
      end

      let(:reporter) { described_class.new(issues) }
      let(:result) { JSON.parse(reporter.report) }

      it "includes summary" do
        expect(result["summary"]).to include(
          "total" => 2,
          "warnings" => 1,
          "errors" => 1,
          "files_affected" => 2
        )
      end

      it "includes all issues" do
        expect(result["issues"].size).to eq(2)
      end

      it "includes issue details" do
        issue = result["issues"].first
        expect(issue["detector"]).to eq("loop_association")
        expect(issue["file_path"]).to eq("app/controllers/posts_controller.rb")
        expect(issue["line_number"]).to eq(15)
        expect(issue["message"]).to eq("Potential N+1 query")
        expect(issue["suggestion"]).to eq("Use includes(:author)")
      end
    end

    context "with pretty option" do
      it "outputs formatted JSON when pretty is true" do
        issues = [create_issue]
        reporter = described_class.new(issues, pretty: true)
        output = reporter.report

        expect(output).to include("\n")
        expect(output).to include("  ")
      end

      it "outputs compact JSON when pretty is false" do
        issues = [create_issue]
        reporter = described_class.new(issues, pretty: false)
        output = reporter.report

        expect(output).not_to include("\n")
      end
    end

    context "JSON validity" do
      it "produces valid JSON" do
        issues = [create_issue, create_issue(severity: :error)]
        reporter = described_class.new(issues)

        expect { JSON.parse(reporter.report) }.not_to raise_error
      end
    end
  end
end
