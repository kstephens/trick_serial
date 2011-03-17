$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'rspec'
require 'cnu_serializer'

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

=begin
require 'rubygems'
gem 'ruby-debug'
require 'ruby-debug'
=end

RSpec.configure do |config|
  
end

######################################################################
# Common test helpers
#

module Cnu
  class Serializer
    module Test
      class PhonyActiveRecord
        attr_accessor :id

        @@find_map = { }
        def self.find_map
          @@find_map
        end

        def initialize
          @id = object_id
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
      end
      
      class Model < PhonyActiveRecord
        attr_accessor :state
        def initialize x = nil
          super()
          @state = x
        end
      end
    end
  end
end

