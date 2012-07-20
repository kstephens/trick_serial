require 'trick_serial/serializer'

module TrickSerial
  class Serializer
    # Support for ::CGI::Session stores.
    #
    # Stores for use with CGI::Session and TrickSerial::Serializer::CgiSession::Store
    # must implement #_data and #_data= to get access to the underlying Hash structure.
    #
    module CgiSession
      def self.activate!
        require 'cgi/session'
        require 'cgi/session/pstore'

        ::CGI::Session.send(:include, SessionSerializer)

        if defined? ::CGI::Session::FileStore
          ::CGI::Session::FileStore.send(:include, FileStoreSerializer)
        end
        if defined? ::CGI::Session::PStore
          ::CGI::Session::PStore.send(:include, PStoreSerializer)
        end
        if defined? ::CGI::Session::MemCacheStore
          ::CGI::Session::MemCacheStore.send(:include, MemCacheStoreSerializer)
        end
        if defined? ::CGI::Session::CassandraStore
          ::CGI::Session::CassandraStore.send(:include, CassandraStoreSerializer)
        end
      end
      
      # Defines a Session store Decorator that interjects TrickSerial::Serializer
      # inside #restore, #update, etc.
      #
      # Example:
      #
      #   cgi = CGI.new("html4")
      #   session = CGI::Session.new(
      #     'database_manager' => TrickSerial::Serializer::CgiSession::Store, # The Decorator.
      #     'TrickSerial.database_manager' => CGI::Session::PStore, # Actual store Class.
      #     # Options for PStore instance:
      #     'tmpdir' => '/tmp/mysessions',
      #     'session_key' => 'mykey',
      #     ...
      #   )
      #     
      class Store
        attr_accessor :logger, :logger_level

        # Options:
        #
        #   'TrickSerial.database_manager': the actual session Store class (e.g.: CGI::Session::PStore).
        #   'TrickSerial.dbman': an actual session store instance.
        #   'TrickSerial.serializer': a clonable instance of TrickSerial::Serializer.
        #   'TrickSerial.logger': a Log4r object.
        #   'TrickSerial.logger_level': a Symbol for the logger level (e.g: :debug)
        #
        # The remaining options are passed to the actual Store specified by
        # :'TrickSerial.database_manager'.
        def initialize(session, option={})
          @session = session
          @option = option
          @dbman_cls = option.delete('TrickSerial.database_manager') ||
            (raise "#{self} options did not specify TrickSerial.database_manager: #{option.inspect}")
          @dbman = option.delete('TrickSerial.dbman')
          # option['new_session'] = true 
          @option['database_manager'] = @dbman_cls
          @serializer = option.delete('TrickSerial.serializer')
          @logger = option.delete('TrickSerial.logger')
          @logger_level = option.delete('TrickSerial.logger_level') || :debug
          _log { "creating #{self} for #{option.inspect}" }
        end

        def _dbman
          @dbman ||= 
            begin
              # Fool decorated Store.
              save = @session.new_session
              @session.new_session = true
              # debugger
              @dbman_cls.new(@session, @option)
            ensure
              @session.new_session = save
            end
        end

        def _make_serializer
          (@serializer || TrickSerial::Serializer.default).dup
        end

        def restore
          _log { "#{self} restore" }
          _dbman.restore
          _dbman.decode_with_trick_serial_serializer! if _dbman.respond_to?(:decode_with_trick_serial_serializer!)
          _dbman._data
        end

        def update
          _log { "#{self} update" }
          serializer = _make_serializer
          data_save = _dbman._data
          _dbman._data = serializer.encode(_dbman._data)
          _dbman.encode_with_trick_serial_serializer! if _dbman.respond_to?(:encode_with_trick_serial_serializer!)
          # debugger
          _dbman.update
        ensure
          _dbman._data = data_save
        end

        def close
          _log { "#{self} close" }
          serializer = _make_serializer
          data_save = _dbman._data
          _dbman._data = serializer.encode(_dbman._data)
          _dbman.encode_with_trick_serial_serializer! if _dbman.respond_to?(:encode_with_trick_serial_serializer!)
          _dbman.close
        ensure
          _dbman._data = data_save
        end

        def delete
          _log { "#{self} delete" }
          _dbman.delete
        end

        def _log msg = nil
          msg ||= yield if block_given?
          if msg && @logger
            @logger.send(@logger_level, msg)
          end
        end
      end

      # Hacks to get access to Session.new_session.
      module SessionSerializer
        attr_writer :session_id, :new_session
      end

      # Defines common mixin for interjecting TrickSerial::Serializer before
      # SessionStore#update saves its data. 
      module SessionStoreDataHook
        def self.included target
          super
          target.extend(ModuleMethods)
        end
        
        module ModuleMethods
          def included target
            super
=begin
            target.class_eval do 
              alias :restore_without_trick_serial_serializer :restore
              alias :restore :restore_with_trick_serial_serializer
              alias :update_without_trick_serial_serializer :update
              alias :update :update_with_trick_serial_serializer
            end
=end
          end
        end

=begin        
        def restore_with_trick_serial_serializer
          restore_without_trick_serial_serializer
          decode_with_trick_serial_serializer!
          _data
        end
=end

        def encode_with_trick_serial_serializer!
        end

        def decode_with_trick_serial_serializer!
        end

=begin
        # Clones TrickSerial::Serializer.default.
        # Encodes the session store's "data".
        # Replaces the session store's data with the encoded data.
        # Call original #update.
        # Restores old session store's "data".
        def update_with_trick_serial_serializer
          serializer = TrickSerial::Serializer.default.dup
          data_save = self._data
          self._data = serializer.encode(self._data)
          encode_with_trick_serial_serializer!
          update_without_trick_serial_serializer
        ensure
          self._data = data_save
        end
=end
      end
      
      # FileStore can only handle String => String data.
      # Use Marshal and Base64 to further encode it.
      module FileStoreSerializer
        include SessionStoreDataHook
        def self.included target
          super
          require 'base64'
        end

        def _data; @hash; end
        def _data= x; @hash = x; end

        PHONY_KEY = '_'.freeze

        def encode_with_trick_serial_serializer!
          # $stderr.puts "#{self} encode <= @hash=#{@hash.inspect}"
          @hash &&= { PHONY_KEY => ::Base64.encode64(Marshal.dump(@hash)).chomp! }
          # $stderr.puts "#{self} encode => @hash=#{@hash.inspect}"
        end
        def decode_with_trick_serial_serializer!
          # $stderr.puts "#{self} decode <= @hash=#{@hash.inspect}"
          @hash &&= (v = @hash[PHONY_KEY]) ? Marshal.load(::Base64.decode64(v)) : { }
          # $stderr.puts "#{self} decode => @hash=#{@hash.inspect}"
        end
      end

      module PStoreSerializer
        include SessionStoreDataHook
        def _data; @hash; end
        def _data= x; @hash = x; end
      end
      
      module MemCacheStoreSerializer
        include SessionStoreDataHook
        def _data; @session_data; end
        def _data=x; @session_data = x; end
      end
      
      module CassandraStoreSerializer
        include SessionStoreDataHook
        def _data; @session_data; end
        def _data=x; @session_data = x; end
      end
    end
    
  end
end

