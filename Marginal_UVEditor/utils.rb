require 'sketchup.rb'

module Marginal
  module UVEditor

    # Rounding for UV values
    Round = 8
    Factor = 10.0 ** Round
    Inverse = 1/Factor

    # Convert a UV coordinate expressed as a Geom::Point3d to a simple tuple (well, Ruby doesn't do tuple, so actually array).
    def self.point2UV(p)
      return [(p.x*Factor).round * Inverse, (p.y*Factor).round * Inverse] if p.z==0	# eh?
      return [(p.x*Factor/p.z).round * Inverse, (p.y*Factor/p.z).round * Inverse]
    end

    # Determine most used material
    def self.material_from_selection(entities, usedmaterials)
      entities.each do |ent|
        case ent
        when Sketchup::ComponentInstance
          material_from_selection(ent.definition.entities, usedmaterials)
        when Sketchup::Group
          material_from_selection(ent.entities, usedmaterials)
        when Sketchup::Face
          [true,false].each do |front|
            material = front ? ent.material : ent.back_material
            if material and material.texture
              usedmaterials[material] += ent.outer_loop.vertices.length + (front ? 1 : 0)	# weight towards front
            end
          end
        end
      end
    end

  end
end
