require 'sketchup.rb'
require File.join(File.dirname(__FILE__), 'utils.rb')

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

      # def onTransactionStart(model)
      #   p "onTransactionStart #{model}" if TraceEvents
      # end

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
        Marginal::UVEditor::theeditor.new_selection(selection)
      end

      def onSelectionCleared(selection)
        p 'onSelectionCleared ' + selection.inspect if TraceEvents
        Marginal::UVEditor::theeditor.clear_selection()
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
          install_observers(model)
        end
      end

      def onOpenModel(model)
        # onOpenModel can be called multiple times if the user re-opens the model from Explorer/Finder
        p 'onOpenModel ' + model.inspect if TraceEvents
        if !@known_models.include?(model)
          @known_models[model] = true
          install_observers(model)
        end
      end

      def install_observers(model)
        if !model || !model.valid?
          @known_models.delete(model)
          @model_observers.delete(model)
          @selection_observers.delete(model)
        elsif @dialog && !@model_observers[model]
          @model_observers[model] = UVModelObserver.new(model)
          @selection_observers[model] = UVSelectionObserver.new(model)
        end
      end

      def install_all_observers
        @known_models.keys.each { |model| install_observers(model) }
      end

      def remove_observers(model)
        if !model || !model.valid?
          @known_models.delete(model)
          @model_observers.delete(model)
          @selection_observers.delete(model)
        else
          o = @model_observers.delete(model)
          o.remove(model) if o
          o = @selection_observers.delete(model)
          o.remove(model) if o
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
          @dialog.add_action_callback("on_projview")     { |d,p| on_projview() }
          @dialog.add_action_callback("on_export")       { |d,p| on_export() }
          @dialog.add_action_callback("on_help")         { |d,p| on_help() }
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
          clear_selection()
        else
          new_selection(Sketchup.active_model.selection)
        end
      end

      def clear_selection
        @model = nil
        @uvs = []
        @facelookup = []
        @idxlookup = {}
        @dialog.execute_script('clear()') if @dialog
      end

      def new_selection(selection)
        @model = nil
        @uvs = []
        @facelookup = []
        @idxlookup = {}
        return if !@dialog

        @model = selection.model
        facedata = {}
        uvlookup = {}
        polys = []

        mymaterial = Marginal::UVEditor.material_from_selection(selection)
        return clear_selection() if !mymaterial

        # Ensure material's texture is available in the file system
        newfile = mymaterial.texture.filename
        basename = mymaterial.texture.filename[/[^\/\\]+$/]	# basename which handles \ on Mac
        if !File.file?(newfile) || newfile==basename	# doesn't exist or unqualified
          newfile = File.join(File.dirname(@model.path), basename)
          if !File.file? newfile
            selection.each do |ent|
              if ent.is_a?(Sketchup::Face) and ent.material == mymaterial
                raise "Can't write #{newfile}" if @tw.load(ent, true)==0 || @tw.write(ent, true, newfile)!=0
                break
              elsif ent.is_a?(Sketchup::Face) and ent.back_material == mymaterial
                raise "Can't write #{newfile}" if @tw.load(ent, false)==0 || @tw.write(ent, false, newfile)!=0
                break
              end
            end
          end
        end

        selection.each do |ent|
          if !ent.is_a?(Sketchup::Face)
            # selection.toggle(ent)	# not interested in anything else
          elsif (!ent.material || !ent.material.texture || ent.material.texture.filename[/[^\/\\]+$/]!=basename) && (!ent.back_material || !ent.back_material.texture || ent.back_material.texture.filename[/[^\/\\]+$/]!=basename)
            # selection.toggle(ent)	# doesn't use our texture
          else
            uvHelp = ent.get_UVHelper(true, true, @tw)
            [true,false].each do |front|
              material = front ? ent.material : ent.back_material
              next if not material or not material.texture or material.texture.filename[/[^\/\\]+$/]!=basename
              poly = []
              #pos = []	# debug
              v = ent.outer_loop.vertices
              v.each_index do |i|
                pt = v[i].position
                next if pt.on_line?([v[i-1], v[(i+1)%v.length]])	# skip colinear points - can't do anything useful with them
                uv = Marginal::UVEditor.point2UV(front ? uvHelp.get_front_UVQ(pt) : uvHelp.get_back_UVQ(pt))
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

        url = 'file:///' + newfile.gsub('%','%25').gsub("'",'%27').gsub(';','%3B').gsub('?','%3F').gsub('\\','/')	# minimal escaping
        @dialog.execute_script("document.getElementById('thetexture').src='#{url}'; uvs=#{@uvs.inspect}; polys=#{polys.inspect}; restart()");
      end

      # a model is going away
      def goodbye(model)
        clear_selection() if model==@model	# its our active model
        remove_observers(model)
        @known_models.delete(model)
      end

      # dialog about to be closed
      def on_close
        p 'on_close ' + @dialog.inspect if TraceEvents
        remove_all_observers()
        @dialog = nil
        clear_selection()
      end

      # incoming!
      def on_startupdate
        p 'on_startupdate' + @dialog.inspect if TraceEvents
        remove_observers(@model)
        if !@model.valid?	# we didn't notice that our model was closed on Mac
          return clear_selection()
        end
        @model.start_operation('Position Texture', false)
      end

      # incoming!
      def on_update
        p 'on_update' + @dialog.inspect if TraceEvents
        update_uvs = eval(@dialog.get_element_value('update_uvs'))
        selection = {}	# selected faces
        eval(@dialog.get_element_value('update_selection')).each_with_index do |idx,i|
          @uvs[idx] = update_uvs[i];
          @facelookup[idx].each{ |x| selection[x] = true }
        end
        selection.keys.each do | ent,front |
          pos = []
          indices = @idxlookup[[ent,front]]	# [Entity,side] -> [uv index]
          v = ent.outer_loop.vertices
          j = 0
          v.each_index do |i|
            pt = v[i].position
            next if pt.on_line?([v[i-1], v[(i+1)%v.length]])	# skip colinear points - can't do anything useful with them
            pos << pt
            uv = @uvs[indices[j]]
            pos << Geom::Point3d.new(uv[0],uv[1],1)
            j+=1
          end
          begin
            ent.position_material(front ? ent.material : ent.back_material, pos[0..7], front)
          rescue => e
            # silently ignore failure to project
            puts "Error: #{e.inspect} #{pos[0..7].inspect}", e.backtrace	# Report to console
          end
          #p "new: #{pos.inspect} #{front}"
        end
      end

      def on_cancelupdate
        p 'on_cancelupdate' + @dialog.inspect if TraceEvents
        @model.abort_operation if @model and @model.valid?
        install_observers(@model)
      end

      def on_finishupdate
        p 'on_finishupdate' + @dialog.inspect if TraceEvents
        return clear_selection() if !@model.valid?	# we didn't notice that our model was closed on Mac
        @model.commit_operation
        install_observers(@model)
      end

      # something changed in a model
      def transaction
        if @model and @model.valid?	# its our model
          on_load()
        end
      end

      def on_projview
        p 'on_projview' if TraceEvents
        Marginal::UVEditor::from_view
      end

      def on_export
        p 'on_export' if TraceEvents
        filename = UI::savepanel("Export UV layout", File.dirname(@model.path), "UV_layout.png")
        if filename
          File.open(filename, 'wb') {|f| f.write(@dialog.get_element_value('export_data').unpack('m')[0]) }
        end
      end

      def on_help
        p 'on_help' if TraceEvents
        Marginal::UVEditor::help
      end
        
    end


    # one-time initialisation
    if !file_loaded?(__FILE__)

      # create a single instance and accessor for it
      @@theeditor = UVMain.new

      def self.theeditor
        @@theeditor
      end

      file_loaded(__FILE__)
    end

  end
end
