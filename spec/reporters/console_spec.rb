# frozen_string_literal: true

RSpec.describe EagerEye::Reporters::Console do
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
      it "returns success message" do
        reporter = described_class.new([], colorize: false)
        output = reporter.report

        expect(output).to include("No issues detected!")
      end
    end

    context "with issues" do
      let(:issues) do
        [
          create_issue(
            file_path: "app/controllers/posts_controller.rb",
            line_number: 15,
            message: "Potential N+1 query: `post.author`",
            suggestion: "Use includes(:author)"
          ),
          create_issue(
            file_path: "app/controllers/posts_controller.rb",
            line_number: 20,
            detector: :missing_counter_cache,
            message: "`.count` called on `comments`"
          ),
          create_issue(
            file_path: "app/serializers/post_serializer.rb",
            line_number: 8,
            detector: :serializer_nesting,
            message: "Nested association in serializer",
            severity: :error
          )
        ]
      end

      let(:reporter) { described_class.new(issues, colorize: false) }
      let(:output) { reporter.report }

      it "includes header" do
        expect(output).to include("EagerEye Analysis Results")
      end

      it "groups issues by file" do
        expect(output).to include("app/controllers/posts_controller.rb")
        expect(output).to include("app/serializers/post_serializer.rb")
      end

      it "shows line numbers" do
        expect(output).to include("Line 15:")
        expect(output).to include("Line 20:")
        expect(output).to include("Line 8:")
      end

      it "shows detector names" do
        expect(output).to include("[LoopAssociation]")
        expect(output).to include("[MissingCounterCache]")
        expect(output).to include("[SerializerNesting]")
      end

      it "shows messages" do
        expect(output).to include("Potential N+1 query: `post.author`")
      end

      it "shows suggestions when present" do
        expect(output).to include("Suggestion:")
        expect(output).to include("Use includes(:author)")
      end

      it "shows summary" do
        expect(output).to include("Total: 3 issues")
        expect(output).to include("2 warnings")
        expect(output).to include("1 error")
      end
    end

    context "with single issue" do
      it "uses singular form in summary" do
        issues = [create_issue]
        reporter = described_class.new(issues, colorize: false)
        output = reporter.report

        expect(output).to include("1 issue")
        expect(output).to include("1 warning")
        expect(output).to include("0 errors")
      end
    end

    context "with colorize option" do
      it "includes ANSI color codes when colorize is true" do
        issues = [create_issue]
        reporter = described_class.new(issues, colorize: true)
        output = reporter.report

        expect(output).to include("\e[")
      end

      it "excludes ANSI color codes when colorize is false" do
        issues = [create_issue]
        reporter = described_class.new(issues, colorize: false)
        output = reporter.report

        expect(output).not_to include("\e[")
      end
    end
  end
end
