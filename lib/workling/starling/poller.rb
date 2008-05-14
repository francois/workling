module Workling
  module Starling
    
    class Poller
      
      cattr_accessor :sleep_time
      cattr_accessor :reset_time
      
      @@sleep_time = 2        # Seconds to sleep before looping
      @@reset_time = 30       # Seconds to wait while resetting connection
    
      def initialize(routing)
        @routing = routing
        @workers = ThreadGroup.new
      end

      def logger
        Workling::Base.logger
      end
    
      def listen

        # Allow concurrency for our tasks
        ActiveRecord::Base.allow_concurrency = true

        # Create a thread for each worker.
        Workling::Discovery.discovered.each do |clazz|
          clazz_routing = @routing.build(clazz)
          @workers.add(Thread.new(clazz, clazz_routing) { |c, r| clazz_listen(c, r) })
        end
        
        # Wait for all to complete
        @workers.list.each { |t| t.join }

        # Clean up all the connections. Don't need to do this since we are exiting anyway, but it doesn't
        # hurt to get in the habit.
        ActiveRecord::Base.verify_active_connections!
      end
      
      # gracefully stop processing
      def stop
        @workers.list.each { |w| w[:shutdown] = true }
      end
      
      # Thread procs below --------------------------------------------------
      
      # Listen for one worker class
      def clazz_listen(clazz, clazz_routing)

        # Setup my connection - each thread gets its own connection to starling
        connection = Workling::Starling::Client.new
        
        # Start dispatching those messages
        while (!Thread.current[:shutdown]) do
          begin
            
            # If you don't do anything for a while, mysql will drop you. Make sure it stays around.
            unless ActiveRecord::Base.connection.active?
              unless ActiveRecord::Base.connection.reconnect!
                logger.fatal("FAILED - Database not available")
                break
              end
            end

            # Dispatch and process the messages
            n = dispatch!(connection, clazz, clazz_routing)
            if n > 0
              Thread.pass                   # Give someone else a chance
            else
              sleep(self.class.sleep_time)  # Sleep since there was nothing processed
            end
            
          # If there is a memcache error, hang for a bit to give it a chance to fire up again
          # and reset the connection.
          rescue MemCache::MemCacheError
            sleep(self.class.reset_time)
            connection = Workling::Starling::Client.new
          end
        end
      end
      
      # Dispatcher for one worker class. Will throw MemCacheError if unable to connect.
      # Returns the number of worker methods called
      def dispatch!(connection, clazz, clazz_routing)
        n = 0
        for queue in clazz_routing.keys
          begin
            result = connection.get(queue)
            if result
              # We got a result from the queue - dispatch it
              n += 1
              handler = clazz_routing[queue]
              method_name = clazz_routing.method_name(queue)
              logger.debug("\n*****************\nCalling #{handler.class.to_s}\##{method_name}(#{result.inspect})\n*****************\n")
              handler.send(method_name, result)
            end
          rescue MemCache::MemCacheError => e
            logger.error("FAILED to connect with queue #{ queue }: #{ e } }")
            raise e
          rescue Object => e
            logger.error("FAILED to process queue #{ queue }. #{ clazz_routing[queue] } could not handle invocation of #{ clazz_routing.method_name(queue) } with #{ result.inspect }: #{ e }.\n#{ e.backtrace.join("\n") }")
          end
        end
        
        return n
      end
      
    end
  end
end
