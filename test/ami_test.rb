
require 'test/unit'

require File.expand_path(File.join(File.dirname(__FILE__), '../../../../config/environment.rb'))
class RAI::TelegraphTCP
  @@recieved_buffer = Array.new
  @@write_buffer = Array.new
  def set_recieved(data, add_crlf = true)
    if data.kind_of?(Array)
      data.reverse_each do |r|
        add_to_recieved_buffer(r, add_crlf)
      end
    elsif data =~ /\n/
      data.split("\n").reverse_each do |r|
        add_to_recieved_buffer(r.gsub(/^\s+/, ""), true)
      end
    else
      add_to_recieved_buffer(data, add_crlf)
    end
  end
  
  def add_to_recieved_buffer(line, add_crlf)
    line = line + "\n\r" if add_crlf
    @@recieved_buffer << line
  end
  
  def clear_recieved_buffer
    @@recieved_buffer.clear
  end
  
  def gets
    puts "gets"
    s =@@recieved_buffer.pop
    puts "Sending: " + s
    return s
  end
  
  def initialize(host=nil, port=nil)
    puts "initialize"
  end
  
  def write(w)
    @@write_buffer << w
  end
  
  def written
    @@write_buffer
  end
  
  def clear_write_buffer
    @@write_buffer.clear
  end
  
end


class AMIServerTest < Test::Unit::TestCase
  def setup
    @blah = Test::Unit::MockObject(TCPSocket).new
    @tcp = RAI::TelegraphTCP.new
    @srv = RAI::AMIServer.new
  end
  
  def test_mock_tcp
    @tcp.set_recieved('Hi There')
    assert_equal "Hi There\n\r", @tcp.gets
    
    @tcp.set_recieved(['Hi There', 'Long time no talk'], false)
    assert_equal 'Hi There', @tcp.gets
    assert_equal 'Long time no talk', @tcp.gets
         
    s = <<-EOL 
      line_1
      line_2
      line_3
    EOL
    puts s
    
    @tcp.set_recieved(s)
    assert_equal "line_1\n\r", @tcp.gets
    
    @tcp.write("You there?")
    assert  @tcp.written.include?('You there?')
    
    
  end
   
  def test_connects
    puts "test_connect"
    
    s = <<-EOM
    Asterisk Call Manager/1.0
    Response: Success
    ActionID: 1177582847.67069
    Challenge: 18535068
    
    Response: Success
    ActionID: 1177582847.84917
    Message: Authentication accepted
    
    EOM
    
    @tcp.set_recieved(s)
    tcp2 = RAI::TelegraphTCP.new
    assert_equal tcp2.gets, "Asterisk Call Manager/1.0\n\r"
    puts "recieved"
    
     @srv.connect
     
#     puts "connect"
#     assert_written 'Action: challenge'
#     assert_written 'Action: login'
  end
  
  
  private 
  def assert_written(line)
    assert @tcp.written.include?(line)
  end
end