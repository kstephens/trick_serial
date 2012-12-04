require File.expand_path('../../spec_helper', __FILE__)

# Test Target:
require 'trick_serial/serializer/cgi_session'

# Test Helpers:
require 'cgi'
require 'cgi/session'
require 'cgi/session/pstore'
require 'fileutils'
require 'stringio'

$have_mem_cache_store = false
begin
  require 'action_controller/session/mem_cache_store'
  require 'trick_serial/serializer/cgi_session'
  $have_mem_cache_store = true
rescue LoadError => err
  # NOTHING
end


TrickSerial::Serializer::CgiSession.activate!

describe "TrickSerial::Serializer::Cgi::Session" do

  before(:each) do 
    @s = TrickSerial::Serializer.new
    @s.class_option_map = { 
      TrickSerial::Serializer::Test::PhonyActiveRecord => 
      { :proxy_class => TrickSerial::Serializer::ActiveRecordProxy, },
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

  def create_session! options
    @cgi = CGI.new("html4")
    def @cgi.env_table; @env_table ||= { }; end
    def @cgi.stdinput; @stdinput ||= StringIO.new; end

    @cgi.stdinput << @header if @header

    yield if block_given?

    options = {
      'TrickSerial.database_manager' => @store,
      'database_manager' => TrickSerial::Serializer::CgiSession::Store,
      'tmpdir' => @tmpdir,
      'session_id' => 'abc123',
      'session_key' => '_test',
      'session_expires' => Time.now + 30 + 30,
      'prefix' => '_test',
    }.merge(options)
    @session = CGI::Session.new(cgi, options)
  end

  def test_store! store, options = { }
    @tmpdir = "/tmp/#{File.basename(__FILE__)}-#{$$}"
    FileUtils.mkdir_p(@tmpdir)

    @store = store

    create_session! options

    @session['a'] = 1
    @session['b'] = :b
    @session['c'] = "aksjdfsd"
    @session['m'] = @m
    @session['m2'] = @m
    @session['m_unsaved'] = @m_unsaved
    @session['ary'] = [ 0, 1, @m, 3, 4, @m ]

    @session.update
    @session.close

    create_session! options

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

  if $have_mem_cache_store 
    it "should handle CGI::Session::MemCacheStore" do
      begin
        memcache_pid = nil
        memcache_port = 45328
        memcache_host = '127.0.0.1'
        memcache_args = [ "memcached", 
                          "-p", memcache_port,
                          "-l", memcache_host,
                        ]
        memcache_args << "-vvv" if $DEBUG

        cache = ::MemCache.new(memcache_host)
        cache.servers = "#{memcache_host}:#{memcache_port}"
        session_opts = { 
          'cache' => cache,
        }
        memcache_pid = Process.fork do
          memcache_args.map!{|e| e.to_s}
          $stderr.puts "#{__FILE__}: starting memcache #{memcache_args.inspect}" if $DEBUG
          Process.exec(*memcache_args)
        end
        sleep 1
        test_store! CGI::Session::MemCacheStore, session_opts
      ensure
        sleep 1
        Process.kill(9, memcache_pid) if memcache_pid
      end
    end
  end
end

