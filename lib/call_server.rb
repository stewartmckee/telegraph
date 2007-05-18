# Copyright (c) 2005, SNAPVINE LLC (www.snapvine.com)
# All rights reserved.

# Portions Copyright (c) 2007 Jonathan Palley, Idapted Inc.
# All rights reserved


require 'webrick/config'
require 'webrick/log'
require 'webrick/server'
require 'thread'

module Telegraph

  @global_config = nil

  def self.LOGGER
    @logger ||= WEBrick::Log::new
    @logger
  end

  def self.LOGGER=(logger)
    @logger = logger
  end

  def self.global_config
    # This assignment will make a dup
    @global_config ||= Telegraph::Config::Globals
    @global_config
  end

  def self.global_config=(new_config)
    @global_config = new_config.dup()
  end
  

  class CallServer
    @incomingcallsocket = nil

    # 4573 = asterisk AGI
    # Telegraph::CallHandler - default handler
    
    def initialize(config = {}, default = Telegraph::Config::Standard)
      @config = default.dup.update(config)
      @config[:Logger] ||= WEBrick::Log::new
      @config[:ParentStopCallback] = @config[:StopCallback] if @config[:StopCallback]
      @config[:StopCallback] = method('shutdown_done')
      @config[:BindAddress]='localhost'
     # @config[:Port]=nil
      Telegraph.LOGGER = @config[:Logger]
      ActionController::Base.logger = Telegraph.LOGGER
      
    end

    def run
      @mutex = Mutex.new
      @signal = ConditionVariable.new
      @running = true

      if (@incomingcallsocket == nil)
        begin
          # code to executed in a thread
          Telegraph.LOGGER.info("#{self.class.name}: default-handler=#{@config[:DefaultHandler].to_s} port=#{@config[:Port]}")
         
          @incomingcallsocket = WEBrick::GenericServer.new( @config )
   
          @incomingcallsocket.start{ |sock|
            ENV['REQUEST_METHOD'] = "post"
            cgi=CGI.new
            cc = CallConnection.new(sock, cgi)
       
            # the default call handler comes from config environment.rb
            prepare_application
            
            ActionController::Routing::Routes.recognize(cc.request)

            # bit of a hack.  Need to setup next_action/next_controller
            cc.request.next_action = cc.request.parameters['action']
            cc.request.next_controller = cc.request.parameters['controller'].camelize + 'Controller'
            #Loops until we are done executing all the actions for this call
            while cc.request.next_action !=nil do
              path_params={:action=>cc.request.next_action, :controller=>cc.request.next_controller}
              cc.request.path_parameters = path_params
              #cc.request.params['action'] = next_action
              cc.request.next_action=nil
              response=ActionController::CgiResponse.new(cgi)
              cc.request.next_controller.constantize.new.process(cc.request,response)
            end
          }
          Telegraph.LOGGER.info("#{self.class.name}: server shutdown port=#{@config[:Port]}")
          
        rescue StandardError => err
          Telegraph.LOGGER.info('There is an error here, but we got it')
          Telegraph.LOGGER.error("#{err.message}")
          Telegraph.LOGGER.error(err.backtrace.join("\n"))
         rescue
           puts "error"
           Telegraph.LOGGER.info('error!')
        end
        
      end
    end    

    #loads Telegraphls route/application.  Not sure if this works?s
    def prepare_application
        ActionController::Routing::Routes.reload if Dependencies.load?
        #prepare_breakpoint
        require_dependency('application.rb') unless Object.const_defined?(:ApplicationController)
        ActiveRecord::Base.verify_active_connections!
      end
      
      
    def shutdown
      @incomingcallsocket.shutdown
    end

    def shutdown_done
      Telegraph.LOGGER.debug("#{self.class.name}: Shutdown complete")

      @config[:ParentStopCallback].call if @config[:ParentStopCallback]
      @mutex.synchronize do
        @running = false
        @signal.signal
      end
    end
    
    def join
      @mutex.synchronize do
        if @running
          @signal.wait(@mutex)
        end
      end      
    end      
  end
end
