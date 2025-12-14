# frozen_string_literal: true

class PostSerializer
  attribute :author_name do
    object.author.name
  end
end
