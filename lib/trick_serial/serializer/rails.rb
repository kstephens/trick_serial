require 'trick_serial/serializer'

module TrickSerial
  class Serializer
    module Rails
      def self.activate!
        rails_version = 
          (Rails.version rescue nil) ||
          (RAILS_VERSION rescue nil) || :unknown
        case rails_version
        when /^3\./
          V3
        when /^1\.2\./
          V12
        else
          raise ArgumentError, "#{self}: Unknown Rails version: #{rails_version.inspect}"
        end.activate!
      end

      # Rails 3 support.
      module V3
        def self.activate!
=begin
          if defined? ::ActiveRecord::Session
            ::ActiveRecord::Sesson.send(:include, ActiveRecordSessionSerializer)
          end
=end
          if defined? ::ActionDispatch::Session::MemCacheStore
            ::ActionDispatch::Session::MemCacheStore.send(:include, SessionStoreSerializer)
          end
        end

        module SessionStoreSerializer
          def self.included target
            super
            target.class_eval do
              alias :get_session_without_trick_serial_serializer :get_session
              alias :get_session :get_session_with_trick_serial_serializer
              alias :set_session_without_trick_serial_serializer :set_session
              alias :set_session :get_session_with_trick_serial_serializer
            end
          end

          def get_session_with_trick_serial_serializer env, sid
            result = get_session_without_trick_serial_serializer env, sid
            result
          end

          def set_session_with_trick_serial_serializer env, sid, session_data
            serializer = (env[:'TrickSerial::Serializer.instance'] || TrickSerial::Serializer.default).dup
            session_data = serializer.encode(session_data) 
            set_session_without_trick_serial_serializer env, sid, session_data
            result
          end
        end

        module ActiveRecordSessionSerializer
          def self.included target
            super
            target.class_eval do
              alias :marshal_data_without_trick_serial_serializer! :marshal_data!
              alias :marshal_data! :marshal_data_with_trick_serial_serializer!
            end
          end

          def marshal_data_with_trick_serial_serializer!
            save_data = @data
            if loaded?
              serializer = TrickSerial::Serializer.default.dup
              @data = serializer.encode(@data)
            end
            marshal_data_without_trick_serial_serializer!
          ensure
            @data = save_data
          end
        end
      end

      # Rails 1.2 support.
      module V12
        def self.activate!
          require 'trick_serial/serializer/cgi_session'
          TrickSerial::Serializer::CgiSession.activate!
        end
      end
    end
  end
end
