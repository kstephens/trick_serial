$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'rspec'
require 'trick_serial'

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

=begin
if $DEBUG || ENV['DEBUG']
  require 'rubygems'
  gem 'ruby-debug'
  require 'ruby-debug'
end
=end

RSpec.configure do |config|
  
end

######################################################################
# Common test helpers
#

module TrickSerial
  class Serializer
    module Test
      class A
        attr_accessor :x, :y
      end
      class B
        attr_accessor :x, :y
      end
      class PhonyActiveRecord
        attr_accessor :id

        @@find_map = { }
        def self.find_map
          @@find_map
        end

        @@id ||= 0
        def initialize
          @id = (@@id += 1)
        end
        def self.find(id)
          obj = new
          obj.id = id
          # $stderr.puts "  #{self}.find(#{id.inspect}) => #{obj.inspect}"
          # (@@find_map[id] ||= 0) += 1 # Shouldn't Ruby parse this?
          @@find_map[id] ||= 0
          @@find_map[id] += 1
          obj
        end

        def to_s
          super.sub!(/>$/, " id=#{@id.inspect}>")
        end
      end
      
      class Model < PhonyActiveRecord
        attr_accessor :state
        def initialize x = nil
          super()
          @state = x
        end

        def to_s
          super.sub!(/>$/, " @state=#{@state.inspect}>")
        end
      end
    end
  end
end

