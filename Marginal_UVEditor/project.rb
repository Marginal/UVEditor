require 'sketchup.rb'
require File.join(File.dirname(__FILE__), 'utils.rb')

module Marginal
  module UVEditor

    def self.from_view
      
      model = Sketchup.active_model
      view = model.active_view
      selection = model.selection

      usedmaterials = Hash.new(0)
      mymaterial = material_from_selection(selection, usedmaterials)
      return if usedmaterials.empty?
      byuse = usedmaterials.invert
      mymaterial = byuse[byuse.keys.sort[-1]]	# most popular material

      tl = [ 1024*1024,  1024*1024]
      br = [-1024*1024, -1024*1024]
      bounds_from_view(selection, view, Geom::Transformation.new, tl, br)

      begin
        @@theeditor.remove_observers(model)
        model.start_operation('Project Texture', true)
        entities_from_view(selection.to_a, view, Geom::Transformation.new, tl, br, selection, mymaterial)	# convert selection to array since selection changes under SketchUp 2014
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

    def self.bounds_from_view(entities, view, trans, tl, br)
      entities.each do |ent|
        case ent
        when Sketchup::ComponentInstance
          bounds_from_view(ent.definition.entities, view, trans*ent.transformation, tl, br)
        when Sketchup::Group
          bounds_from_view(ent.entities, view, trans*ent.transformation, tl, br)
        when Sketchup::Face
          spt = ent.outer_loop.vertices.map { |v| view.screen_coords(trans * v.position) }
          tl[0] = (spt.map{ |s| s.x } << tl[0]).min
          tl[1] = (spt.map{ |s| s.y } << tl[1]).min
          br[0] = (spt.map{ |s| s.x } << br[0]).max
          br[1] = (spt.map{ |s| s.y } << br[1]).max
        end
      end
    end

    def self.entities_from_view(entities, view, trans, tl, br, selection, material)
      entities.each do |ent|
        case ent
        when Sketchup::ComponentInstance
          ent.material = nil
          entities_from_view(ent.definition.entities, view, trans*ent.transformation, tl, br, selection, material)
        when Sketchup::Group
          ent.material = nil
          entities_from_view(ent.entities, view, trans*ent.transformation, tl, br, selection, material)
        when Sketchup::Face
          ent.material = material
          ent.back_material = nil
          pos = []
          v = ent.outer_loop.vertices
          v.each_index do |i|
            pt = v[i].position
            next if pt.on_line?([v[i-1], v[(i+1)%v.length]])	# skip colinear points - can't do anything useful with them
            spt = view.screen_coords(trans * pt)
            uv = point2UV(Geom::Point3d.new((spt.x-tl[0]) / (br[0]-tl[0]), 1 - (spt.y-tl[1]) / (br[1]-tl[1]), 1))
            pos << pt
            pos << Geom::Point3d.new(uv[0], uv[1], 1)
          end
          pos = pos[0..7]	# can only set up to 4 vertices
          while true
            begin
              ent.position_material(material, pos, true)
              break
            rescue ArgumentError => e
              p pos	# Report to console
              pos = pos[0...-2]		# Try with fewer points
              raise e if pos.length<=0	# eh?
            end
          end
        when Sketchup::Edge
          # do nothing
        else
          selection.toggle(ent)	# not usable
        end
      end

    end

  end

end
