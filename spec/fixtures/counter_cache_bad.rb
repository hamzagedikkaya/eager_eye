# frozen_string_literal: true

class CounterCacheBadController
  def index
    @posts = Post.all
    @posts.each do |post|
      post.comments.count
      post.likes.count
    end
  end

  def show
    @post = Post.find(params[:id])
    @comment_count = @post.comments.count
    @like_count = @post.likes.size
  end

  def popular
    @posts = Post.all.select do |post|
      post.comments.count > 10
    end
  end
end

class PostModel
  def popular?
    comments.count > 100
  end

  def engagement_score
    comments.count + likes.size
  end

  def has_many_comments?
    comments.size >= 50
  end
end

class StatsService
  def calculate_totals(posts)
    posts.sum { |post| post.comments.count }
  end

  def average_comments(posts)
    total = posts.sum { |post| post.comments.size }
    total.to_f / posts.count
  end
end
