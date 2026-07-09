# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::PluckToArray do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :pluck_to_array" do
      expect(described_class.detector_name).to eq(:pluck_to_array)
    end
  end

  describe "#detect" do
    def parse(source)
      EagerEye::SourceParser.parse(source)
    end

    context "when pluck result is used in where" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.pluck(:id)
          Post.where(user_id: user_ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("pluck")
        expect(issues.first.suggestion).to include(".select(:id)")
      end
    end

    context "when .ids is used" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.ids
          Post.where(user_id: user_ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when map(&:id) is used" do
      let(:code) do
        <<~RUBY
          user_ids = users.map(&:id)
          Post.where(user_id: user_ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when collect(&:id) is used" do
      let(:code) do
        <<~RUBY
          ids = records.collect(&:id)
          Item.where(record_id: ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when map(&:to_i) is used" do
      let(:code) do
        <<~RUBY
          ids = strings.map(&:to_i)
          Item.where(id: ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when select subquery is used correctly" do
      let(:code) do
        <<~RUBY
          Post.where(user_id: User.active.select(:id))
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when pluck is used for non-where purposes" do
      let(:code) do
        <<~RUBY
          emails = User.active.pluck(:email)
          send_newsletter(emails)
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when pluck variable is not used in where" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.pluck(:id)
          process_ids(user_ids)
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when different variable is used in where" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.pluck(:id)
          other_ids = [1, 2, 3]
          Post.where(user_id: other_ids)
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with nil AST" do
      it "returns empty array" do
        issues = detector.detect(nil, "test.rb")

        expect(issues).to eq([])
      end
    end

    context "issue attributes" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.pluck(:id)
          Post.where(user_id: user_ids)
        RUBY
      end

      it "sets correct detector name" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.first.detector).to eq(:pluck_to_array)
      end

      it "sets correct file_path" do
        ast = parse(code)
        issues = detector.detect(ast, "app/services/post_service.rb")

        expect(issues.first.file_path).to eq("app/services/post_service.rb")
      end

      it "sets correct line_number" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.first.line_number).to eq(2)
      end

      it "includes suggestion about select subquery" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.first.suggestion).to include("select")
      end
    end

    context "with critical .all.pluck pattern" do
      let(:code) do
        <<~RUBY
          Post.where(user_id: User.all.pluck(:id))
        RUBY
      end

      it "detects critical issue with error severity" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.severity).to eq(:error)
        expect(issues.first.message).to include(".all.pluck")
      end
    end

    context "with small collection pluck (tags, settings, etc.)" do
      it "lowers severity to info for tags" do
        code = <<~RUBY
          tag_ids = prize.tags.pluck(:id)
          user.user_tags.where(tag_id: tag_ids).destroy_all
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.severity).to eq(:info)
      end

      it "lowers severity to info for settings" do
        code = <<~RUBY
          setting_ids = user.settings.pluck(:id)
          Config.where(setting_id: setting_ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.severity).to eq(:info)
      end

      it "lowers severity to info for roles" do
        code = <<~RUBY
          role_ids = user.roles.pluck(:id)
          Permission.where(role_id: role_ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.severity).to eq(:info)
      end

      it "keeps warning severity for large collections" do
        code = <<~RUBY
          user_ids = company.users.pluck(:id)
          Post.where(user_id: user_ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.severity).to eq(:warning)
      end
    end

    context "with .map(&:id) pattern" do
      it "uses different message for map pattern" do
        code = <<~RUBY
          user_ids = users.map(&:id)
          Post.where(user_id: user_ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("map(&:id)")
        expect(issues.first.message).not_to include("plucked")
      end
    end

    context "when variable is used multiple times" do
      let(:code) do
        <<~RUBY
          ids = ordered_missions.pluck(:id)
          result = Mission.where(id: ids)
          sorted = result.order(Arel.sql('array_position(ARRAY[?], id)', ids))
        RUBY
      end

      it "does not report an issue when variable is used elsewhere" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with Sidekiq source" do
      it "does not flag Sidekiq::Queue map operations" do
        code = <<~RUBY
          job_ids = Sidekiq::Queue.new.map { |job| job.args[0] }
          Integration.where(id: job_ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues).to be_empty
      end

      it "does not flag Sidekiq::ScheduledSet operations" do
        code = <<~RUBY
          ids = Sidekiq::ScheduledSet.new.map(&:jid)
          Job.where(jid: ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with Redis source" do
      it "does not flag Redis smembers result" do
        code = <<~RUBY
          user_ids = redis.smembers("active_users").map(&:to_i)
          User.where(id: user_ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with Hash/Array source" do
      it "does not flag Hash keys/values operations" do
        code = <<~RUBY
          ids = top_senders.map { |u| u[:id] }
          User.where(id: ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with .to_sql usage (UNION pattern)" do
      it "does not flag when variable is used in .to_sql" do
        code = <<~RUBY
          active_ids = Mission.active.pluck(:id)
          mission_sql = FriendshipChallenge.where(mission_id: active_ids).to_sql
          challenge_sql = ChallengeOption.where(mission_id: active_ids).to_sql
          from_sql = "(#\{mission_sql} UNION #\{challenge_sql}) AS combined"
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with non-ActiveRecord where call" do
      it "does not flag Sidekiq.where calls" do
        code = <<~RUBY
          job_ids = jobs.pluck(:id)
          Sidekiq::Queue.where(jid: job_ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with .all preceded by a scoping method" do
      it "does not flag .where(...).all.pluck(:id) as critical 'loads entire table'" do
        code = <<~RUBY
          ids = Foo.where(active: true).all.pluck(:id)
          Bar.where(foo_id: ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        critical = issues.select { |i| i.severity == :error }
        expect(critical).to be_empty
      end

      it "still flags unscoped .all.pluck(:id) as critical" do
        code = <<~RUBY
          ids = Foo.all.pluck(:id)
          Bar.where(foo_id: ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        critical = issues.select { |i| i.severity == :error }
        expect(critical).not_to be_empty
      end

      it "treats .joins(...).all.pluck as scoped" do
        code = <<~RUBY
          ids = Foo.joins(:bar).all.pluck(:id)
          Bar.where(foo_id: ids)
        RUBY
        issues = detector.detect(parse(code), "test.rb")

        critical = issues.select { |i| i.severity == :error }
        expect(critical).to be_empty
      end
    end
  end
end
