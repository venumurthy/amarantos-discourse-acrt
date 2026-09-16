# frozen_string_literal: true

module ::AmarantosAcrt
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace AmarantosAcrt
    config.autoload_paths << File.join(config.root, "lib")
  end
end
