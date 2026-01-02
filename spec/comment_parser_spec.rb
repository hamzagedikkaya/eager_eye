# frozen_string_literal: true

RSpec.describe EagerEye::CommentParser do
  describe "#disabled_at?" do
    context "with inline disable" do
      let(:source) do
        <<~RUBY
          user.posts.count  # eager_eye:disable CountInIteration
          user.comments.count
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "disables the specified detector on that line" do
        expect(parser.disabled_at?(1, :count_in_iteration)).to be true
        expect(parser.disabled_at?(2, :count_in_iteration)).to be false
      end
    end

    context "with disable-next-line" do
      let(:source) do
        <<~RUBY
          # eager_eye:disable-next-line LoopAssociation
          @users.each { |u| u.profile }
          @users.each { |u| u.settings }
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "disables only the next line" do
        expect(parser.disabled_at?(2, :loop_association)).to be true
        expect(parser.disabled_at?(3, :loop_association)).to be false
      end
    end

    context "with block disable/enable" do
      let(:source) do
        <<~RUBY
          do_something
          # eager_eye:disable LoopAssociation
          @users.each { |u| u.profile }
          @users.each { |u| u.settings }
          # eager_eye:enable LoopAssociation
          @users.each { |u| u.avatar }
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "disables within the block" do
        expect(parser.disabled_at?(1, :loop_association)).to be false
        expect(parser.disabled_at?(3, :loop_association)).to be true
        expect(parser.disabled_at?(4, :loop_association)).to be true
        expect(parser.disabled_at?(6, :loop_association)).to be false
      end
    end

    context "with file-level disable" do
      let(:source) do
        <<~RUBY
          # eager_eye:disable-file CustomMethodQuery
          class MyClass
            def foo
              @users.each { |u| u.teams.where(active: true) }
            end
          end
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "disables for entire file" do
        expect(parser.disabled_at?(4, :custom_method_query)).to be true
        expect(parser.disabled_at?(4, :loop_association)).to be false
      end
    end

    context "with multiple detectors" do
      let(:source) do
        <<~RUBY
          # eager_eye:disable LoopAssociation, CountInIteration
          @users.each { |u| u.posts.count }
          # eager_eye:enable LoopAssociation, CountInIteration
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "disables all specified detectors" do
        expect(parser.disabled_at?(2, :loop_association)).to be true
        expect(parser.disabled_at?(2, :count_in_iteration)).to be true
      end
    end

    context "with CamelCase detector names" do
      let(:source) do
        <<~RUBY
          user.posts.count  # eager_eye:disable CountInIteration
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "normalizes to snake_case" do
        expect(parser.disabled_at?(1, :count_in_iteration)).to be true
      end
    end

    context "with reason comment" do
      let(:source) do
        <<~RUBY
          user.posts.count  # eager_eye:disable CountInIteration -- using counter_cache
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "ignores the reason part" do
        expect(parser.disabled_at?(1, :count_in_iteration)).to be true
      end
    end

    context "with 'all' keyword" do
      let(:source) do
        <<~RUBY
          # eager_eye:disable all
          @users.each { |u| u.posts.count }
          # eager_eye:enable all
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "disables all detectors" do
        expect(parser.disabled_at?(2, :loop_association)).to be true
        expect(parser.disabled_at?(2, :count_in_iteration)).to be true
        expect(parser.disabled_at?(2, :custom_method_query)).to be true
      end
    end

    context "with file-level 'all' disable" do
      let(:source) do
        <<~RUBY
          # eager_eye:disable-file all
          class MyClass
            def foo
              @users.each { |u| u.posts.count }
            end
          end
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "disables all detectors for entire file" do
        expect(parser.disabled_at?(4, :loop_association)).to be true
        expect(parser.disabled_at?(4, :count_in_iteration)).to be true
      end
    end

    context "with unclosed disable block" do
      let(:source) do
        <<~RUBY
          # eager_eye:disable LoopAssociation
          @users.each { |u| u.profile }
          @users.each { |u| u.settings }
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "extends disable to end of file" do
        expect(parser.disabled_at?(2, :loop_association)).to be true
        expect(parser.disabled_at?(3, :loop_association)).to be true
      end
    end

    context "with file-level disable not in first 5 lines" do
      let(:source) do
        <<~RUBY
          class MyClass
            def foo
              bar
            end
            def baz
              # eager_eye:disable-file CustomMethodQuery
              @users.each { |u| u.teams.where(active: true) }
            end
          end
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "does not disable for entire file" do
        expect(parser.disabled_at?(7, :custom_method_query)).to be false
      end
    end

    context "with snake_case detector names" do
      let(:source) do
        <<~RUBY
          user.posts.count  # eager_eye:disable count_in_iteration
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "accepts snake_case names" do
        expect(parser.disabled_at?(1, :count_in_iteration)).to be true
      end
    end

    context "with mixed detector names in same directive" do
      let(:source) do
        <<~RUBY
          # eager_eye:disable LoopAssociation count_in_iteration
          code
          # eager_eye:enable LoopAssociation count_in_iteration
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "accepts both formats" do
        expect(parser.disabled_at?(2, :loop_association)).to be true
        expect(parser.disabled_at?(2, :count_in_iteration)).to be true
      end
    end

    context "with block-start pattern on its own line" do
      let(:source) do
        <<~RUBY
          # eager_eye:disable-block LoopAssociation
          @users.each { |u| u.profile }
        RUBY
      end
      let(:parser) { described_class.new(source) }

      it "disables lines inside block" do
        expect(parser.disabled_at?(2, :loop_association)).to be true
      end
    end
  end
end
