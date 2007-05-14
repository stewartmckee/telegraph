# Copyright (c) 2007 Jonathan Palley, Idapted Inc.
# All rights reserved


module Telegraph
  require 'drb'
   require 'monitor'
   require 'socket'
   require 'timeout'
   require 'digest/md5'


  class AMIConnectionError < StandardError; end
  class AMIFunctionError < StandardError; end
  class AMIManager
    ###############################
    # The following arrays hold a list of the Asterisk functions and their required parameters
    ###############################
    FIND = {:agents =>           [:agents,          []],
            :db =>              [:db_get,          [:family, :key]],
            :extension_state => [:extension_state, [:context, :exten]],
            :variable =>        [:get_variable,    [:channel, :variable]],
            :all_iax_peers =>       [:iax_peers,       []],
            :mailbox =>         [:mailbox_status,  [:mailbox]],
            :parked_calls =>    [:parked_calls,    []],
            :queue =>           [:queue_status,    []],
            :mailbox_count=>    [:mailbox_count,   []],
            :sip_peer=>         [:sip_show_peer,  [:peer]],
            :all_sip_peers=>    [:sip_peers,       []],
            :status=>          [:status,  [:channel]]
          }
          
    UPDATE = {:absolute_timeout =>  [:absolute_timeout,  [:channel, :timeout]],
              :monitor =>           [:change_monitor,    [:channel, :file]],
              :db =>                [:db_put,            [:family, :key, :value]],
              :redirect =>          [:redirect,          [:channel, :context, :extension, :priority]],
              :variable =>          [:set_variable,       [:channel, :variable, :value]]
      }
    
    CREATE = {:monitor =>           [:monitor, [:channel, :file, :format, :mix]],
              :call =>              [:originate, []]  #Call/Originate has many optional parameters
      }
      
    DESTROY = {:call =>             [:hangup, [:channel]],
               :monitor =>          [:stopmonitor, [:channel]]
              }
    
    @@connection = nil
    @@drb_started = false
    @@last_connect_attempt = 5.minutes.ago
    
    #Establish Connection to AMI Server
    def self.establish_connection!(opts={})
      @@connection_options = opts
      raise AMIConnectionError unless self.reconnect!
    end

    def self.reconnect!
      return false if @@last_connect_attempt and Time.now - @@last_connect_attempt < 60
      @@last_connect_attempt = Time.now

      @@connection = Telegraph::AMIClient.new("druby://localhost:9000")
      return @@connection
    end
    
    def self.disconnect!
      if @@drb_started
        DRb.stop_service
      end
    end

    #return connection object
    def initialize
      @response = nil
    end
    
    def connection
      @@connection
    end

    %w(find update create destroy).each do |f|
      class_eval <<-HERE
        def self.#{f}(func, args={})
          exec_func(#{f.upcase}[func.to_sym], args)
        end
      HERE
    end

    
    def self.exec_func(func_specs, args= {})
        if func_specs
          if (func_specs[1] - args.keys).empty?
            re = Telegraph::AMIManager.new
            re.do_action({:action=> func_specs[0]}.merge(args))
            re
          else
            raise AMIFunctionError, "Missing Arguements: #{(func_specs[1] - args.keys).join(', ')}"
          end
        else
          raise AMIFunctionError, "Invalid Find Item: #{func.to_s}"
        end
    end
    
    def do_action(args)
      if self.connection
        @response = self.connection.do_action(args)  
      else
        if AsteriskManager.reconnect!
           do_action(args)
        else
          raise AMIConnectionError
        end  
      end
    end
    #Forward methods to AMI
    def method_missing(method, *args, &block)
   
      #Allows you to access most attributes
      return @response.attributes[method] if @response.attributes[method]
      
      #Allows you to access things like PeerEntries
      return @response.events.find_all{|e| e[:event] == "#{method.to_s.singularize.camelize}Entry"} if @response.events.detect{|e| e[:event] == "#{method.to_s.singularize.camelize}Entry"}
      
      #Allows parsed channel names
      return @response.attributes[(method.to_s.delete('parsed_')).to_sym] if method.to_s =~ /parsed/
      
#      if self.connection
#        self.connection.send(method, *args, &block) if self.connection.respond_to?(method)
#      else
#        if AsteriskManager.reconnect!
#           method_missing(method, *args, &block)
#        else
#          raise AMIConnectionError
#        end  
#      end
    end
    
    def events
      @response.events if @response
    end
    
    # This function gives you the pure channel name (i.e. SIP/Test)
    def self.parse_channel(str)
      str.gsub('SIP/', '').gsub(/-[a-zA-Z0-9]*/,'')
    end
    
    def self.cli_command(command)
      Telegraph::AMIManager.new.do_action({:action => :command, :command => command})
    end
      
      
    def self.queues
      queue_status = Telegraph::AMIManager.new.queue_status
      queues = Array.new
      events = Array.new

      raw_events = queue_status.events
      
      prev_queue = nil
      raw_events.each do |e|
        if e[:queue] != prev_queue
          queues << Telegraph::AMIManager.new(events) unless events.empty?
          events = Array.new
        end
        events << e
        
        prev_queue = e[:queue]
      end
      queues
    end
    
    
    
  end
  
  class Queue
    attr_reader :params, :members, :callers
    def initialize(events)
      @params = events.find{|e| e[:event] == "QueueParams"}
      events.delete(events.find{|e| e[:event] == "QueueParams"})
      @members = events.find_all{|e| e[:event] == "QueueMember"}
      @callers = events.find_all{|e| e[:event] == "QueueEntry"}
    end
  end
  
  
end
    
