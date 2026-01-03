# frozen_string_literal: true

class PostSerializer
  attribute :comments_list do
    object.comments.map(&:body)
  end
end
