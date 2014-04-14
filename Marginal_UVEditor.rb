#
# UV Editor for SketchUp
#
# Copyright (c) 2014 Jonathan Harris
# 
# Mail: <x-plane@marginal.org.uk>
# Web:  http://marginal.org.uk/x-planescenery/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

require 'sketchup.rb'
require 'extensions.rb'

module Marginal
  module UVEditor

    Version = "0.10"

    # Debug
    TraceEvents = false

    extension = SketchupExtension.new('UVEditor', File.join(File.dirname(__FILE__), File.basename(__FILE__,'.rb'), 'loader.rb'))
'SU2XPlane.rb'
    extension.description = 'Texture UV map editor.'
    extension.version = Version
    extension.creator = 'Jonathan Harris'
    extension.copyright = '2014, Jonathan Harris. Licensed under GPLv2.'
    Sketchup.register_extension(extension, true)

  end
end
