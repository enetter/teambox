class CommentsController < ApplicationController
  before_filter :load_comment, :only => [:edit, :update, :convert, :show, :destroy]
  before_filter :load_target, :only => [:create, :convert]
  before_filter :load_orginal_controller, :only => [:create]
  before_filter :check_timeless, :only => [:edit, :convert]
  before_filter :check_permissions, :only => [:create, :edit, :update, :convert]
  before_filter :set_page_title

  cache_sweeper :task_list_panel_sweeper, :only => [:create]

  def create
    if params.has_key?(:project_id)
      @comment  = @current_project.new_comment(current_user,@target,params[:comment])
      @comments = @current_project.comments
    else
      @comment = current_user.new_comment(current_user,@target,params[:comment])
    end

    if @comment.save
      @comment.save_uploads(params)
    end

    @target = @comment.target

    # Evaluate target
    case @target
    when Conversation
      @conversation = @comment.target
      redirect_path = project_conversation_path(@current_project, @conversation)
    when TaskList
      @task_list = @comment.target
      redirect_path = project_task_list_path(@current_project, @task_list)
    when Task
      @comment.reload unless @comment.new_record?
      @task = @comment.target
      @target = @task
      @task_list = @task.task_list
      @new_comment = @current_project.comments.new
      @new_comment.target = @task
      @new_comment.status = @task.status
      redirect_path = project_task_list_task_path(@current_project, @task_list, @task)
    else
      redirect_path = project_path(@target || @current_project)
    end

    respond_to do |f|
      f.html { redirect_to redirect_path }
      f.m    { redirect_to redirect_path }
      f.js   { fetch_new_comments }
    end
  end

  def show
    respond_to{|f|f.js}
  end

  def edit
    @edit_part = params[:part]
    respond_to{|f|f.js}
  end

  def update
    if @has_permission
      @comment.save_uploads(params) if @comment.update_attributes(params[:comment])
    end
    
    respond_to{|f|f.js}
  end
  
  def convert
    if request.method == :put and @has_permission and @comment.target.class == Project and @target.class == TaskList and !@target.archived
      # Make a new task in the target...
      params = {
        'name' => @comment.body
      }
      @task = @current_project.create_task(current_user,@target,params)
      
      if @task.errors.empty?
        @comment.target = @task
        @comment.save
      end
    end
    
    respond_to do |f|
      f.js {
        render :template => 'comments/update'
      }
    end
  end

  def destroy
    if @comment.can_destroy?(current_user)
      @comment.destroy
      @has_permission = true
    else  
      @has_permission = false
    end
  end

  private

    def load_orginal_controller
      @original_controller = params[:original_controller]
    end

    def load_comment
      @comment = @current_project.comments.find(params[:id])
    end

    def load_target
      if params.has_key?(:project_id)
        @target = assign_project_target
      else
        @target = User.find(params[:user_id])
      end
    end
    
    def check_timeless
      if (action_name == 'edit' && params[:part] == 'task') || action_name == 'convert'
        @checks_time = false
      end
    end
    
    def check_permissions
      # Can they even create comments?
      if @comment.nil?
        unless @current_project.commentable?(current_user)
          respond_to do |f|
            flash[:error] = t('common.not_allowed')
            f.html { redirect_to project_path(@current_project) }
          end
          return false
        end
      end
      
      if @comment
        @has_permission = true
        @checks_time = true if @checks_time.nil?
        
        if action_name == 'destroy'
          return if @comment.can_destroy?(current_user, @checks_time)
        else
          return if @comment.can_edit?(current_user, @checks_time)
        end
        
        # Error update handled in rjs handlers
        @has_permission = false
        return if request.format == :js
        
        # Process of elimination: don't allow this!
        respond_to do |f|
          flash[:error] = t('comments.errors.cannot_update')
          f.html { redirect_to project_path(@comment.project) }
        end
        return false
      end
    end

    def assign_project_target
      if params.has_key?(:task_id)
        t = @current_project.tasks.find(params[:task_id])
        t.previous_status = t.status
        t.previous_assigned_id = t.assigned_id
        t.status = params[:comment][:status]
        if params[:comment][:target_attributes]
          t.assigned_id = params[:comment][:target_attributes][:assigned_id]
        end
        t
      elsif params.has_key?(:task_list_id)
        @current_project.task_lists.find(params[:task_list_id])
      elsif params.has_key?(:conversation_id)
        @current_project.conversations.find(params[:conversation_id])
      else
        @current_project
      end
    end
    
    def fetch_new_comments
      # Fetch new comments
      if params[:last_comment_id]
        @last_id = params[:last_comment_id].to_i
        new_id = @comment.new_record? ? 0 : @comment.id
        @new_comments = @target.comments.find(:all, :conditions => ['comments.id != ? AND comments.id > ?', new_id, @last_id])
        @last_id = @new_comments[0].id unless @new_comments.empty?
      end
    end
end