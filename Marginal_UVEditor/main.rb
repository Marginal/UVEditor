require 'sketchup.rb'

module Marginal
  module UVEditor

    class UVModelObserver < Sketchup::ModelObserver

      def initialize(model)
        model.add_observer(self)
      end

      def remove(model)
        model.remove_observer(self)
        self
      end

      def onDeleteModel(model)
        # This doesn't fire on closing the model, so currently worthless. Maybe it will work in the future.
        p "onDeleteModel #{model}" if TraceEvents
        Marginal::UVEditor::theeditor.goodbye(model)
      end

      def onEraseAll(model)
        # Currently only works on Windows.
        p "onEraseAll #{model}" if TraceEvents
        Marginal::UVEditor::theeditor.goodbye(model)
      end

      def onTransactionStart(model)
        p "onTransactionStart #{model}" if TraceEvents
      end

      def onTransactionCommit(model)
        p "onTransactionCommit #{model}" if TraceEvents
        Marginal::UVEditor::theeditor.transaction()
      end

      def onTransactionRedo(model)
        p "onTransactionRedo #{model}" if TraceEvents
        Marginal::UVEditor::theeditor.transaction()
      end

      def onTransactionUndo(model)
        p "onTransactionUndo #{model}" if TraceEvents
        Marginal::UVEditor::theeditor.transaction()
      end

    end

    class UVSelectionObserver < Sketchup::SelectionObserver

      def initialize(model)
        model.selection.add_observer(self)
      end

      def remove(model)
        model.selection.remove_observer(self)
        self
      end

      def onSelectionBulkChange(selection)
        p 'onSelectionBulkChange ' + selection.inspect if TraceEvents
        Marginal::UVEditor::theeditor.newselection(selection)
      end

      def onSelectionCleared(selection)
        p 'onSelectionCleared ' + selection.inspect if TraceEvents
        Marginal::UVEditor::theeditor.clearselection()
      end

    end


    # one per app
    class UVMain < Sketchup::AppObserver
 
      def initialize
        @known_models = {}
        @model_observers = {}
        @selection_observers = {}

        @dialog = nil
        @tw = Sketchup.create_texture_writer

        # currently active stuff
        @model = nil
        @mytransaction = false	# 
        @uvs = []		# [[u,v]]
        @facelookup = []	# uv index -> [originating Entity, side]
        @idxlookup = {}		# [Entity,side] -> [uv index]

        Sketchup.add_observer(self)
        # on[Open|New]Model not sent for initial model - http://www.sketchup.com/intl/en/developer/docs/ourdoc/appobserver#onOpenModel
        onOpenModel(Sketchup.active_model)
      end

      def onNewModel(model)
        p 'onNewModel ' + model.inspect if TraceEvents
        if !@known_models.include?(model)
          @known_models[model] = true
          install_observers(model) if @dialog
        end
      end

      def onOpenModel(model)
        # onOpenModel can be called multiple times if the user re-opens the model from Explorer/Finder
        p 'onOpenModel ' + model.inspect if TraceEvents
        if !@known_models.include?(model)
          @known_models[model] = true
          install_observers(model) if @dialog
        end
      end

      def install_observers(model)
        if !model.valid?
          @known_models.delete(model)
          @model_observers.delete(model)
          @selection_observers.delete(model)
        else
          @model_observers[model] = UVModelObserver.new(model)
          @selection_observers[model] = UVSelectionObserver.new(model)
        end
      end

      def install_all_observers
        @known_models.keys.each { |model| install_observers(model) }
      end

      def remove_observers(model)
        if !model.valid?
          @known_models.delete(model)
          @model_observers.delete(model)
          @selection_observers.delete(model)
        else
          @model_observers.delete(model).remove(model)
          @selection_observers.delete(model).remove(model)
        end
      end

      def remove_all_observers
        @known_models.keys.each { |model| remove_observers(model) }
      end

      def launch()
        p 'launch' if TraceEvents
        if !@dialog
          # https://github.com/thomthom/sketchup-webdialogs-the-lost-manual/wiki/Sizing-Window
          if RUBY_PLATFORM =~ /darwin/i
            @dialog = UI::WebDialog.new('UV Editor', false, 'UVEditor', 512, 512 + 69 + 22)
          else
            @dialog = UI::WebDialog.new('UV Editor', false, 'UVEditor', 512 + 16, 512 + 69 + 38)	# default Win7
            @dialog.allow_actions_from_host("getfirebug.com")	# for debugging on Windows
          end
          @dialog.set_file(File.join(File.dirname(__FILE__), 'Resources', 'uveditor.html'))
          @dialog.add_action_callback("on_load")         { |d,p| on_load() }
          @dialog.add_action_callback("on_startupdate")  { |d,p| on_startupdate() }
          @dialog.add_action_callback("on_update")       { |d,p| on_update() }
          @dialog.add_action_callback("on_finishupdate") { |d,p| on_finishupdate() }
          @dialog.add_action_callback("on_cancelupdate") { |d,p| on_cancelupdate() }
          @dialog.set_on_close { on_close() }
          install_all_observers()
        end
        # https://github.com/thomthom/sketchup-webdialogs-the-lost-manual/wiki/WebDialog.show-vs-WebDialog.show_modal
        RUBY_PLATFORM =~ /darwin/i ? @dialog.show_modal : @dialog.show
        @dialog.bring_to_front
      end

      def on_load
        # Remaining initialization, deferred 'til DOM is ready
        p 'on_load' if TraceEvents
        if Sketchup.active_model.selection.empty?
          clearselection()
        else
          newselection(Sketchup.active_model.selection)
        end
      end

      def clearselection
        @model = nil
        @mytransaction = false
        @uvs = []
        @facelookup = []
        @idxlookup = {}
        @dialog.execute_script('clear()') if @dialog
      end

      def newselection(selection)
        @model = nil
        @mytransaction = false
        @uvs = []
        @facelookup = []
        @idxlookup = {}
        return if !@dialog

        @model = selection.model
        facedata = {}
        usedmaterials = Hash.new(0)
        uvlookup = {}
        polys = []

        # Determine most used material
        selection.each do |ent|
          if ent.typename == 'Face'	# not interested in anything else, and don't recurse into Components
            [true,false].each do |front|
              material = front ? ent.material : ent.back_material
              if material and material.texture
                usedmaterials[material] += ent.outer_loop.vertices.length + (front ? 1 : 0)	# weight towards front
              end
            end
          end
        end
        return clearselection() if usedmaterials.empty?
        byuse = usedmaterials.invert
        mymaterial = byuse[byuse.keys.sort[-1]]	# most popular material

        # Ensure material's texture is available in the file system
        newfile = mymaterial.texture.filename
        basename = mymaterial.texture.filename.split(/[\/\\:]+/)[-1]	# basename which handles \ on Mac
        if !File.file?(newfile) || newfile==basename	# doesn't exist or unqualified
          newfile = File.join(File.dirname(@model.path), basename)
          if !File.file? newfile
            selection.each do |ent|
              if ent.typename == 'Face' and ent.material == mymaterial
                raise "Can't write #{newfile}" if @tw.load(ent, true)==0 || @tw.write(ent, true, newfile)!=0
                break
              elsif ent.typename == 'Face' and ent.back_material == mymaterial
                raise "Can't write #{newfile}" if @tw.load(ent, false)==0 || @tw.write(ent, false, newfile)!=0
                break
              end
            end
          end
        end

        selection.each do |ent|
          if ent.typename != 'Face'
            # selection.toggle(ent)	# not interested in anything else
          elsif (!ent.material || !ent.material.texture || ent.material.texture.filename.split(/[\/\\:]+/)[-1]!=basename) && (!ent.back_material || !ent.back_material.texture || ent.back_material.texture.filename.split(/[\/\\:]+/)[-1]!=basename)
            # selection.toggle(ent)	# doesn't use our texture
          else
            uvHelp = ent.get_UVHelper(true, true, @tw)
            [true,false].each do |front|
              material = front ? ent.material : ent.back_material
              next if not material or not material.texture or material.texture.filename.split(/[\/\\:]+/)[-1]!=basename
              poly = []
              #pos = []	# debug
              ent.outer_loop.vertices.each do |vertex|
                uv = Point2UV(front ? uvHelp.get_front_UVQ(vertex.position) : uvHelp.get_back_UVQ(vertex.position))
                idx = uvlookup[uv]
                if !idx
                  idx = uvlookup[uv] = @uvs.length
                  @uvs << uv
                  @facelookup << []
                end
                poly << idx
                @facelookup[idx] << [ent,front]
                #pos << vertex	# debug
                #pos << uv	# debug
              end
              polys << poly
              @idxlookup[[ent,front]] = poly
              #p "old: #{pos.inspect} #{front}"	# debug
            end
          end
        end

        url = 'file:///' + newfile.gsub('%','%25').gsub(';','%3B').gsub('?','%3F').gsub('\\','/')	# minimal escaping
        @dialog.execute_script("document.getElementById('thetexture').src='#{url}'; uvs=#{@uvs.inspect}; polys=#{polys.inspect}; restart()");
      end

      # a model is going away
      def goodbye(model)
        clearselection() if model==@model	# its our active model
        remove_observers(model)
        @known_models.delete(model)
      end

      # dialog about to be closed
      def on_close
        p 'on_close ' + @dialog.inspect if TraceEvents
        remove_all_observers()
        @dialog = nil
        clearselection()
      end

      # incoming!
      def on_startupdate
        p 'on_startupdate' + @dialog.inspect if TraceEvents
        if !@model.valid?	# we didn't notice that our model was closed on Mac
          remove_observers(@model)
          clearselection()
          return
        end
        @mytransaction = true
        @model.start_operation('Position Texture', false)
        @mytransaction = false
      end

      # incoming!
      def on_update
        p 'on_update' + @dialog.inspect if TraceEvents
        @mytransaction = true
        update_uvs = eval(@dialog.get_element_value('update_uvs'))
        selection = {}	# selected faces
        eval(@dialog.get_element_value('update_selection')).each_with_index do |idx,i|
          @uvs[idx] = update_uvs[i];
          @facelookup[idx].each{ |x| selection[x] = true }
        end
        selection.keys.each do | ent,front |
          pos = []
          v = ent.outer_loop.vertices[0..3]	# can only set up to 4 vertices
          indices = @idxlookup[[ent,front]]	# [Entity,side] -> [uv index]
          v.each_index do |i|
            pos << v[i]
            uv = @uvs[indices[i]]
            pos << Geom::Point3d.new(uv[0],uv[1],1)
          end
          ent.position_material(front ? ent.material : ent.back_material, pos, front)
          #p "new: #{pos.inspect} #{front}"
        end
        @mytransaction = false
      end

      def on_cancelupdate
        p 'on_cancelupdate' + @dialog.inspect if TraceEvents
        @mytransaction = true
        @model.abort_operation if @model and @model.valid?
        @mytransaction = false
      end

      def on_finishupdate
        p 'on_finishupdate' + @dialog.inspect if TraceEvents
        return clearselection() if !@model.valid?	# we didn't notice that our model was closed on Mac
        @mytransaction = true
        @model.commit_operation
        @mytransaction = false
      end

      # something changed in a model
      def transaction
        if @model and @model.valid? and !@mytransaction	# its our model and it wasn't caused by us
          on_load()
        end
      end
        
      # Convert a UV coordinate expressed as a Geom::Point3d to a simple tuple (well, Ruby doesn't do tuple, so actually array).
      def Point2UV(p)
        return [(p.x*Factor/p.z).round * Inverse, (p.y*Factor/p.z).round * Inverse]
      end

    end


    # one-time initialisation
    if !file_loaded?(__FILE__)

      # Rounding for UV values
      Round = 8
      Factor = 10.0 ** Round
      Inverse = 1/Factor

      # create a single instance and accessor for it
      @@theeditor = UVMain.new

      def self.theeditor
        @@theeditor
      end

      file_loaded(__FILE__)
    end

  end
end
