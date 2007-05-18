# Portions Copyright (c) 2007 Jonathan Palley, Idapted Inc.
# All rights reserved

module Telegraph
  class AsteriskUnavailableError < StandardError; end
  require 'drb'
   require 'monitor'
   require 'socket'
   require 'timeout'
   require 'digest/md5'
require 'webrick'
    
  AMI_STATUS_CODE_STRINGS = {
    -1 => "Extension Not Found",
     0 => "Idle",
     1 => "In Use",
     4 => "Unavailable",
     8 => "Ringing"
  }

  class AMIClient
    include DRbUndumped
    if ENV["RAILS_ENV"] #Load handlers if in rails environment
     Dir["#{RAILS_ROOT}/app/ami_logic/*.rb"].each do |t|
       require t
      end
     end
    # Number of seconds before an action will timeout. Default is 10.
    attr_writer :timeout
    attr_writer :event_cache
    

    
    def initialize(client)
      if client.kind_of?(String)
        @client = DRbObject.new(nil, client)
      else
        @client = client
      end
    end
    
    #Initiates new server at same time as client and connects
    def self.new_with_server(options={})
       server = Telegraph::AMIServer.new(options)
       server.connect
       
       return Telegraph::AMIClient.new(server)
    end
    
    #
    def watch_for_events
   #   ast_read = Thread.new do
  #      Thread.current.abort_on_exception=true
  #      begin
          while events = @client.get_next_events
            for event in events
              @mysql_reconnect = false
              begin
                ami_handler=AmiLogic.new(event)
                ami_handler.send(event[:event].underscore.to_sym) if ami_handler.respond_to?(event[:event].underscore.to_sym)
              rescue Exception => e
                #If we loss mysql connectivity, for some reason it dies
                if e.message =~ /MySQL server has gone away/ and not @mysql_reconnect then
                  @mysql_reconnect = true
                  puts 'RECONNECTING============='
                  ActiveRecord::Base.connection.reconnect!
                  retry
                else
                  puts 'Error:'
                  puts e.message
                  puts e.backtrace.join("\n")
                end
              end 
            end
          end
  #      end
  #    end
    end
    
    # This action will request Asterisk to hangup a given channel after the
    # specified number of seconds, thereby effectively ending the active call. 
    #
    # If the channel is linked with another channel (an active connected call
    # is in progress), the other channel will continue it's path through the
    # dialplan (if any further steps remains).
    #
    # ==== Parameters
    # * <tt>channel</tt> -- Which channel to hangup, e.g. <tt>SIP/123-1c20</tt>
    # * <tt>timeout</tt> -- The number of seconds until the channel should hangup
    #
    # ==== Example
    #     absolute_timeout('SIP/123-1c20', 10)
    #
    # Returns a AsteriskResponse
    def absolute_timeout(channel, timeout)
      do_action({:action => :absolutetimeout, :channel => channel, :timeout => timeout})
    end

    # This action will list Agent(s) and their status
    #
    # Returns an array of Agent(s)
    #--
    # Response: Success
    # Message: Agents will follow
    # 
    # Event: AgentsComplete    
    def agents
      do_action(:action => :agents)
    end

    # Changes the file name of a recording occuring on a channel 
    # 
    # ==== Parameters
    # * <tt>channel</tt> -- Which channel to change, e.g. <tt>SIP/x7065558529-1c20</tt>
    # * <tt>file</tt> -- The file name to change to, e.g. <tt>20050103-140105_cc51</tt>
    #
    # Returns a AsteriskResponse
    def change_monitor(channel, file)
      do_action(:action => :changemonitor, :channel => channel, :file => file)
    end

    # This action will run an Asterisk CLI command (not an application command)
    #
    # ==== Options
    # * <tt>:command</tt> -- The command to send, e.g. <tt>show channels</tt>
    #
    # ==== Example
    #    cli_command("show channels")
    #
    # Returns a AsteriskResponse. Check AsteriskResponse#results for results if the action was a success. 
    #--
    # Response: Follows 
    # Channel (Context Extension Pri ) State Appl. Data 
    # 0 active channel(s) 
    # --END COMMAND-- 
    #
    def cli_command(command)
      do_action({:action => :command, :command => command})
    end

    # Get an Asterisk Database entry
    #
    # ==== Parameters
    # * <tt>family</tt> -- the family to use, think category
    # * <tt>key</tt> -- the key
    #
    # ==== Example
    # Here, +test+ is the +family+ in the Asterisk's database. The +key+ in the database is 
    # the word +data+.
    #
    #     db_get('test', 'data')
    #
    # Returns a AsteriskResponse. Check AsteriskResponse#results for results if the action was a success. 
    #--
    # Response: Error 
    # Message: Database entry not found 
    # 
    # or 
    # 
    # Response: Success 
    # Message: Result will follow 
    # 
    # Event: DBGetResponse 
    # Family: <family> 
    # Key: <key> 
    # Val: <value>
    #
    def db_get(family, key)
      do_action({:action => :dbget, :family => family, :key => key})
    end

    # Store an Asterisk Database entry.
    #
    # ==== Paremeters
    # * <tt>family</tt> -- the family to use, think category
    # * <tt>key</tt> -- the key
    # * <tt>value</tt> -- the value to store
    #
    # ==== Example
    # Here, +test+ is the +family+ in the Asterisk's database. The +key+ in the database will 
    # be the word +data+ and the +value+ will be the number 122.
    #
    #     db_put('test', 'data', 122)
    #
    # Returns a AsteriskResponse
    #--
    # Response: Success 
    # Message: Updated database successfully
    #
    def db_put(family, key, value)
      do_action({:action => :dbput, :family => family, :key => key, :value => value})
    end

    # Check the state of an extension
    #
    # ==== Parameters
    # * <tt>context</tt> -- the context that contains the extension
    # * <tt>extension</tt> -- the name of the extension
    #
    # ==== Example
    #    extension_state('internal', 204)
    #
    # Returns a AsteriskResponse. Check AsteriskResponse#results for results if the action was a success.  Use 
    # <tt>RAI::AMI_STATUS_CODE_STRINGS</tt> to get the string value for the extension status.)
    # 
    #--
    # Response: Success 
    # ActionID: 1 
    # Message: Extension Status 
    # Exten: idonno 
    # Context: default 
    # Hint: 
    # Status: -1 
    # 
    # 
    # Status codes: 
    # -1 = Extension not found 
    # 0 = Idle 
    # 1 = In Use 
    # 4 = Unavailable 
    # 8 = Ringing
    def extension_state(context, extension)
      do_action({:action => :extensionstate, :context => context, :exten => extension})
    end
    
    # Check the state of an extension
    #
    # ==== Options
    # * <tt>:channel</tt> -- the context that contains the extension
    # * <tt>:variable</tt> -- the name of the extension
    #
    # ==== Example
    #    get_variable(:channel => 'internal', :variable => 204)
    def get_variable(options = {})
      options[:action] = :get_var
      do_action(options)
    end
    
    # Action: Hangup  
    # Parameters: Channel  
    # 
    # SEND: 
    # ACTION: Hangup 
    # Channel: SIP/x7065558529-99a0 
    # 
    # RECEIVE: 
    # 
    # Response: Success 
    # Message: Channel Hungup 
    def hangup(channel)
      do_action({:action => :hangup, :channel => channel})
    end

    # Action: IAXPeers 
    # 
    # 
    # Example (Show the IAX Peers on the server and their status) 
    # Name/Username    Host                 Mask             Port      Status
    # TESTast7         (Unspecified)   (D)  255.255.255.255  0         UNKNOWN
    # TESTast6         10.10.10.16     (D)  255.255.255.255  4569      OK (1 ms)
    # TESTast4         10.10.10.14     (D)  255.255.255.255  4569      OK (3 ms)
    # TESTast2         10.10.10.12     (D)  255.255.255.255  4569      OK (1 ms)
    # TESTast1         10.10.10.11     (D)  255.255.255.255  4569      OK (1 ms)
    def iax_peers
      do_action({:action => :iaxpeers})
    end
    
    # Action: Monitor 
    # Parameters: Channel, File, Format, Mix 
    # 
    # Example Via Asterisk 1.0.9 
    # SEND: 
    # ACTION: Monitor 
    # Channel: SIP/x7062618529-643d 
    # File: channelsavefile 
    # Mix: 1 
    # 
    # 
    # RECEIVE: 
    # Response: Success 
    # Message: Started monitoring channel 
    # 
    # 
    # RECIEVE ON FAIL: 
    # Response: Error 
    # Message: No such channel 
    def monitor(options)
      options[:action] = :monitor
      do_action(options)
    end
    
    # Action: MailboxStatus 
    # Synopsis: Check Mailbox 
    # Privilege: call,all 
    # Description: Checks a voicemail account for status. 
    # Variables: (Names marked with * are required) 
    #        *Mailbox: Full mailbox ID <mailbox>@<vm-context> 
    #
    # Returns number of messages. 
    #        Message: Mailbox Status 
    #        Mailbox: <mailboxid> 
    #        Waiting: <count> 
    # 
    # Example: 
    # 
    # Action: MailboxStatus 
    # Mailbox: 7000@default
    def mailbox_status(mailbox)
      do_action({:action => :mailboxstatus, :mailbox => mailbox})
    end

    # The "QueueStatus" request returns statistical information about calls
    # delivered to the existing queues, as well as the corresponding service level. 
    # 
    # Parameters: ActionID 
    # 
    # =>Request 
    # Action: QueueStatus 
    # 
    # => Return value example 
    # Message: Queue status will follow 
    # 
    # Event: QueueParams 
    # Queue: default 
    # Max: 0 
    # Calls: 0 
    # Holdtime: 0 
    # Completed: 0 
    # Abandoned: 0 
    # ServiceLevel: 0 
    # ServicelevelPerf: 0.0 
    def queue_status
      do_action({:action => :queuestatus})
    end

    def mailbox_count(mailbox)
      do_action({:action => :mailboxcount})
    end

    # options is a hash with the following keys.  keys that are nil will not be passed to asterisk.
    # * :channel
    # * :context
    # * :extension
    # * :priority
    # * :timeout
    # * :caller_id
    # * :variable
    # * :account
    # * :application
    # * :data
    # * :asynchronous (boolean)
    # If Async has a value, the method will wait until the call is hungup or fails. On hangup,
    # Asterisk will response with Hangup event, and on failure it will respond with an OriginateFailed event.
    # If Async is nil, the method will return immediately and the associated events can be obtained by calling
    # find_events() or get_events().
    def originate(options = {})
      options[:action] = :originate
      do_action(options)
    end

    def parked_calls
      do_action({:action => :parked_calls})
    end

    def ping
      do_action({:action => :ping})
    end

    # options are a hash with the following keys.  keys that are nil will not be passed to asterisk.
    # * :channel
    # * :extra_channel
    # * :context
    # * :extension
    # * :priority
    def redirect(channel, context, extension, options = {})
      options[:action] = :redirect
      options[:channel] = channel
      options[:context] = context
      options[:exten] = extension
      options[:priority] ||= 1
      do_action(options)
    end

    def set_variable(channel, variable, value)
      do_action({:action => :setvar, :channel => channel, :variable => variable, :value => value})
    end
    
    # Detailed information about a particular peer.
    # XXX: get unknown action on asterisk 1.2.12.1
    def sip_show_peer(peer)
      puts 'sip show peer'
      do_action({:action => :sipshowpeer, :peer => peer})
    end
    
    def sip_peers
      do_action({:action => :sippeers})
    end

    def status(channel)
      do_action({:action => :status, :channel => channel})
    end

    def stop_monitor(channel)
      do_action({:action => :stopmonitor, :channel => channel})
    end
    
    
    def do_action(options={})
      @client.do_action(options)
    end
    
  end

  
  class AMIServer
    @@last_connect_attempt = nil
    CRLF = "\r\n"
    
    attr_writer :event_cache
    
    include DRbUndumped
    
    # Connect to the AMI server.  This must be done before using any other commands, or you will get
    # a failed AsteriskResponse.
    #
    # Returns a AsteriskResponse
    def connect
      puts 'Connecting to Asterisk...'
      begin
        @socket = TCPSocket.new(@host, @port)
        challenge_login = {:action =>'challenge', :authtype => 'md5'}
        write_action(challenge_login)
        
       challenge_response = get_hash_response
        login = {:action => "login",
                    :username => @username,
                    :authtype => 'MD5',
                    :key => Digest::MD5.hexdigest(challenge_response['Challenge'] + @secret),
                    :events => "On"}
                    
          write_action(login)
          login_response = get_hash_response
          main_loop
      rescue Exception => e
        puts('Error:')
        puts("#{e.message}")
        puts(e.backtrace.join("\n"))
      end
    end
    
    def get_hash_response
       response = {}
        Timeout.timeout(@timeout) do
          while line = read_line do
            response = parseline(line, response)
            return response if (line==CRLF and response['Response'] == 'Success')
          end
        end
    end
    def parseline(line, hsh)
      return hsh unless line.include?(':')
      if line =~/(^[\w\s\/-]*:[\s]*)(.*\r\n$)/
        key = $1
        value = $2
        key = key.gsub(/[\s:]*/,'')
        value = value.gsub(/\r\n/,'')
      else
        key = "UNKNOWN"
        value = "UNKNOWN"
      end
      hsh[key] = value
      return hsh
    end
    # Explicitly close the connection to the AMI server (socket is closed). 
    # You will need to call Client#connect before using  any other actions after disconnecting.
    def disconnect
      begin
        unless @socket.nil?
          @socket.close
          AsteriskResponse.new("Client disconnected.", true)
        else
          AsteriskResponse.new("No connection to server.")
        end
      rescue Exception => e
        AsteriskResponse.new(e.message)
      end
    end
    
    def reconnect
      return false if @@last_connect_attempt and Time.now - @@last_connect_attempt < 60
      @@last_connect_attempt = Time.now
      puts 'reconnect'
      disconnect
      connect
    end

    def initialize(options={})
      @timeout = options[:timeout] || 10
      @username = options[:username] || 'asterisk'
      @secret = options[:secret] || 'secret'
      @host = options[:host] || 'localhost'
      @port = options[:port] || 5038
      @event_cache = options['event_cache'] || 100
      
      @event_cache = 1
      @socketlock = nil
      @socketlock.extend(MonitorMixin)
      
      @response_cache = Array[]
      @response_cache.extend(MonitorMixin)
      @response_cache_pending = @response_cache.new_cond
      
      @event_cache = Array[]
      @event_cache.extend(MonitorMixin)
      @event_cache_pending = @event_cache.new_cond
    end
        
    def get_next_events()
      found = []
      @event_cache.synchronize do
        if @event_cache.empty?
          @event_cache_pending.wait_while{@event_cache.empty?}
          @event_cache.clone.each do |e|
            found.push(e)
          end
          @event_cache.clear
          return found
        else
          @event_cache.clone.each do |e|
            found.push(e)
          end
          @event_cache.clear
          return found
        end
      end
    end 
    def do_action(options={})
      action_id = Time.now.to_f
      response = AsteriskResponse.new(action_id)
      begin
        @response_cache.synchronize do
          @response_cache << response
        end
        
        write_action(options, response.action_id)
      
        begin
          Timeout.timeout(@timeout) do
              @response_cache.synchronize do
  #              @response_cache_pending.wait_while{
  #                re = @response_cache.detect{|r| r.action_id == action_id}
  #                re and re.complete
  #                }
                  @response_cache_pending.wait_while{!response.complete}
                return response
              end
          end
        rescue Timeout::Error => e
          response.message = "Action timed out after #{@timeout} seconds."
          return @response_cache.delete(response)
        end
      rescue IOError => e
        response.message = "No connection to server."
        return @response_cache.delete(response)
      rescue Errno::EPIPE
        puts 'pipe error'
        if reconnect
          
          do_action(options)
        else
          AsteriskResponse.new("No connection to the Asterisk server.")
        end
      end
    end
    
    def write_action(hsh={}, action_id=nil, terminate=true)
     action_id=Time.now.to_f unless action_id
      # making sure the action gets sent first, can't rely on sorting
      action = hsh.delete(:action).to_s.gsub(/_/,'').downcase
      write_line("Action: #{action}")
      if authtype = hsh.delete(:authtype)
        write_line("authtype: #{authtype}")
      end
      write_line("actionid: #{action_id}")
      # write the rest of the options to the socket        
      hsh.each{|key, value| write_line("#{key.to_s}: #{value}")}
      write_line if terminate
    end
    
    def write_line(line="")
      unless @socket.nil? 
        @socket.write(line + CRLF)
      else
        raise IOError
      end
    end
    
    def read_line
      unless @socket.nil?
        @socket.gets
        a = $_
        $_
      else
        raise IOError
      end
    end
    
    
    def main_loop
      ast_read = Thread.new do
       # Thread.current.abort_on_exception=true
        begin
          linecount = 0
          loop do
              #new lines come in...read them.
               while line=read_line do

                #we have a response...
                if line =~ /^Event:\s(.*)#{CRLF}/
                    complete = false
                    action_id=nil
                    event = Hash.new
                    event[:event] = $1
                    while line=read_line do

                      if event[:event].downcase =~ /complete/
                        complete = true
                      end
                      if line =~ /^(\w+):\s(.*)#{CRLF}/
                        if $1=="ActionID"
                          action_id= $2
                        else
                          event[underscorize($1).to_sym] = $2
                        end
                      elsif line == CRLF
                        if action_id
                          @response_cache.synchronize do
                            response = @response_cache.detect{|r| r.action_id.to_s == action_id.to_s}
                            if response
                              response.events << event
                              response.complete = complete
                            end
                            @response_cache_pending.signal if response && response.complete
                          end
                        else
                          @event_cache.synchronize do
                            @event_cache << event
                              @event_cache_pending.signal
                          end
                        
                        end
                         break
                      end
                    end
                elsif line =~ /^Response:\s(.*)#{CRLF}/ || line =~ /^ActionID:\s(.*)#{CRLF}/
                  if line =~ /^ActionID:\s(.*)#{CRLF}/
                    action_id = $1
                    line = read_line
                    line =~ /^Response:\s(.*)#{CRLF}/
                  end
                  #response ||= AsteriskResponse.new
                  success = complete = ($1 == 'Success' or $1 == 'Pong') ? true : false
                  message = $1 if $1 == 'Pong' 
                  #For cli_command - unformated response
                  if $1 == 'Follows'
                      results = ''
                      while line = read_line
                        if line =~ /^ActionID:\s(.*)#{CRLF}/
                          action_id = $1
                        elsif line =~ /^(.+[^\r])\n/
                          results << $1.squeeze(' ') + "\n"
                        elsif line == "\r\n" or line == "\n"
                          @response_cache.synchronize do
                            response = @response_cache.detect{|r| 
                              r.action_id.to_s == action_id.to_s}
                            if response
                              response.results = results
                              response.complete = true
                              @response_cache_pending.signal if response.complete
                            end
                          end
                          break
                        end
                      end
    
                  
                  else
                  
                  attributes={}
                  complete = true
                  while line = read_line do
                    if line =~ /^ActionID:\s(.*)#{CRLF}/
                      action_id = $1 
                    elsif line =~ /^Message:\s(.*)#{CRLF}/
                      message = $1
                      if message =~ /^.*will follow$/
                        #response.message = message
                        complete=false
                      else
                        complete=true
                      end
                    elsif line =~  /^([\w|-]+):\s(.*)#{CRLF}/
                      at = $1
                      val = $2
                      at = at.downcase.gsub("-", "_")
                      attributes[at.to_sym] = val
                    elsif line == CRLF
                      #this is it.  Find response and save it
                      @response_cache.synchronize do
                        response = @response_cache.detect{|r| 
                          r.action_id.to_s == action_id.to_s}
                        if response
                          response.message=message
                          response.attributes = attributes
                          response.complete=complete
                          response.success=success
                          @response_cache_pending.signal if response.complete
                        end
     
                     
                     end
                     break
                      
                    end
                  end
                  
                  #we are done reading this action...let's get out
                end
                  break
                end
                
                
              end
          end
        rescue Errno::EPIPE
          puts "Pipe Error"
        end
      end
    end
    
    protected
    def underscorize(camel_cased_word)
      camel_cased_word.to_s.gsub(/::/, '/').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        tr("-", "_").downcase
    end
  end
  
  class AsteriskResponse
    attr_writer :success, :message, :results, :attributes, :complete
    attr_reader :action_id
    
    def initialize(action_id=nil, message=nil, success=false, results=[])
      @action_id=action_id
      @success = success
      @message = message
      @results = results
      @events = Array.new
      @attributes = Hash.new
      @complete=false
    end
    
    # Returns +true+ if the response was successful, otherwise +false+
    def success?
      @success
    end
    
    #  Returns descriptive text about the response
    def message
      @message
    end
    
    def complete
      @complete
    end
    # Holds the attributes for a AsteriskResponse.  If you know the name of the attribute
    # you can access it simply by using its name.
    #
    # ==== Example
    #  # response = AsteriskResponse.new
    #  => #<RAI::AsteriskResponse:0x49ade0 @results=[], @message=nil, @success=true, @attributes={}>
    #  # response.attributes[:foo] = "bar"
    #  => "bar"
    #  # response
    #  => #<RAI::AsteriskResponse:0x49ade0 @results=[], @message=nil, @success=true, @attributes={:foo=>"bar"}>
    #  # response.foo
    #  => "bar"
    #--
    # XXX: I though about using OpenStruct for this, but it would be less obvious than a hash with
    # named attributes.  -schulty
    def attributes
      @attributes
    end
    
    def events
      @events
    end
    
    # Returns any results from the command
    def results
      @results
    end
    
    protected
    # lets you do nifty things like AsteriskResponse#foo assuming that there is an attribute named 'foo'
    def method_missing(symbol, *args)
      @attributes[symbol]
    end
    
    def to_s
      self.inspect
    end
    
  end
  
  
  
end
