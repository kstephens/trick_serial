require File.expand_path('../../spec_helper', __FILE__)

# Test Target:
require 'trick_serial/serializer/cgi_session'

# Test Helpers:
require 'cgi'
require 'cgi/session'
require 'cgi/session/pstore'
require 'fileutils'
require 'stringio'

TrickSerial::Serializer::CgiSession.activate!

describe "TrickSerial::Serializer::Cgi::Session" do
  before(:each) do 
    @s = TrickSerial::Serializer.new
    @s.proxy_class_map = { 
      TrickSerial::Serializer::Test::PhonyActiveRecord => TrickSerial::Serializer::ActiveRecordProxy,
    }

    TrickSerial::Serializer::Test::PhonyActiveRecord.find_map.clear
    
    @m = TrickSerial::Serializer::Test::Model.new(123)
    @m_unsaved = TrickSerial::Serializer::Test::Model.new(:unsaved)
    @m_unsaved.id = nil

    TrickSerial::Serializer.default = @s
  end

  after(:each) do 
    TrickSerial::Serializer.default = nil
  end


  attr_accessor :cgi, :session

  def create_session!
    @cgi = CGI.new("html4")
    def @cgi.env_table; @env_table ||= { }; end
    def @cgi.stdinput; @stdinput ||= StringIO.new; end

    @cgi.stdinput << @header if @header

    yield if block_given?

    @session = CGI::Session.new(cgi,
                                :'TrickSerial.database_manager' => @store,
                                'database_manager' => TrickSerial::Serializer::CgiSession::Store,
                                'tmpdir' => @tmpdir,
                                'session_id' => 'abc123',
                                'session_key' => '_test',
                                'session_expires' => Time.now + 30 + 30,
                                'prefix' => '_test')
  end

  def test_store! store
    @tmpdir = "/tmp/#{File.basename(__FILE__)}-#{$$}"
    FileUtils.mkdir_p(@tmpdir)

    @store = store

    create_session!

    @session['a'] = 1
    @session['b'] = :b
    @session['c'] = "aksjdfsd"
    @session['m'] = @m
    @session['m2'] = @m
    @session['m_unsaved'] = @m_unsaved
    @session['ary'] = [ 0, 1, @m, 3, 4, @m ]

    @session.update
    @session.close

=begin
    outheader = @cgi.header
    # $stderr.puts "cgi.header=\n#{outheader}\n"
    outheader =~ /^Set-Cookie: ([^;]*;)/
    raw_cookie = $1 || (raise "Cannot file Set-Cookie in header.")
    $stderr.puts "raw_cookie = #{raw_cookie.inspect}"

    ##################################################################

    create_session! do
      @cgi.env_table["HTTP_COOKIE"] = raw_cookie
    end
=end

    create_session!

    fm = TrickSerial::Serializer::Test::PhonyActiveRecord.find_map
    fm.clear
    fm[@m.id].should == nil

    @session['a'].should == 1
    @session['b'].should == :b
    @session['c'].should == "aksjdfsd"

    fm[@m.id].should == nil

    @session['m'].class.should == @m.class
    @session['m'].object_id.should_not == @m.object_id
    @session['m'].id.should == @m.id

    fm[@m.id].should == 1

    @session['m2'].object_id.should == @session['m'].object_id

    fm[@m.id].should == 1

    @session['ary'].class.should == Array

    fm[@m.id].should == 1
    fm.keys.size.should == 1

  ensure
    File.unlink(*Dir["#{@tmpdir}/*"])
    FileUtils.rmdir(@tmpdir)
  end

  # FileStore can only handle String => String data.
  it "should handle CGI::Session::FileStore" do
    test_store! CGI::Session::FileStore
  end

=begin
  # MemoryStore is completely transparent
  it "should handle CGI::Session::MemoryStore" do
    test_store! CGI::Session::MemoryStore
  end
=end

  it "should handle CGI::Session::PStore" do
    test_store! CGI::Session::PStore
  end

end

