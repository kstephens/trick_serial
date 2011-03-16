module Cnu
  class Serializer
    # Support for ::CGI::Session stores.
    module CgiSession
      def self.initialize!
        if defined? ::CGI::Session::FileStore
          ::CGI::Session::FileStore.send(:include, FileStoreSerializer)
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
        
        class ModuleMethods
          def included target
            super
            target instance_eval do 
              alias :update_without_cnu_serializer :update
              alias :update :update_with_cnu_serializer
            end
          end
        end
        
        # Clones Cnu::Serializer.default.
        # Encodes the session store's "data".
        # Replaces the session store's data with the encoded data.
        # Call original #update.
        # Restores old session store's "data".
        def update_with_cnu_serializer
          serializer = Cnu::Serializer.default.dup
          data_save = self._data
          self._data = serializer.encode(data_save)
          update_without_cnu_serializer
        ensure
          self._data = data_save
        end
      end
      
      module FileStoreSerializer
        include SessionStore
        def data; @hash; end
        def data= x; @hash = x; end
      end
      
      module MemCacheStoreSerializer
        include SessionStore    
        def _data; @session_data; end
        def _data=x; @session_data = x; end
      end
    end
    
  end
end

