module Workling
  module Starling
    class Client
      attr_accessor :starling_url
      attr_accessor :connection
      
      def initialize
        config = YAML.load( IO.read(::RAILS_ROOT + "/config/starling.yml") )
        @starling_url = config[::RAILS_ENV]["listens_on"]
        @connection = ::MemCache.new(self.starling_url)
      end
      
      def method_missing(method, *args)
        @connection.send(method, *args)
      end
    end
  end
end