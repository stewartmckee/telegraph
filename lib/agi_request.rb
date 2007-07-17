# Copyright (c) 2007 Jonathan Palley, Idapted Inc.
# All rights reserved

module Telegraph

 class TelegraphRequest < ActionController::AbstractRequest
    attr_accessor :session_options, :path, :path_parameters, :session, :env, :cookies, :content_type
    attr_accessor :host, :cc, :next_action, :next_controller, :path
    
    def initialize(cc, cgi, query_parameters={}, request_parameters={}, session_opts = ActionController::CgiRequest::DEFAULT_SESSION_OPTIONS)
      @cc                 = cc # Telegraph::CallConnection
      @query_parameters   = query_parameters 
      @request_parameters = request_parameters
      @session_options    = session_opts
      @redirect           = false
      @env                = {}
      @cookies            = {}
      @path_parameters    = {}
      
      #these allow us to do redirects (or psuedo form submits)to other actions since we can't do a HTTP 302
      @next_action             = nil
      @next_controller         = nil
      @redirect_parameters     = nil
      
      
      logger=Telegraph.LOGGER
      
      @cgi = cgi
      @host                    = "agi"
      @request_uri             = "/"
      self.remote_addr         = "0.0.0.0"        
      @env["SERVER_PORT"]      = 84837
      @env['REQUEST_METHOD']   = "POST"
      @path=cc.agi_url
      @session_options['session_id'] = cc.params['session_id']
      
      super()
    end
    def parameters!
      @parameters ||= {}
      controller = @parameters[:controller]
      @parameters = request_parameters.update(query_parameters).update(path_parameters).with_indifferent_access
      @parameters[:controller] ||= controller
    end

    def sound?
      true
    end
    def accepts
  
     [Mime::VOICE]
     # Mime::Type.new('text/vnd.wap.wml')
    end

    def content_type
     @content_type ||= Mime::VOICE
    end

    #copies parameters from the agi request (in the call_connection object)
    #if this is a redirect we add in the redict parameters
    def request_parameters
      @cc.params.dup
    end
    
    def query_parameters
      @redirect_parameters || {}
    end
    

    def create_redirect(args)
      @redirect_parameters = args    
      @next_action=args[:action].to_s
      @next_controller = args[:controller].to_s.camelize + 'Controller' unless args[:controller].nil?
      #reset the parameters to include the original ones from the routing engine
      @path_parameters = {}
      parameters
    end

     def remote_addr=(addr)
      @env['REMOTE_ADDR'] = addr
    end

    def remote_addr
      @env['REMOTE_ADDR']
    end

    def request_uri
      @request_uri || super()
    end

    def path
      @path || super()
    end
   
    def session=(session)
      @session = session
      @session.update
    end
    
    def session  
      unless @session
         if @session_options == false
            @session = Hash.new
        else
          stale_session_check! do
            
            if session_options_with_string_keys['new_session'] == true
              @session = new_session
            else
              @session = CGI::Session.new(@cgi, session_options_with_string_keys)
            end
            session['__valid_session']
          end
        end
      end
      @session
    end

    def reset_session
      @session.delete if CGI::Session === @session
      @session = new_session
    end

    def method_missing(method_id, *arguments)
      @cgi.send(method_id, *arguments) rescue super
    end
    
    def logger=(logger)
      @logger=logger
    end
    
    def logger
      @logger
    end
    
    private
      # Delete an old session if it exists then create a new one.
      def new_session
        if @session_options == false
          Hash.new
        else
          CGI::Session.new(@cgi, session_options_with_string_keys.merge("new_session" => false)).delete rescue nil
          CGI::Session.new(@cgi, session_options_with_string_keys.merge("new_session" => true))
        end
      end
          def stale_session_check!
        yield
      rescue ArgumentError => argument_error
        if argument_error.message =~ %r{undefined class/module (\w+)}
          begin
            Module.const_missing($1)
          rescue LoadError, NameError => const_error
            raise ActionController::SessionRestoreError, <<end_msg
Session contains objects whose class definition isn\'t available.
Remember to require the classes for all objects kept in the session.
(Original exception: #{const_error.message} [#{const_error.class}])
end_msg
          end

          retry
        else
          raise
        end
      end

      def session_options_with_string_keys
        @session_options_with_string_keys ||= ActionController::CgiRequest::DEFAULT_SESSION_OPTIONS.merge(@session_options).inject({}) { |options, (k,v)| options[k.to_s] = v; options }
      end
  end
  
end
