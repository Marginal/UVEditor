require 'sketchup.rb'
require File.join(File.dirname(__FILE__), 'main.rb')

module Marginal
  module UVEditor

    if !file_loaded?(__FILE__)
      UI.menu("Tools").add_item('UV Editor') { p "launch #{@@theeditor.launch}" }
    end
    file_loaded(__FILE__)

  end
end
