# load rails
puts "loading rails. imagine something spinning..."
require File.dirname(__FILE__) + '/../../../../config/environment'
require File.dirname(__FILE__) + '/../lib/workling/starling/poller'
require File.dirname(__FILE__) + '/../lib/workling/starling/routing/class_and_method_routing'

ActiveRecord::Base.logger = Workling::Base.logger
ActionController::Base.logger = Workling::Base.logger
RAILS_DEFAULT_LOGGER = Workling::Base.logger

puts "starting Workling::Starling::Poller."
client = Workling::Starling::Poller.new(Workling::Starling::Routing::ClassAndMethodRouting.new)
puts "lean back. somebody is doing your work for you."
client.listen
