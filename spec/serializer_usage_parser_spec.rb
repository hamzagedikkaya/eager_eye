# frozen_string_literal: true

RSpec.describe EagerEye::SerializerUsageParser do
  let(:parser) { described_class.new }

  def parse_files(*sources)
    sources.each { |s| parser.parse_file(Parser::CurrentRuby.parse(s)) }
    parser
  end

  describe "#known_serializer?" do
    it "is true once a render site is seen" do
      parse_files("UserBlueprint.render_as_hash(users)")
      expect(parser.known_serializer?("UserBlueprint")).to be(true)
      expect(parser.known_serializer?("OtherBlueprint")).to be(false)
    end
  end

  describe "#safe_access?" do
    it "is safe when the association is preloaded at the only render site" do
      parse_files(<<~RUBY)
        def index
          users = User.includes(:organization)
          UserBlueprint.render_as_hash(users)
        end
      RUBY
      expect(parser.safe_access?("UserBlueprint", nil, :organization)).to be(true)
    end

    it "is unsafe when a collection site does not preload the association" do
      parse_files(<<~RUBY)
        def index
          UserBlueprint.render_as_hash(User.all)
        end
      RUBY
      expect(parser.safe_access?("UserBlueprint", nil, :organization)).to be(false)
    end

    it "is safe when every site passes a single record" do
      parse_files(<<~RUBY)
        def show
          UserBlueprint.render_as_hash(User.find(id))
        end
      RUBY
      expect(parser.safe_access?("UserBlueprint", nil, :organization)).to be(true)
    end

    it "matches a named view only against sites rendering that view" do
      parse_files(<<~RUBY)
        def index
          UserBlueprint.render_as_hash(User.includes(:org), view: :detail)
          UserBlueprint.render_as_hash(User.all, view: :list)
        end
      RUBY
      expect(parser.safe_access?("UserBlueprint", :detail, :org)).to be(true)
      expect(parser.safe_access?("UserBlueprint", :list, :org)).to be(false)
    end

    it "never concludes safe for an unseen serializer" do
      expect(parser.safe_access?("UnknownBlueprint", nil, :x)).to be(false)
    end

    it "sees through pagination wrappers to the preloaded relation" do
      parse_files(<<~RUBY)
        def index
          records = paginate(Post.includes(:author))
          PostBlueprint.render_as_hash(records)
        end
      RUBY
      expect(parser.safe_access?("PostBlueprint", nil, :author)).to be(true)
    end
  end
end
