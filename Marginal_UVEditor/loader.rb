require 'sketchup.rb'
require File.join(File.dirname(__FILE__), 'main.rb')
require File.join(File.dirname(__FILE__), 'project.rb')

module Marginal
  module UVEditor

    if !file_loaded?(__FILE__)
      # reload main.rb in case user has installed an updated version
      cmd_win = UI::Command.new("UV Editor") { load File.join(File.dirname(__FILE__), 'main.rb'); @@theeditor.launch }
      cmd_win.large_icon = File.join(File.dirname(__FILE__), 'Resources', 'UVEditor_24.png')
      cmd_win.small_icon = File.join(File.dirname(__FILE__), 'Resources', 'UVEditor_16.png')
      cmd_win.status_bar_text = "Edit selected faces' texture coordinates in a UV Editor window."
      cmd_win.tooltip = 'UV Editor window'

      cmd_proj_view = UI::Command.new("Project UVs from View") { load File.join(File.dirname(__FILE__), 'project.rb'); from_view }
      cmd_proj_view.large_icon = File.join(File.dirname(__FILE__), 'Resources', 'ProjView_24.png')
      cmd_proj_view.small_icon = File.join(File.dirname(__FILE__), 'Resources', 'ProjView_16.png')
      cmd_proj_view.status_bar_text = "Project selected faces' texture coordinates from current view."
      cmd_proj_view.tooltip = 'Project UVs from View'

      UI.menu("Tools").add_item(cmd_win)

      tb = UI::Toolbar.new("UV Editor")
      tb.add_item(cmd_win)
      tb.add_item(cmd_proj_view)
      if tb.get_last_state!=0
        tb.restore
        UI.start_timer(0.2, false) { tb.restore }	# http://sketchucation.com/forums/viewtopic.php?p=269734#p269734
      end

      file_loaded(__FILE__)
    end

  end
end
