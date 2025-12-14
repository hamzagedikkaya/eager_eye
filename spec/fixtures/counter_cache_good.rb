# frozen_string_literal: true

class CounterCacheGoodController
  def index
    # Using counter_cache column directly
    @posts = Post.all
    @posts.each do |post|
      post.comments_count
      post.likes_count
    end
  end

  def show
    # No count/size calls on associations
    @post = Post.find(params[:id])
    @comment_count = @post.comments_count
    @like_count = @post.likes_count
  end

  def stats
    # Using database aggregation instead
    @total_comments = Comment.count
    @posts_with_comments = Post.where("comments_count > 0").count
  end
end

class GoodPostModel
  def popular?
    comments_count > 100
  end

  def engagement_score
    comments_count + likes_count
  end
end

class SafeService
  def count_items(items)
    # count on array is fine
    items.count
  end

  def size_check(array)
    # size on array is fine
    array.size
  end

  def length_check(string)
    # length on string is fine
    string.length
  end
end
