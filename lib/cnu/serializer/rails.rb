module Cnu
  class Serializer
    module Rails
      def self.initialize!
        Cnu::Serializer::CgiSession.initialize!

        rails_version = 
          (Rails.version rescue nil) ||
          (RAILS_VERSION rescue nil) || :unknown
        case rails_version
        when /^3\./
          V3.initialize!
        when /^1\.2\./
          V12.initialize!
        else
          raise ArgumentError, "#{self}: Unknown Rails version: #{rails_version.inspect}"
        end
      end

      module V3
        def self.initialize!
        end
      end

      module V12
        def self.initialize!
        end
      end
    end
  end
end
