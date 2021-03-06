require 'sinatra/base'
require 'sinatra/reloader'

require 'omniauth'
require 'mongo_mapper'
require 'haml'

require_relative 'models'

module Sinatra
  module UserHelper

    # This incredibly useful helper gives us the currently logged in user. We
    # keep track of that by just setting a session variable with their id. If it
    # doesn't exist, we just want to return nil.
    def current_user
      return User.first(:id => session[:user_id]) if session[:user_id]
      nil
    end

    # This very simple method checks if we've got a logged in user. That's pretty
    # easy: just check our current_user.
    def logged_in?
      current_user != nil
    end

    # Our `admin_only!` helper will only let admin users visit the page. If
    # they're not an admin, we redirect them to either / or the page that we
    # specified when we called it.
    def admin_only!(opts = {:return => "/"})
      unless logged_in? && current_user.admin?
        flash[:error] = "Sorry, buddy"
        redirect opts[:return]
      end
    end

    # Similar to `admin_only!`, `require_login!` only lets logged in users access
    # a particular page, and redirects them if they're not.
    def require_login!(opts = {:return => "/"})
      unless logged_in?
        flash[:error] = "Sorry, buddy"
        redirect opts[:return]
      end
    end
  end

  helpers UserHelper
end


class Rstatus < Sinatra::Base
  use Rack::Session::Cookie, :secret => ENV['COOKIE_SECRET']
  set :root, File.dirname(__FILE__)

  require 'rack-flash'
  use Rack::Flash

  configure :development do
    register Sinatra::Reloader
  end

  configure do
    enable :sessions

    if ENV['MONGOHQ_URL']
      MongoMapper.config = {ENV['RACK_ENV'] => {'uri' => ENV['MONGOHQ_URL']}}
      MongoMapper.database = ENV['MONGOHQ_DATABASE']
      MongoMapper.connect("production")
    else
      MongoMapper.connection = Mongo::Connection.new('localhost')
      MongoMapper.database = "rstatus-#{settings.environment}"
    end
  end

  helpers Sinatra::UserHelper

  use OmniAuth::Builder do
    cfg = YAML.load_file("config.yml")[ENV['RACK_ENV']]
    provider :twitter, cfg["CONSUMER_KEY"], cfg["CONSUMER_SECRET"]
  end

 get '/' do
   if logged_in?
     haml :dashboard
   else
     haml :index
   end
  end

  get '/auth/twitter/callback' do

    auth = request.env['omniauth.auth']
    unless @auth = Authorization.find_from_hash(auth)
      @auth = Authorization.create_from_hash(auth, current_user)
    end
    session[:user_id] = @auth.user.id

    flash[:notice] = "You're now logged in."
    redirect '/'
  end

  get "/logout" do
    session[:user_id] = nil
    flash[:notice] = "You've been logged out."
    redirect '/'
  end

  get "/users/:slug" do
    @user = User.first :username => params[:slug]
    haml :"users/show"
  end

  # users can follow each other, and this route takes care of it!
  get '/users/:name/follow' do
    require_login! :return => "/users/#{params[:name]}/follow"

    @user = User.first(:username => params[:name])

    #make sure we're not following them already
    if current_user.following? @user
      flash[:notice] = "You're already following #{params[:name]}."
      redirect "/users/#{current_user.username}"
      return
    end

    # then follow them!
    current_user.follow! @user

    flash[:notice] = "Now following #{params[:name]}."
    redirect "/users/#{current_user.username}"
  end

  #this lets you unfollow a user
  get '/users/:name/unfollow' do
    require_login! :return => "/users/#{params[:name]}/unfollow"

    @user = User.first(:username => params[:name])

    #make sure we're following them already
    unless current_user.following? @user
      flash[:notice] = "You're already not following #{params[:name]}."
      redirect "/users/#{current_user.username}"
      return
    end

    #unfollow them!
    current_user.unfollow! @user

    flash[:notice] = "No longer following #{params[:name]}."
    redirect "/users/#{current_user.username}"
  end

  # this lets us see followers.
  get '/users/:name/followers' do
    @user = User.first(:username => params[:name])

    haml :"users/followers"
  end

  # This lets us see who is following.
  get '/users/:name/following' do
    @user = User.first(:username => params[:name])

    haml :"users/following"
  end

end

