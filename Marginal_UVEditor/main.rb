require 'sketchup.rb'

module Marginal
  module UVEditor

    # one per model
    class UVObserver

      @@known_models = {}
      
      def self.Hello(model)
        if !@@known_models.include?(model)
          @@known_models[model] = Marginal::UVEditor::UVObserver.new(model)
        end
      end

      def self.GoodBye(model)
        fail if !@@known_models.include?(model)
        @@known_models.delete(model)
        Marginal::UVEditor::theeditor.goodbye(model)
      end

      def initialize(model)
        UVModelObserver.new(model)
        UVSelectionObserver.new(model)
      end

    end

    class UVModelObserver < Sketchup::ModelObserver

      def initialize(model)
        model.add_observer(self)
      end

      def onDeleteModel(model)
        # This doesn't fire on closing the model, so currently worthless. Maybe it will work in the future.
        # p "onDeleteModel #{model}"
        Marginal::UVEditor::UVObserver::GoodBye(model)
      end

      def onEraseAll(model)
        # Currently only works on Windows.
        # p "onEraseAll #{model}"
        Marginal::UVEditor::UVObserver::GoodBye(model)
      end

      def onTransactionStart(model)
        # p "onTransactionStart #{model}"
      end

      def onTransactionCommit(model)
        # p "onTransactionCommit #{model}"
        Marginal::UVEditor::theeditor.transaction()
      end

      def onTransactionRedo(model)
        # p "onTransactionRedo #{model}"
        Marginal::UVEditor::theeditor.transaction()
      end

      def onTransactionUndo(model)
        # p "onTransactionUndo #{model}"
        Marginal::UVEditor::theeditor.transaction()
      end

    end

    class UVSelectionObserver < Sketchup::SelectionObserver

      def initialize(model)
        model.selection.add_observer(self)
      end

      def onSelectionBulkChange(selection)
        # p 'onSelectionBulkChange ' + selection.inspect
        Marginal::UVEditor::theeditor.newselection(selection)
      end

      def onSelectionCleared(selection)
        # p 'onSelectionCleared ' + selection.inspect
        Marginal::UVEditor::theeditor.clearselection()
      end

    end


    # one per app
    class UVMain

      # Rounding for UV values
      Round = 8
      Factor = 10.0 ** UVMain::Round
      Inverse = 1/UVMain::Factor
 
      def initialize
        @dialog = nil
        @tw = Sketchup.create_texture_writer

        # currently active stuff
        @model = nil
        @mytransaction = false	# 
        @uvs = []		# [[u,v]]
        @facelookup = []	# uv index -> [originating Entity, side]
        @idxlookup = {}		# [Entity,side] -> [uv index]
      end

      def launch()
        # p 'launch'
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
        end
        # https://github.com/thomthom/sketchup-webdialogs-the-lost-manual/wiki/WebDialog.show-vs-WebDialog.show_modal
        RUBY_PLATFORM =~ /darwin/i ? @dialog.show_modal : @dialog.show
        @dialog.bring_to_front
      end

      def on_load
        # Remaining initialization, deferred 'til DOM is ready
        # p 'on_load'
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

        selection.each do |ent|
          if ent.typename == 'Face'	# not interested in anything else, and don't recurse into Components
            uvHelp = ent.get_UVHelper(true, true, @tw)
            [true,false].each do |front|
              material = front ? ent.material : ent.back_material
              next if not material or not material.texture
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
              usedmaterials[material] += poly.length
              polys << poly
              @idxlookup[[ent,front]] = poly
              #p "old: #{pos.inspect} #{front}"	# debug
            end
          end
        end

        # Determine most used material
        usedmaterials.delete(nil)
        return clearselection() if usedmaterials.empty?
        byuse = usedmaterials.invert
        mymaterial = byuse[byuse.keys.sort[-1]]	# most popular material
        return clearselection() if not mymaterial.texture

        # Ensure material's texture is available in the file system
        newfile = mymaterial.texture.filename
        if !File.file? newfile
          newfile = File.join(File.dirname(@model.path), mymaterial.texture.filename.split(/[\/\\:]+/)[-1])	# basename which handles \ on Mac
          if !File.file? newfile
            selection.each do |ent|
              if ent.typename == 'Face' and ent.material == mymaterial
                raise "Can't write #{newfile}" if @tw.load(ent, true)==0 || @tw.write(ent, true, newfile)!=0
                break
              end
            end
          end
        end

        @dialog.execute_script("document.getElementById('thetexture').src='file:///#{newfile.gsub('\\','/')}'; uvs=#{@uvs.inspect}; polys=#{polys.inspect}; restart()");
      end

      # a model is going away
      def goodbye(model)
        clearselection() if model==@model	# its our active model
      end

      # dialog about to be closed
      def on_close
        # p 'on_close ' + @dialog.inspect
        @dialog = nil
        clearselection()
      end

      # incoming!
      def on_startupdate
        # p 'on_startupdate' + @dialog.inspect
        return clearselection() if !@model.valid?	# we didn't notice that our model was closed on Mac
        @mytransaction = true
        @model.start_operation('Position Texture', false)
        @mytransaction = false
      end

      # incoming!
      def on_update
        # p 'on_update' + @dialog.inspect
        return clearselection() if !@model.valid?	# we didn't notice that our model was closed on Mac
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
          ent.position_material(ent.material, pos, front)
          #p "new: #{pos.inspect} #{front}"
        end
        @mytransaction = false
      end

      def on_cancelupdate
        # p 'on_cancelupdate' + @dialog.inspect
        @mytransaction = true
        @model.abort_operation if @model and @model.valid?
        @mytransaction = false
      end

      def on_finishupdate
        # p 'on_finishupdate' + @dialog.inspect
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


    if !file_loaded?(__FILE__)

      # one per app
      class UVAppObserver < Sketchup::AppObserver

        def initialize
          Sketchup.add_observer(self)
        end

        def onNewModel(model)
          # p 'onNewModel ' + model.inspect
          Marginal::UVEditor::UVObserver::Hello(model)
        end

        def onOpenModel(model)
          # onOpenModel can be called multiple times if the user re-opens the model from Explorer/Finder
          # p 'onOpenModel ' + model.inspect
          Marginal::UVEditor::UVObserver::Hello(model)
        end

      end

      # on[Open|New]Model not sent for initial model - http://www.sketchup.com/intl/en/developer/docs/ourdoc/appobserver#onOpenModel
      UVAppObserver.new.onOpenModel(Sketchup.active_model)
      
      # create a single instance and accessor for it
      @@theeditor = UVMain.new

      def self.theeditor
        @@theeditor
      end

      file_loaded(__FILE__)
    end

  end
end
