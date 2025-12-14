# frozen_string_literal: true

class PostsController
  def index
    @posts = Post.all
    @posts.each do |post|
      post.author.name
      post.comments.count
    end
  end
end
