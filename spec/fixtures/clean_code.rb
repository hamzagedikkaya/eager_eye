# frozen_string_literal: true

class CleanController
  def index
    @posts = Post.includes(:author, :comments).all
    @posts.each do |post|
      post.title
      post.body
    end
  end
end
