require 'cnu/serializer'

module Cnu
  class Serializer
    # Support for ::CGI::Session stores.
    module CgiSession
      def self.activate!
        require 'cgi/session'
        require 'cgi/session/pstore'

#=begin
        if defined? ::CGI::Session::FileStore
          ::CGI::Session::FileStore.send(:include, FileStoreSerializer)
        end
#=end
        if defined? ::CGI::Session::PStore
          ::CGI::Session::PStore.send(:include, PStoreSerializer)
        end
        if defined? ::CGI::Session::MemCacheStore
          ::CGI::Session::MemCacheStore.send(:include, MemCacheStoreSerializer)
        end
      end
      
      # Defines common mixin for interjecting Cnu::Serializer before
      # SessionStore#update saves its data. 
      module SessionStore
        def self.included target
          super
          target.extend(ModuleMethods)
        end
        
        module ModuleMethods
          def included target
            super
            target.class_eval do 
              alias :restore_without_cnu_serializer :restore
              alias :restore :restore_with_cnu_serializer
              alias :update_without_cnu_serializer :update
              alias :update :update_with_cnu_serializer
            end
          end
        end
        
        def restore_with_cnu_serializer
          restore_without_cnu_serializer
          decode_with_cnu_serializer!
          _data
        end

        def encode_with_cnu_serializer!
        end

        def decode_with_cnu_serializer!
        end

        # Clones Cnu::Serializer.default.
        # Encodes the session store's "data".
        # Replaces the session store's data with the encoded data.
        # Call original #update.
        # Restores old session store's "data".
        def update_with_cnu_serializer
          serializer = Cnu::Serializer.default.dup
          data_save = self._data
          self._data = serializer.encode(self._data)
          encode_with_cnu_serializer!
          update_without_cnu_serializer
        ensure
          self._data = data_save
        end
      end
      
      # FileStore can only handle String => String data.
      # Use Marshal and Base64 to further encode it.
      module FileStoreSerializer
        include SessionStore
        def self.included target
          super
          require 'base64'
        end

        def _data; @hash; end
        def _data= x; @hash = x; end

        def encode_with_cnu_serializer!
          # $stderr.puts "#{self} encode <= @hash=#{@hash.inspect}"
          @hash = { '_' => ::Base64.encode64(Marshal.dump(@hash)).chomp! }
          # $stderr.puts "#{self} encode => @hash=#{@hash.inspect}"
        end
        def decode_with_cnu_serializer!
          # $stderr.puts "#{self} decode <= @hash=#{@hash.inspect}"
          @hash = @hash['_'] ? Marshal.load(::Base64.decode64(@hash['_'])) : { }
          # $stderr.puts "#{self} decode => @hash=#{@hash.inspect}"
        end
      end

      module PStoreSerializer
        include SessionStore
        def _data; @hash; end
        def _data= x; @hash = x; end
      end
      
      module MemCacheStoreSerializer
        include SessionStore 
        def _data; @session_data; end
        def _data=x; @session_data = x; end
      end
    end
    
  end
end

