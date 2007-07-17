# Copyright (c) 2005, SNAPVINE LLC (www.snapvine.com)
# All rights reserved.

# Portions Copyright (c) 2007 Jonathan Palley, Idapted Inc.
# All rights reserved

require 'cgi'
require 'breakpoint'
#
# Class - RAI::CallConnection
#
# This class provides a Ruby API for controlling functions on the Asterisk server.  
# Many, but not all, of the Asterisk AGI commands are implemented.  The syntax of 
# these API is designed to be convenient and familiar to a Ruby developer and thus 
# do not map exactly to the method name and parameterization of Asterisk AGI.
#
# Changelog
#   7-14-05 (Joe)  - added a mechanism for routing calls to the appropriate handler via environment variable "AGI_URL"
#  


module Telegraph
  class UsageError < StandardError; end
  class CmdNotFoundError < StandardError; end
  class ApplicationError < StandardError; end
  class SoundFileNotFoundError < StandardError; end
  class ChannelHungup < StandardError; end

  CALLERID = 'agi_callerid'


  class CallConnection
    attr_reader :params
  
    ALL_DIGITS = "1234567890*#"
    ALL_NUMERIC_DIGITS = "1234567890"
    ALL_SPECIAL_DIGITS = "*#"

	  @socket = nil
    @params = {}
    
    logger=Telegraph.LOGGER
	  
	  # Many of the command here correspond roughly to Asterisk AGI in their
    # naming and parameterization.  However, we have designed these to be familiar
    # to Ruby developers.

    # Hang up immediately on the specified channel
  	def hang_up(channelName=nil) 
  		msg="HANGUP"
  		if (channelName  !=  nil)
  			msg = msg + " " + channelName
  		end
  		send(msg)
  		return get_int_result()
  	end
	
	
  	# Plays a sound over the channel, synchronously until the end of the sound.
      # Your asterisk must have the appropriate codecs installed.
      # The param "soundName" must be a full path to the sound file on the Asterisk server
  	def play_sound(soundName)
  		exec("playback", soundName)
  	end
	
  	# Plays a sound over the channel in the background and continues processing other commands.
      # Your asterisk must have the appropriate codecs installed.
      # The param "soundName" must be a full path to the sound file on the Asterisk server
  	def background(soundName)   #unverified
  		exec("background", soundName)
  	end

	  def queue(name)
	    exec("queue", "#{name}|n")
    end
    
      # Dial an address.
      # \param address - The address to dial e.g. SIP/1234@foo.com
      # \param waittime
      # \param time Maximum time for the call, in sec, or 0 to specify no time limit
      # \param extraOptions Extra options to pass to asterisk, as a string
  	def dial(address, waittime=15, time=0, extraOptions="")
        options = "g#{extraOptions}"
        if time > 0
          options = "#{options}S(#{time})"
        end
        exec("Dial", "#{address}|#{waittime.to_s}|#{options}")
  	end
	
      # Answer the channel
  	def answer
  		send("ANSWER")
  		return get_int_result()
  	end
	
      # See the Asterisk wiki for syntax.
  	def play_tones(tonestring)
  		exec("PlayTones", tonestring)
  	end
	
  	def play_record_tone
  		exec("PlayTones", "1400/500,0/15000")
  	end
	
  	def play_info_tone
  		exec("PlayTones", "!950/330,!1400/330,!1800/330,0")
  	end
	
  	def play_dial_tone
  		exec("PlayTones", "440+480/2000,0/4000")
  	end
	
  	def play_busy_tone
  		exec("PlayTones", "480+620/500,0/500")
  	end	
	
  	def send_dtmf(digits)
  		exec("SendDTMF", digits.to_s)
  	end	

  	# Send the caller to a group conference room, which is created on the fly.
  	def meet_me(confnumber)
  		exec("MeetMe", confnumber.to_s + "|dM")
  	end

      # Returns several states such as "ringing...".  See Asterisk wiki for more info.
      #
      # 0 Channel is down and available
      # 1 Channel is down, but reserved
      # 2 Channel is off hook
      # 3 Digits (or equivalent) have been dialed
      # 4 Line is ringing
      # 5 Remote end is ringing
      # 6 Line is up
      # 7 Line is busy
  	def channel_status(channelName=nil) 
  		msg = "CHANNEL STATUS"
  		if (channelName  !=  nil)
  			msg = msg + " " + channelName
  		end
  		send(msg)
  		return get_int_result()
  	end

      # Executes an arbitrary Asterisk application.
  	def exec(application, options=nil)
  		msg = "EXEC"
  		if (application  !=  nil)
  			msg = msg + " " + application
  		end
  		if (options  !=  nil)
  			msg = msg + " " + options
  		end

  		send(msg)
  		return get_result()	
  	end
	
	
  	#Plays a sound and reads key presses from the user (which are returned)
      #timeout: the milliseconds to wait for the user before giving up.
      #maxdigits:  if positive, returns when that many have been read.
  	def get_data(filename, timeout = 2000, maxdigits = -1)
        msg = "GET DATA #{filename} #{timeout}"
        if (maxdigits != -1) then
          msg = "#{msg} #{maxdigits}"
        end
        send(msg)
        result = get_result()
        if result == '-1' then
          # todo: This happens if the user hangs up too.
          #raise SoundFileNotFoundError, "Error in get_data for #{filename}"
        end
        result
  	end

      # Returns two values: 
      #   1. key pressed, as a character
      #   2. Final position of the file if it was stopped prematurely or -1 if it completed
  	def stream_file(filename, sampleOffset, escapeDigits)
        msg = "STREAM FILE #{filename} #{escape_digit_string(escapeDigits)} #{sampleOffset}"

        send(msg)

        results = get_multivalue_result

        # Parse the return values.  This is from the asterisk documentation:
        #
        # failure: 200 result=-1 endpos=<sample offset>
        # failure on open: 200 result=0 endpos=0
        # success: 200 result=0 endpos=<offset>
        # digit pressed: 200 result=<digit> endpos=<offset> 
        key = ''
        finalOffset = sampleOffset

        keyCode = results["result"]
        if keyCode
          case keyCode
          when '-1'
            # Failure
            if results["endpos"]
              finalOffset = results["endpos"].to_i
            end
          when '0'
            if results["endpos"] != '0'
              # Successful completion of file
              finalOffset = -1
            end
          else
            key = keyCode.to_i.chr
            finalOffset = results["endpos"].to_i
          end
        end

        return key, finalOffset
      end

      # Returns a variable as set in extensions.conf with setVar command.
  	def get_variable(variableName)
        cmd = "GET VARIABLE " + variableName
        send(cmd)
        res = get_result()
        if res == '0' then
          res = nil
        end
        res
  	end
	
  	# The opposite of get_variable
  	def set_variable(name, value) 
  		msg="SET VARIABLE " + name + " " + value
  		send(msg)
  		return get_int_result()
  	end

      # Calls swift.agi to speak some text.  Sorry, this expects the Cepstral engine.
  	def speak_text(texttospeak)
  		fixedmessage = texttospeak
  		fixedmessage = fixedmessage.gsub("\r", " ")
  		fixedmessage = fixedmessage.gsub("\n", " ")
  		fixedmessage = fixedmessage.strip
  		exec("AGI", "swift.agi|\"" + fixedmessage + "\"")
  	end	

  	#
  	# Usage Notes:  
  	#       Asterisk will not create directories for you, so make sure the path you specify for the sound is valid.
  	#	Silence detection must be an int greater than 0
  	#
  	def record_file(filename, maxtimeinseconds, beep=false, silencedetect=10)	
      beepstr = ""
  		if (beep == true)
  			beepstr = " BEEP "
  		end
		
  		cmd = "RECORD FILE " + filename + " gsm " + " \"*#\" " + (maxtimeinseconds * 10000).to_s + beepstr + " s=" + silencedetect.to_s
  		send(cmd)
  		return get_result()
  	end
    def mix_monitor(output_file, exten="wav", options='')
      exec("MixMonitor", "#{output_file}.#{exten}|#{options}")
    end
      
    def monitor_call(outputFile)
      exec("Monitor", "wav|#{outputFile}|m")
    end

  	# Pronounce the digits, e.g. "123" will speak as "one two three"
  	def say_digits(digits, escapeDigits=ALL_SPECIAL_DIGITS) 
  		msg="SAY DIGITS #{digits} #{escape_digit_string(escapeDigits)}"
  		send(msg)
  		return get_int_result()
  	end

      # Says the number, e.g. "123" is "one hundred twenty three"
  	def say_number(number, escapeDigits=ALL_SPECIAL_DIGITS)
  		msg="SAY NUMBER #{number} #{escape_digit_string(escapeDigits)}"
  		send(msg)
  		return get_int_result()
  	end
	
  	#Pass in a Ruby Time object
  	def say_time(time, escapeDigits=ALL_SPECIAL_DIGITS) 
  	    #calc the number of seconds elapsed since epoch (00:00:00 on January 1, 1970) 
          diff = time.to_i
  		msg = "SAY TIME #{diff} #{escape_digit_string(escapeDigits)}"
  		send(msg)
  		return get_int_result()
  	end

      # Set the caller ID to use
      # e.g.,  "8001235555"
  	def set_caller_id(idSpecification) 
  		msg="SET CALLERID " + idSpecification.to_s 
  		send(msg)
  		return get_int_result()
  	end
	
  	def wait_music_on_hold(seconds) 
  		exec("WaitMusicOnHold", seconds.to_s)
  	end
	
  	# Synchronously hold the line for some seconds
  	def wait(seconds) 
  		exec("Wait", seconds.to_s)
  	end
		
  	# Returns the current status of the call.
      # Eventually this might have states like "ringing" or "hungup"
  	def call_status
  	  dialstatus = get_variable("dialstatus")
  	  if dialstatus == nil  #the dial command has not returned yet..thus the call is in progress
  	    return :InProgress
  	  elsif dialstatus == "ANSWER"  #the dial command returned from a successfully answered call
  	    return :Answered
  	  elsif dialstatus == "BUSY"  #the dial command met with a busy signal on the other end
  	    return :Busy
  	  elsif dialstatus == "NOANSWER"  #the dial command aborted due to no answer
  	    return :NoAnswer
  	  elsif dialstatus == "CONGESTION"  #the dial command failed due to congestion
  	    return :Congestion
  	  elsif dialstatus == "CHANUNAVAIL"  #the dial command failed due to misc reasons.
  	    return :ChannelUnavailable
  	  else
  	    return :Offline   #not sure
  	  end
  	end	
	
	
  	# Used by the server for tracking
  	def agi_url
        script = @params['agi_network_script']
        return "/#{script}"
  	end

  	# This method is used in conjunction with RAI.place_call.
      # This method returns the hashData hashtable parameter from that call, if present
      # or nil if not present.  In the call file, this data is stored as an ascii encoding
      # in the call file variable "CallInitiate_hashdata"
  	def get_hash_data
        return CallInitiate.decode_call_params(get_variable("CallInitiate_hashdata"))
  	end


	#----------------HELPERS-----------------
    private

    def parse_params
      #have to process a bunch of key pairs from asterisk first
      _doit = true
      while _doit
        _res = read_line().chomp
        if (_res == nil or _res.size<=1)
          _doit = false
        else
          _name,_val = _res.split(/:\s/)
          @params[_name]=_val
          #RAI.LOGGER.info("CallParam[#{_name}]=#{_val}")
        end
      end
   
      new_script=@params['agi_network_script'].split('?')
      @params['agi_network_script']=new_script[0]

      unless new_script[1].nil?
       new_script[1].split('&').each{|param|
         _name,_val = param.split('=')
         @params[_name]=_val
      }
      end
    end

  	def send(message)
  		@socket.print(message)
  		#RAI.LOGGER.info("msg=#{message}");
  	end
	
  	def get_int_result
  		result=parse_result(get_result())
  		intresult = -1
  		if (result == nil)
  			intresult = -1
  		else
  			intresult = result.to_i
  		end
  		#RAI.LOGGER.info("res=#{intresult}");
  	end

  	def get_result
  		_res = parse_result(read_line())
  	end

    # Parse a result that consists of a 200 result code plus one or
    # more name=value pairs separated by spaces.  Calls through to
    # parse_result if the status is not 200.  Returns hash of
    # name=value pairs.
    def get_multivalue_result
      rawResult = read_line()

      if (rawResult[0..2] == "200") then
        rawResult.slice!(0..2)
        pairs = rawResult.split(' ')

        results = {}
        pairs.each do |pair|
          tmp = pair.split('=')
          results[tmp[0]] = tmp[1]
        end
      
        results
      else
        parse_result(rawResult)
      end
    end

  	def read_line
  		begin
  			_res = @socket.gets   #gets
  			Telegraph.LOGGER.debug("READ LINE: " + _res.to_s)
  		rescue Errno::EINVAL
  			raise ApplicationError
  		end
  		_res
  	end
	

  	# Asterisk AGI talks over a human-readable protocol.  We parse that.
    # Asterisk appears to be giving back multiple error responses
  	# before sending the "real" response.  Thus, we have to
  	# read through error codes such as 510 and 520 and look for the 200.
  	def parse_result(_res)
  		#form of the response:  
  		#VALID RESULTS (arbitrary value) ==>    200 result=1 (1119166301)
  		#VALID RESULTS (integer) ==>  Response:  200 result=0
  		#BAD COMMAND    ==>    510
  		#USAGE ERROR    ==>    520...520..\n
  		#if I get 510, then the command was not found, sorry
		  # 510 = BAD COMMAND
  		return response_510_bad_command(_res) if (_res=~/510/)==0 

  		#if I get 520, then the command usage was not found, sorry
  		return response_520_usage_error(_res) if (_res=~/520/)==0
    
      # 200 = Results
  		return response_200_results(_res) if (_res=~/200/)==0
    end
    
    def response_200_results(_res)
      return nil unless valid_response(_res)
			
			#if there is a value in  parens, return it.
			lb=_res.index("(")
			rb=_res.rindex(")")
			eqindex=_res.index('=')
			if (lb != nil and rb != nil)
        value = _res[lb+1, rb-lb-1]
        if value == "timeout" then
          # in the case of "200 result=<num> (timeout)" we should return <num>
          value = _res[eqindex+1,lb-eqindex-1]
        end
      
        value.chomp!(" ")
        return value
			else
        # there is an int result we hope.
        value = _res[eqindex+1, _res.length]
        returning value.chomp! do |val|
          raise ChannelHungup if val == "-1"
        end
			end
		end
    
    def response_510(_res)
      while !(_res=~/510/)      # asterisk may send more than one at at time. lame.
				#logger.info("Received " + _res);
				_res = read_line()
				#logger.info("STUFF2:  #{_res}")
			end
		
	#		logger.info("Received 510 Command not found error #{_res}")
			_cmd = /\(.*\)/.match(_res).to_s.gsub(/[\(\)]/,'')
			raise CmdNotFoundError, "Command could not be found = #{_cmd}"
			return nil
		end
		
		def response_520_useage_error(_res)
#		  logger.info("Received 520 Invalid Command Usage #{_res}")
			_usage = ''
			_res = read_line()
			#logger.info("STUFF:  #{_res}")
			while !(_res=~/520/)  # asterisk may send more than one at at time. lame.
				#Rlogger.info("Received " + _res);
				_usage += _usage
				_res = read_line()
				#logger.info("STUFF2:  #{_res}")
			end
			raise UsageError, "Command Usage Incorrect, correct usage - #{_usage}"
			return nil
		end
    
    def valid_response(_res)
      eqindex =_res.index("=")  
			if (eqindex==nil)
				RAILS_DEFAULT_LOGGER.error("Error, unexpected 200 result with no value " + _res.to_s)
				return nil
			end
			return true
    end
    
    def logger=(logger)
      @logger=logger
    end
    
    def logger
      @logger
    end
    
    
    
    def escape_digit_string(digits)
      if digits
        "\"#{digits}\""
      else
        ""
      end
    end
    
  end
end
