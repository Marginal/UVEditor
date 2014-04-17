require 'sketchup.rb'
require File.join(File.dirname(__FILE__), 'utils.rb')

module Marginal
  module UVEditor

    def self.from_view
      
      model = Sketchup.active_model
      view = model.active_view
      selection = model.selection
      tl = view.corner(0)	# always [0,0] ?
      br = view.corner(3)

      mymaterial = material_from_selection(selection)
      return if !mymaterial
      basename = mymaterial.texture.filename.split(/[\/\\:]+/)[-1]	# basename which handles \ on Mac

      @@theeditor.remove_observers(model)
      model.start_operation('Project Texture', true)

      begin
        selection.each do |ent|
          if !ent.is_a?(Sketchup::Face)
            selection.toggle(ent)	# not interested in anything else
          elsif (!ent.material || !ent.material.texture || ent.material.texture.filename.split(/[\/\\:]+/)[-1]!=basename) && (!ent.back_material || !ent.back_material.texture || ent.back_material.texture.filename.split(/[\/\\:]+/)[-1]!=basename)
            selection.toggle(ent)	# doesn't use our texture
          else
            [true,false].each do |front|
              material = front ? ent.material : ent.back_material
              next if not material or not material.texture or material.texture.filename.split(/[\/\\:]+/)[-1]!=basename
              pos = []
              v = ent.outer_loop.vertices[0..3]	# can only set up to 4 vertices
              v.each do |vertex|
                pos << vertex
                pt = view.screen_coords(vertex)
                # p vertex, pt, [(pt.x-tl[0]) / (br[0]-tl[0]), 1 - (pt.y-tl[1]) / (br[1]-tl[1])]
                uv = point2UV(Geom::Point3d.new((pt.x-tl[0]) / (br[0]-tl[0]), 1 - (pt.y-tl[1]) / (br[1]-tl[1]), 1))
                pos << Geom::Point3d.new(uv[0], uv[1], 1)
              end
              ent.position_material(material, pos, front)
            end
          end
        end
        
        @@theeditor.install_observers(model)
        model.commit_operation
        @@theeditor.launch

      rescue => e
        puts "Error: #{e.inspect}", e.backtrace	# Report to console
        model.abort_operation
        @@theeditor.install_observers(model)
        UI::messagebox("Could not project all faces' UVs.\nTry with fewer faces selected.")
      end

    end

  end

end
