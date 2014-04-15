require 'sketchup.rb'
require File.join(File.dirname(__FILE__), 'main.rb')

module Marginal
  module UVEditor

    if !file_loaded?(__FILE__)
      # reload main.rb in case user has installed an updated version
      UI.menu("Tools").add_item('UV Editor') { load File.join(File.dirname(__FILE__), 'main.rb'); @@theeditor.launch }
    end
    file_loaded(__FILE__)

  end
end
