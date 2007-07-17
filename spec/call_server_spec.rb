require File.dirname(__FILE__) + '/../../../../spec/spec_helper'

class Telegraph::CallConnection
  def parse_params
  end
end




describe "Main request loop" do
  before(:each) do
    ENV["REQUEST_METHOD"]="post"
    @call_server = Telegraph::CallServer.new
    @call_connection = Telegraph::CallConnection.new(nil,CGI.new)
    Telegraph::CallConnection.stub!(:new).and_return(@call_connection)
    
  end
  it "should initilize okay" do
    Telegraph::CallServer.new
  end
  
  it "should check_parameters" do
    @call_connection.request.path = "/tests/show/1"
    @call_connection.should_receive(:should_continue?).and_return(false)
    @call_server.handle_request(nil)
    params = @call_connection.request.parameters
    params["action"].should == "show"
    params["controller"].should == "tests"
    params["id"].should == "1"
  end
  
  it "should keep the parameters in the request" do
    mc = mock("tests controller")
    TestsController.should_receive(:new).and_return(mc)
    mc.should_receive(:process)
    @call_connection.request.path_parameters = {:action=>"action",:controller=>"tests",:id=>"1"}
    @call_connection.request.next_controller = "TestsController"

    @call_server.perform_action(@call_connection,CGI.new)
    params = @call_connection.request.parameters
    params["action"].should == "action"
    params["controller"].should == "tests"
    params["id"].should == "1"    
    
  end
  
  it "should correctly setup parameters after redirect" do
    @call_connection.request.path_parameters = {:action=>"action",:controller=>"tests",:id=>"1"}
    @call_server.stub!(:cc).and_return(@call_connection)
    @call_server.stub!(:cgi).and_return(CGI.new)
    @call_connection.request.create_redirect(:action=>"new",:controller=>"new_c")
    @call_connection.request.parameters!
    params = @call_connection.request.parameters
    params["action"].should == "new"
    params["controller"].should == "new_c"
    params["id"].should be_nil
  end
  it "should correctly set the controller once set" do
    request = @call_connection.request
    request.path_parameters = {:action=>"action",:controller=>"tests",:id=>"1"}
    request.parameters!
    request.parameters[:controller].should == "tests"
    @call_server.stub!(:cc).and_return(@call_connection)
    @call_server.stub!(:cgi).and_return(CGI.new)
    @call_connection.request.create_redirect(:action=>"new")
    @call_connection.request.parameters!
    params = @call_connection.request.parameters
    params["action"].should == "new"
    params["controller"].should == "tests"
    params["id"].should be_nil
  end
end