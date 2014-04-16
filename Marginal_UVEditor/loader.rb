require 'sketchup.rb'
require File.join(File.dirname(__FILE__), 'main.rb')

module Marginal
  module UVEditor

    if !file_loaded?(__FILE__)
      # reload main.rb in case user has installed an updated version
      cmd = UI::Command.new("UV Editor") { load File.join(File.dirname(__FILE__), 'main.rb'); @@theeditor.launch }
      cmd.large_icon = File.join(File.dirname(__FILE__), 'Resources', 'UVEditor_24.png')
      cmd.small_icon = File.join(File.dirname(__FILE__), 'Resources', 'UVEditor_16.png')
      cmd.status_bar_text = "Edit selected faces' texture coordinates in a UV Editor window."
      cmd.tooltip = 'UV Editor window'

      UI.menu("Tools").add_item(cmd)
      UI::Toolbar.new("UV Editor").add_item(cmd)	# have to create a toolbar to make button available

      file_loaded(__FILE__)
    end

  end
end
