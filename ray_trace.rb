module Wave_Trace
	
    class RayTracePage	
        attr_accessor :window
        attr_accessor :current_speaker
        attr_accessor :speaker_list
        attr_accessor :tool
        attr_accessor :place_driver_label
        attr_accessor :mark_ignore_label
        attr_accessor :mark_ignore_label2
        attr_accessor :mark_ignore_target_label
        attr_accessor :mark_ignore_target_highlight
        attr_accessor :mark_ignore_update_label
        attr_accessor :mark_ignore_update_check
        attr_accessor :tool_button
        attr_accessor :draw_realtime_check
        attr_accessor :max_length_drop
        attr_accessor :max_bounces_drop
        attr_accessor :bounce_hidden_check
        attr_accessor :bounce_filter_drop
        attr_accessor :realtime_label
        attr_accessor :commit_label
        attr_accessor :delete_button
        attr_accessor :win_open

        unless file_loaded?('wave_trace.rb')
            BUTTON_SPACING = 5
            START_X = 40
            START_Y = 50
            MOVE_LEFT = 1
            MOVE_RIGHT = 2
        end
        
        
        # Save all speaker settings to attribute dictionary within the model, for later recall
        def save_settings
            dir = 'Wave_Trace'
            model = Sketchup.active_model
            model.start_operation('Wave_Trace: Save All Settings', true) # Start an undo-able operation
            model.attribute_dictionaries.delete(dir) # First delete any pre-existing Wave_Trace dictionary
            
            model.set_attribute(dir, 'draw_realtime', @draw_realtime_check.checked?)
            model.set_attribute(dir, 'bounce_hidden', @bounce_hidden_check.checked?)
            model.set_attribute(dir, 'max_length', @max_length_drop.value)
            model.set_attribute(dir, 'use_barrier', @use_barrier_check.checked?)
            model.set_attribute(dir, 'max_bounces', @max_bounces_drop.value)
            model.set_attribute(dir, 'bounce_filter', @bounce_filter_drop.value)
            model.set_attribute(dir, 'draw_sweetspot', @draw_sweetspot_check.checked?)
            
            @speaker_list.each do |speaker|
                # Name each speaker after its index location in speaker_list... "s_1" "s_2" etc
                speaker_key = "s_#{speaker_list.index(speaker).to_s}" 
                speaker_value = {
                    name: speaker.button.caption,
                    realtime_check: speaker.realtime_check.checked?,
                    commit_check: speaker.commit_check.checked?,
                    group_num: speaker.group_num
                }
                # Store the speaker settings as a string
                model.set_attribute(dir, speaker_key, speaker_value.inspect) 
            
                speaker.driver_list.each do |driver|
                    # Name driver index s_1_d_1, s_1_d_2 etc                
                    driver_key = "#{speaker_key}_d_#{speaker.driver_list.index(driver).to_s}"
                    driver_value = {
                        name: driver.name_field.value,
                        origin: driver.origin.to_a,
                        vector: driver.vector.to_a,
                        x_angle_low: driver.x_angle_low_drop.value,
                        x_angle_high: driver.x_angle_high_drop.value,
                        y_angle_low: driver.y_angle_low_drop.value,
                        y_angle_high: driver.y_angle_high_drop.value,
                        x_angle_link: driver.x_angle_link_check.checked?,
                        y_angle_link: driver.y_angle_link_check.checked?,
                        density: driver.density_drop.value,
                        ray_list: driver.ray_list,
                        realtime_check: driver.realtime_check.checked?,
                        commit_check: driver.commit_check.checked?
                    }
                    # Store the driver settings as a string
                    model.set_attribute(dir, driver_key, driver_value.inspect)
                end
            end
            
            # FIX - Save global options too
            
            model.commit_operation # End undo-able operation
            UI.messagebox("              Important!\n\nAll speakers, drivers and global settings have been stored in your model. You must SAVE YOUR MODEL for these settings to persist.", MB_OK)
        end
        
        
        # Load all speakers from attribute dicionary and return a speaker_index list
        def load_settings
            dir = 'Wave_Trace'
            
            dict = Sketchup.active_model.attribute_dictionary(dir)
            return if !dict # No saved settings

            # Set the global options
            @draw_realtime_check.checked = dict['draw_realtime']
            @bounce_hidden_check.checked = dict['bounce_hidden']
            @max_length_drop.value = dict['max_length']
            @use_barrier_check.checked = dict['use_barrier']
            @max_bounces_drop.value = dict['max_bounces']
            @bounce_filter_drop.value = dict['bounce_filter']
            @draw_sweetspot_check.checked = dict['draw_sweetspot']
            
            # Now load any speaker settings
            s_index = 0
            while(speaker_str = dict["s_#{s_index}"]) # There is a saved speaker at s_x in attribute dictionary
                
                # Create a speaker and set its values according to the saved information
                speaker_hash = eval(speaker_str)
                speaker = self.add_speaker(true) # Add a speaker with the 'loading' option set to TRUE (avoids creating any drivers)
                        
                speaker.name_field.value = speaker_hash[:name]
                speaker.name_field.trigger_event(:textchange)
                                                
                speaker.realtime_check.checked = speaker_hash[:realtime_check]
                speaker.commit_check.checked = speaker_hash[:commit_check]
                speaker.group_num = speaker_hash[:group_num]
                # Set the link_to_group droplist value to whatever the group_num index is. Then set a color if there is a group.
                speaker.link_to_group_drop.value = speaker.link_to_group_drop.items[speaker.group_num] if speaker.group_num
                case speaker.group_num
                when 1
                    speaker.group_highlight.background_color = Sketchup::Color.new(128,0,0,255) # Red
                when 2
                    speaker.group_highlight.background_color = Sketchup::Color.new(0,128,0,255) # Green
                when 3
                    speaker.group_highlight.background_color = Sketchup::Color.new(128,128,0,255) # Yellow
                when 4
                    speaker.group_highlight.background_color = Sketchup::Color.new(200,200,200,255) # White
                end
                            
                d_index = 0
                while(driver_str = dict["s_#{s_index}_d_#{d_index}"]) # There is a saved driver at s_x_d_x in attribute dictionary
                    # Create a driver and set its values according to the saved information
                    driver_hash = eval(driver_str)
                    driver = speaker.add_driver(true) # Add a driver with the 'loading' option set to TRUE (avoids any group settings logic)
                                                        
                    driver.name_field.value = driver_hash[:name]
                    driver.name_field.trigger_event(:textchange)

                    origin_array = driver_hash[:origin]
                    vector_array = driver_hash[:vector]
                    if origin_array.empty? # No saved origin... it was never set
                        driver.origin = nil
                        driver.vector = nil
                    else # Found an origin... so there has to be a vector as well. Load both and change "locate driver" button to reflect such.
                        driver.origin = Geom::Point3d.new(origin_array)
                        driver.vector = Geom::Vector3d.new(vector_array)
                        driver.locate_button.background_color = Sketchup::Color.new(0, 0, 0, 128) # Un-highlight locate_button
                        driver.locate_button.caption = "Relocate" # Change its caption
                    end
                    
                    driver.realtime_check.checked = driver_hash[:realtime_check]
                    driver.commit_check.checked = driver_hash[:commit_check]
                    
                    driver.density_drop.trigger_event(:change, driver_hash[:density], true) # Call the density change to update angle droplists
                    driver.x_angle_low_drop.value = driver_hash[:x_angle_low]
                    driver.x_angle_high_drop.value = driver_hash[:x_angle_high]
                    driver.y_angle_low_drop.value = driver_hash[:y_angle_low]
                    driver.y_angle_high_drop.value = driver_hash[:y_angle_high]
                    driver.x_angle_link_check.checked = driver_hash[:x_angle_link]
                    driver.y_angle_link_check.checked = driver_hash[:y_angle_link]
                    driver.ray_list = driver_hash[:ray_list]
                                    
                    d_index += 1
                end
                s_index += 1
            end
        
            self.select_speaker(@speaker_list.first) if speaker_list.length > 0
        end
                
        
        def try_load
            return if @tried_to_load # Already tried to load settings once when the window first signalled it was ready. Abort.
            
            @tried_to_load = true
            self.load_settings
        end
        
        
        def highlight_mute # Workaround to keep new buttons from having focus highlight
            @window.remove_control(@dummy_button) if @dummy_button	
            @dummy_button = SKUI::Button.new('')   
            @dummy_button.width = 0
            @dummy_button.height = 0
            @dummy_button.position(0,0)
            @dummy_button.visible = true
            @window.add_control(@dummy_button)
        end
            
            
            
        def initialize(window)
            @window = window
            @win_open = false
            @tool = Wave_Trace::Wave_Trace_Raycast_Tool.new(self)
            Sketchup.active_model.select_tool(@tool) # This tool will handle all of the various display / assignment duties
            
            @current_speaker = nil
            @speaker_list = []
            @dummy_button = nil
            @tried_to_load = false # Once the window object is ready it will call try_load(), which will attempt to load speakers and set this true
                    
            self.highlight_mute
            
            #### Global menu 
            @global_menu_background = SKUI::Container.new
            @global_menu_background.width = 800
            @global_menu_background.height = 80
            @global_menu_background.position(0, RAY_PAGE_OFFSET)
            @global_menu_background.background_color = Sketchup::Color.new(0, 0, 0, 128)
            @global_menu_background.visible = true
            @window.add_control(@global_menu_background)
            
            @add_button = SKUI::Button.new('Add Speaker') { |control| self.add_speaker }
            @add_button.width = 85
            @add_button.position(-5, (28 + RAY_PAGE_OFFSET))
            @add_button.background_color = Sketchup::Color.new(128, 0, 0, 192)
            @window.add_control(@add_button)
                    
            @delete_button = SKUI::Button.new('Delete Current') { |control| self.delete_speaker }
            @delete_button.width = 100
            @delete_button.position(-95, (28 + RAY_PAGE_OFFSET))
            @delete_button.visible = false
            @window.add_control(@delete_button)
            
            @please_add_label = Wave_Trace::gui_create_label('Please add a speaker to get started...', 325, (330 + RAY_PAGE_OFFSET), true)
            @window.add_control(@please_add_label)		
            
                    
            @realtime_label = Wave_Trace::gui_create_label('Realtime:', 2, (80 + SPEAKER_PAGE_OFFSET), false)
            @window.add_control(@realtime_label)
            
            @commit_label = Wave_Trace::gui_create_label('Commit:', 2, (100 + SPEAKER_PAGE_OFFSET), false)
            @window.add_control(@commit_label)
            
            @speaker_name_label = Wave_Trace::gui_create_label('Speaker Name', 355, (125 + SPEAKER_PAGE_OFFSET), false)
            @speaker_name_label.font = SKUI::Font.new(nil, 9)
            @window.add_control(@speaker_name_label)			

            @place_driver_label = Wave_Trace::gui_create_label("Please locate the driver on a face...", 20, 20, false)
            @window.add_control(@place_driver_label)
            
            @mark_ignore_label = Wave_Trace::gui_create_label("Please select objects for rays to ignore...", 30, 20, false)
            @window.add_control(@mark_ignore_label)
                    
            @mark_ignore_label2 = Wave_Trace::gui_create_label("Object ignore status:", 15, 66, false)
            @window.add_control(@mark_ignore_label2)
                            
            @mark_ignore_target_highlight = SKUI::Container.new
            @mark_ignore_target_highlight.visible = true
            @mark_ignore_target_highlight.background_color = Sketchup::Color.new(0, 0, 0, 0)
            @mark_ignore_target_highlight.width = 83
            @mark_ignore_target_highlight.height = 25
            @mark_ignore_target_highlight.position(138, 61)
            @window.add_control(@mark_ignore_target_highlight)
            
            @mark_ignore_target_label = Wave_Trace::gui_create_label('', 160, 68, false)
            @window.add_control(@mark_ignore_target_label)
            
            @mark_ignore_update_label = Wave_Trace::gui_create_label('Auto-update ALL rays when finished?', 15, 108, false)
            @window.add_control(mark_ignore_update_label)
            
            @mark_ignore_update_check = SKUI::Checkbox.new('', true)
            @mark_ignore_update_check.position(224, 108)
            @mark_ignore_update_check.visible = false
            @window.add_control(@mark_ignore_update_check)
                    
            @tool_button = SKUI::Button.new("Cancel") { |control| self.tool.set_state(STATE_IDLE) ; Sketchup.active_model.active_view.invalidate }
            @tool_button.width = 84
            @tool_button.position(78, 60)
            @tool_button.visible = false
            @window.add_control(@tool_button)
                
            @draw_realtime_label = Wave_Trace::gui_create_label("Draw realtime ray previews", 2, (2 + RAY_PAGE_OFFSET), true)
            @draw_realtime_label.tooltip = "If checked, all speakers and subsequent drivers that have their individual \"Realtime\" / \"R\" also checked" +
                                            " will be drawn in realtime via OpenGL calls. No geometry is created."
            #@draw_realtime_label.font = SKUI::Font.new(nil, 12)
            @window.add_control(@draw_realtime_label)
            
            @draw_realtime_check = SKUI::Checkbox.new('', true)
            @draw_realtime_check.position(72, (21 + RAY_PAGE_OFFSET))
            @draw_realtime_check.on(:change) { |control| control.checked? ; Sketchup.active_model.active_view.invalidate }
            @window.add_control(@draw_realtime_check)
            
            @max_length_label = Wave_Trace::gui_create_label("Max ray length (ft)", 162, (2 + RAY_PAGE_OFFSET), true)
            @max_length_label.tooltip = "The maximum length, in feet, that any individual ray can be."
            @window.add_control(@max_length_label)
            
            @max_length_drop = SKUI::Listbox.new(%w{1 2 3 4 5 7.5 10 15 20 25 30 35 40 45 50 75 100 150 200 300 400 500 1000})
            @max_length_drop.value = "10"
            @max_length_drop.position(183, (19 + RAY_PAGE_OFFSET))
            @max_length_drop.width = 55
            @max_length_drop.height = 18
            @max_length_drop.on(:change) { |control| @tool.update_all_drivers }
            @window.add_control(@max_length_drop)
            
            @max_bounces_label = Wave_Trace::gui_create_label("Max ray bounces", 277, (2 + RAY_PAGE_OFFSET), true)
            @max_bounces_label.tooltip = "The maximum amount of times that any individual ray can bounce."
            @window.add_control(@max_bounces_label)
            
            @max_bounces_drop = SKUI::Listbox.new(%w{0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 100 500 999})
            @max_bounces_drop.value = "1"
            @max_bounces_drop.position(300, (19 + RAY_PAGE_OFFSET))
            @max_bounces_drop.width = 45
            @max_bounces_drop.height = 18
            @max_bounces_drop.on(:change) { |control| @tool.update_all_drivers }
            @window.add_control(@max_bounces_drop)
            
            @bounce_filter_label = Wave_Trace::gui_create_label("Bounce filter (ft)", 382, (2 + RAY_PAGE_OFFSET), true)
            @bounce_filter_label.tooltip = "This will filter out any rays that bounce BEFORE (negative values) or AFTER (positive values) the" +
                                            " setting in feet."
            @window.add_control(@bounce_filter_label)
            
            @bounce_filter_drop = SKUI::Listbox.new(%w{-40 -35 -30 -25 -20 -17.5 -15 -12.5 -10 -7.5 -5 -3 -2 -1 Off
                                                    1 2 3 5 7.5 10 12.5 15 17.5 20 25 30 35 40 })
            @bounce_filter_drop.value = "Off"
            @bounce_filter_drop.position(402, (19 + RAY_PAGE_OFFSET))
            @bounce_filter_drop.width = 45
            @bounce_filter_drop.height = 18
            @bounce_filter_drop.on(:change) { |control| @tool.update_all_drivers }
            @window.add_control(@bounce_filter_drop)
                    
            @draw_sweetspot_label = Wave_Trace::gui_create_label("Create sweet spot", 483, (2 + RAY_PAGE_OFFSET), true)
            @draw_sweetspot_label.tooltip = "This will find the axis intersections within 15 degrees of any grouped pair of speakers and create a" +
                                            " highlighted area for both the realtime drawing and any geometry created. Only pairs are supported, on" +
                                            " a first-come first-serve basis... any additional speakers in the group will be ignored."
            @window.add_control(@draw_sweetspot_label)
            
            @draw_sweetspot_check = SKUI::Checkbox.new('', true)
            @draw_sweetspot_check.on(:change) { |control| control.checked? } # FIX - Draw a sweetspot!
            @draw_sweetspot_check.position(522, (21 + RAY_PAGE_OFFSET))
            @window.add_control(@draw_sweetspot_check)
            
            @bounce_hidden_label = Wave_Trace::gui_create_label("Bounce off hidden geometry", 2, (42 + RAY_PAGE_OFFSET), true)
            @bounce_hidden_label.tooltip = "This will cause rays to reflect off all geometry, hidden or not. Very useful if you'd like to hide objects" +
                                            " for visibility's sake (the roof, walls, console, etc) and not affect the ray's path."
            @window.add_control(@bounce_hidden_label)
            
            @bounce_hidden_check = SKUI::Checkbox.new('', false)
            @bounce_hidden_check.position(72, (61 + RAY_PAGE_OFFSET))
            @bounce_hidden_check.on(:change) { |control| control.checked? ; @tool.update_all_drivers }
            @window.add_control(@bounce_hidden_check)
            
            @use_barrier_label = Wave_Trace::gui_create_label("Stop rays at barrier", 172 , (42 + RAY_PAGE_OFFSET), true)
            @window.add_control(@use_barrier_label)
            
            @use_barrier_check = SKUI::Checkbox.new('', true)
            @use_barrier_check.on(:change) { |control| control.checked? } # FIX - Start barrier tool
            @use_barrier_check.position(214, (61 + RAY_PAGE_OFFSET))
            @window.add_control(@use_barrier_check)		
            
            @define_barrier_button = SKUI::Button.new("Define Barrier") { |control| @tool.set_state(STATE_DEFINE_BARRIER) 
                                                                        Sketchup.active_model.active_view.invalidate  }
            @define_barrier_button.width = 92
            @define_barrier_button.height = 20
            @define_barrier_button.position(238, (58 + RAY_PAGE_OFFSET))
            @window.add_control(@define_barrier_button)		

            @mark_ignore_button = SKUI::Button.new("Mark Objects to Ignore") { |control| @tool.set_state(STATE_MARK_IGNORE) 
                                                                                Sketchup.active_model.active_view.invalidate }
            @mark_ignore_button.width = 140
            @mark_ignore_button.position(358, (50 + RAY_PAGE_OFFSET))
            @window.add_control(@mark_ignore_button)
                    
            @vis_to_geom_button = SKUI::Button.new("Realtime to Geometry") { |control| self.vis_to_geom }
            @vis_to_geom_button.width = 125
            @vis_to_geom_button.position(-5, (55 + RAY_PAGE_OFFSET))
            @window.add_control(@vis_to_geom_button)
            
            @commit_to_geom_button = SKUI::Button.new("Commit to Geometry") { |control| self.commit_to_geom }
            @commit_to_geom_button.width = 125
            @commit_to_geom_button.position(-133, (55 + RAY_PAGE_OFFSET))
            @window.add_control(@commit_to_geom_button)
            
            @save_settings_button = SKUI::Button.new("Save Settings") { |control| self.save_settings }
            @save_settings_button.width = 100
            @save_settings_button.height = 20
            @save_settings_button.position(-5, (3 + RAY_PAGE_OFFSET))
            @window.add_control(@save_settings_button)
            
            @refresh_all_button = SKUI::Button.new("Refresh ALL Rays") { |control| @tool.update_all_drivers }
            @refresh_all_button.width = 120
            @refresh_all_button.height = 40
            @refresh_all_button.background_color = Sketchup::Color.new( 255, 228, 196, 100)
            @refresh_all_button.position(-10, (138 + SPEAKER_PAGE_OFFSET))
            @window.add_control(@refresh_all_button)
                    
            self.highlight_mute		
                    
            @static_elements = [@add_button, @delete_button, @realtime_label, @commit_label, @global_menu_background, @draw_realtime_label,
                                @draw_realtime_check, @max_length_label, @max_length_drop, @max_bounces_label, @max_bounces_drop, @bounce_filter_label,
                                @bounce_filter_drop, @draw_sweetspot_label, @draw_sweetspot_check, @bounce_hidden_label, @bounce_hidden_check,
                                @use_barrier_label, @use_barrier_check, @define_barrier_button, @mark_ignore_button, @vis_to_geom_button,
                                @commit_to_geom_button,	@save_settings_button, @please_add_label, @refresh_all_button]
        end
        
        
        def vis_to_geom
            # Calculate the workload
            num_rays = 0
            if @draw_realtime_check.checked? # There's nothing visible...
                speaker_list.each do |speaker|
                    next if !speaker.realtime_check.checked?
                    speaker.driver_list.each do |driver|
                        next if !driver.realtime_check.checked?
                        next if !driver.origin	
                        num_rays += driver.ray_list.length unless driver.ray_list.empty?
                    end
                end
            end
            
            if (num_rays == 0)
                UI.messagebox("No visible (Realtime) rays!", MB_OK)
                return
            end
        
            choice = UI.messagebox("This will convert all VISIBLE rays (Realtime / R) to actual model geometry.\n\nTotal rays to convert: #{num_rays}\n\n" +
                    "This process can take a while (minutes) if you have leaned towards any extreme settings (dense rays, long rays, etc).\n\n" +
                    "The status bar will cease updating in such cases, but work is still being done. I'll pop-up again and make a sound when finished...", MB_OKCANCEL)
            
            if choice == 2
                return
            end
                
            @window.set_size(0,0)	
                
            num_lines = 0
            Sketchup.active_model.start_operation('Wave_Trace: Create Geometry From Realtime Rays', true) # Create undo start
            speaker_list.each do |speaker|
                next if !speaker.realtime_check.checked?
                speaker.driver_list.each do |driver|
                    next if !driver.realtime_check.checked?
                    next if !driver.origin
                    next if driver.ray_list.length < 1
                    driver_group = Sketchup.active_model.active_entities.add_group
                    driver.ray_list.each do |point_list|
                        next if point_list.length < 6
                        ray_group = driver_group.entities.add_group
                        p_list = Array.new(point_list)
                        
                        ray_color = p_list.shift(3)
                        # Assign/Check if color material already exists... if it returns nil, add a new color
                        if !(ray_material = Sketchup.active_model.materials["Wave_Trace Ray Color R#{ray_color[0]} G#{ray_color[1]} B#{ray_color[2]}"])
                            ray_material = Sketchup.active_model.materials.add("Wave_Trace Ray Color R#{ray_color[0]} G#{ray_color[1]} B#{ray_color[2]}")
                            ray_material.color = Sketchup::Color.new(ray_color)
                        end
                        
                        # Drop the first 2 array values (unused alpha, unused line_width), add the ray origin to the beginning,
                        # then create edges from the entire point list. Finally, apply the color material to each edge.
                        edge_array = ray_group.entities.add_edges(p_list.drop(2).unshift(driver.origin)) # <-- You got all that???   =)
                        if edge_array && !edge_array.empty?
                            edge_array.each do |edge|
                                edge.material = ray_material
                            end
                        end
                        
                        # Add a point at the end of each ray.
                        ray_group.entities.add_cpoint(point_list.last)
                        
                        # Update the status bar with progress every 5 percent of the job finished.
                        if ( ( ( num_lines.to_f / num_rays ) * 100 ).to_i % 5 == 0 )
                            Sketchup.status_text = "Creating geometry... #{num_lines} of #{num_rays} rays converted to edges."
                        end
                        num_lines += 1
                    end
                end
            end
            Sketchup.active_model.commit_operation # Undo end
            Sketchup.status_text = nil
            @draw_realtime_check.checked = false
            @window.set_size(800,800)	
            Sketchup.active_model.active_view.invalidate
            UI.messagebox("All visible (Realtime) rays have been converted into model geometry.\n\nDraw Realtime Ray Previews has been toggled OFF.", MB_OK)
        end	
                            
        
        
        
        def commit_to_geom
            # Calculate the workload
            num_rays = 0
            speaker_list.each do |speaker|
                next if !speaker.commit_check.checked?
                speaker.driver_list.each do |driver|
                    next if !driver.commit_check.checked?
                    next if !driver.origin	
                    num_rays += driver.ray_list.length unless driver.ray_list.empty?
                end
            end
            
            if (num_rays == 0)
                UI.messagebox("No rays specified! (Toggle Commit / C)", MB_OK)
                return
            end
            
            
            choice = UI.messagebox("This will convert all specified rays (Commit / C) to actual model geometry.\n\nTotal rays to convert: #{num_rays}\n\n" +
                    "This process can take a while (minutes) if you have leaned towards any extreme settings (dense rays, long rays, etc).\n\n" +
                    "The status bar will cease updating in such cases, but work is still being done. I'll pop-up again and make a sound when finished...", MB_OKCANCEL)
            
            if choice == 2
                return
            end
                
            @window.set_size(0,0)	
                
            num_lines = 0
            Sketchup.active_model.start_operation('Wave_Trace: Create Geometry From Realtime Rays', true) # Create undo start
            speaker_list.each do |speaker|
                next if !speaker.commit_check.checked?
                speaker.driver_list.each do |driver|
                    next if !driver.commit_check.checked?
                    next if !driver.origin
                    next if driver.ray_list.length < 1
                    driver_group = Sketchup.active_model.active_entities.add_group
                    driver.ray_list.each do |point_list|
                        next if point_list.length < 6
                        ray_group = driver_group.entities.add_group
                        p_list = Array.new(point_list)
                        
                        ray_color = p_list.shift(3)
                        # Assign/Check if color material already exists... if it returns nil, add a new color
                        if !(ray_material = Sketchup.active_model.materials["Wave_Trace Ray Color R#{ray_color[0]} G#{ray_color[1]} B#{ray_color[2]}"])
                            ray_material = Sketchup.active_model.materials.add("Wave_Trace Ray Color R#{ray_color[0]} G#{ray_color[1]} B#{ray_color[2]}")
                            ray_material.color = Sketchup::Color.new(ray_color)
                        end
                        
                        # Drop the first 2 array values (unused alpha, unused line_width), add the ray origin to the beginning,
                        # then create edges from the entire point list. Finally, apply the color material to each edge.
                        edge_array = ray_group.entities.add_edges(p_list.drop(2).unshift(driver.origin)) # <-- You got all that???   =)
                        if edge_array && !edge_array.empty?
                            edge_array.each do |edge|
                                edge.material = ray_material
                            end
                        end
                        
                        # Add a point at the end of each ray.
                        ray_group.entities.add_cpoint(point_list.last)
                        
                        # Update the status bar with progress every 5 percent of the job finished.
                        if ( ( ( num_lines.to_f / num_rays ) * 100 ).to_i % 5 == 0 )
                            Sketchup.status_text = "Creating geometry... #{num_lines} of #{num_rays} rays converted to edges."
                        end
                        num_lines += 1
                    end
                end
            end
            Sketchup.active_model.commit_operation # Undo end
            Sketchup.status_text = nil
            @draw_realtime_check.checked = false
            @window.set_size(800,800)	
            Sketchup.active_model.active_view.invalidate
            UI.messagebox("All selected (Commit) rays have been converted into model geometry.\n\nDraw Realtime Ray Previews has been toggled OFF.", MB_OK)
        end
        
        
        def ready?
            return @win_open
        end
        
        # Move all of this to SpeakerPage::initialize...
        def add_speaker(loading = false)
            @add_button.background_color = Sketchup::Color.new(64, 64, 64, 64)
            base_name = "Speaker " + (@speaker_list.length + 1).to_s
            name = base_name
            duplicate_number = 2
            
            speaker_names = []
            @speaker_list.each do |speaker|
                speaker_names.push(speaker.button.caption)
            end
            
            while speaker_names.include?(name) do
                name = base_name + (" (" + duplicate_number.to_s + ")")	# Apply a unique name
                duplicate_number += 1
            end				
                    
            speaker = SpeakerPage.new(self, @window, @speaker_list)
            speaker.button = SKUI::Button.new(name) { |control| self.select_speaker(speaker) }
            speaker.button.width = (84)
            speaker.button.font = SKUI::Font.new(nil, 12)
            
            if (last_speaker = speaker_list.last) # There is a a speaker in the list already. Place this to the right of it.
                speaker.button.position( (last_speaker.button.left) + (last_speaker.button.width + 1), (50 + SPEAKER_PAGE_OFFSET))
            else
                ### List is empty... this is the first speaker	
                @realtime_label.visible = true					# Why are these settings here???
                @commit_label.visible = true
                @speaker_name_label.visible = true
                @delete_button.visible = true
                @please_add_label.visible = false
                speaker.button.position(START_X, (START_Y + SPEAKER_PAGE_OFFSET))
            end
            
            speaker.group_highlight.position(speaker.button.left, (speaker.button.top-10))
            
            speaker.realtime_check = SKUI::Checkbox.new('' , true)
            speaker.realtime_check.position( (speaker.button.left + speaker.button.width / 2) - 5, speaker.button.top + 30)
            speaker.realtime_check.on(:change) { |control| control.checked? ; Sketchup.active_model.active_view.invalidate }
            @window.add_control(speaker.realtime_check)
            
            speaker.commit_check = SKUI::Checkbox.new('' , true)
            speaker.commit_check.position( (speaker.button.left + speaker.button.width / 2) - 5, speaker.button.top + 50)
            speaker.commit_check.on(:change) { |control| control.checked? ; Sketchup.active_model.active_view.invalidate }
            @window.add_control(speaker.commit_check)
            
            speaker.name_field = SKUI::Textbox.new(name)
            speaker.name_field.position(350, (140 + SPEAKER_PAGE_OFFSET))
            speaker.name_field.width = 70
            speaker.name_field.on( :textchange ) { |control| self.update_speaker_name(control) }
            @window.add_control(speaker.name_field)
                        
            @speaker_list.push(speaker)
            @window.add_control(speaker.button)
            speaker.add_driver unless loading # This is turning into ugly spaghetti code! Move all of the initialization into the SpeakerPage class!
            ### ^^^ I had to move that here when attribute dictionaries were being updated constantly. Probably can move it back, but it works.
            self.highlight_mute
            self.select_speaker(speaker)
            return speaker
        end
        
        def select_speaker(speaker)
            if @current_speaker # Un-highlight and hide the currently selected speaker
                @current_speaker.button.background_color = Sketchup::Color.new(0,0,0,128) 
                @current_speaker.hide
            end	

            speaker.button.background_color = Sketchup::Color.new(0, 0, 150, 150 )
            speaker.show
            @current_speaker = speaker		
        end
        
        
        def update_speaker_name(control)
            old_name = @current_speaker.button.caption
            num_capitals = 0
            control.value.each_char do |char| num_capitals += 1 if char =~ /[A-Z]/ || char =~ /[0-9]/ end
            cap_mod = num_capitals * 2 # 2 extra pixels per capital letter or number
            diff_width = @current_speaker.button.width - (84 + cap_mod + (control.value.length-10)*5) # So the next speakers know how far to move
                    
            @current_speaker.button.caption = control.value
            @current_speaker.button.width = (84 + cap_mod + (control.value.length-10)*5) # Change the button width by 5 pixels per character
            @current_speaker.name_field.width = (70 + cap_mod + (control.value.length-10)*5) # (and the name field...)
            @current_speaker.group_highlight.width = @current_speaker.button.width - 1
            
    #		Wave_Trace::Attr_Update_Speaker(@current_speaker) # Update the stored model attributes
            
            # Move commit / realtime labels and check boxes
            found = false
            @speaker_list.each do |speaker|
                if speaker == @current_speaker  # Move the current speaker's checkboxes
                    found = true
                    speaker.realtime_check.left = speaker.button.left + (speaker.button.width / 2) - 5
                    speaker.commit_check.left = speaker.button.left + (speaker.button.width / 2) - 5 
                    next
                elsif found == true 	# We've passed the current speaker in the array... start shifting every speaker that follows.
                    speaker.button.left -= diff_width
                    speaker.group_highlight.left = speaker.button.left
                    speaker.realtime_check.left = speaker.button.left + (speaker.button.width / 2) - 5
                    speaker.commit_check.left = speaker.button.left + (speaker.button.width / 2) - 5
                end # Last case (else) would be !found and !current_speaker... which are speakers to the left of current (ignorable)			
            end
        end
        
        
        def sort_speaker(direction)
        
        end
        
        
        def delete_speaker
            # FIX - Add "ARE YOU SURE?" warning...
            
            @current_speaker.group_num = nil
            
            if @current_speaker == @speaker_list.first
                if @speaker_list.length > 1   # First speaker, with others following. Delete and shift entire array down 1.
                    offset = @current_speaker.button.width + 1
                    self.select_speaker(@speaker_list[1])
                    @speaker_list.shift.delete  # Pop first speaker and run its delete routine
                    @speaker_list.compact!
                    @speaker_list.each do |speaker|  # Now shift each speaker left
                        speaker.button.left -= offset
                        speaker.group_highlight.left = speaker.button.left
                        speaker.realtime_check.left -= offset
                        speaker.commit_check.left -= offset
                            ### FIX shift the sorting buttons here as well
                    end	
                else	# First and only speaker. Delete and hide static page elements
                    @current_speaker.delete
                    @current_speaker = nil
                    @speaker_list.pop
                    @speaker_list.compact!
                    @realtime_label.visible = false
                    @commit_label.visible = false
                    @speaker_name_label.visible = false	
                    @delete_button.visible = false
                    @please_add_label.visible = true
                    @add_button.background_color = Sketchup::Color.new(128, 0, 0, 192) # Reset the "Add Speaker" color to red...
                end
            elsif @current_speaker == @speaker_list.last # Last speaker (with others left). Delete and shift focus left 1
                self.select_speaker(@speaker_list[-2])		
                @speaker_list.pop.delete  # Pop last speaker and run its delete routine
                @speaker_list.compact!
            else
                ### This speaker is somewhere in the middle... delete it and shift remaining array down
                offset = @current_speaker.button.width + 1
                i = @speaker_list.index(@current_speaker)
                @speaker_list.delete(@current_speaker) # Remove the current speaker from the list
                @speaker_list.compact!
                @current_speaker.delete # Clear current speaker
                @current_speaker = nil
                self.select_speaker(@speaker_list[i])
                for x in i..((@speaker_list.length) - 1)
                    @speaker_list[x].button.left -= offset
                    @speaker_list[x].group_highlight.left = @speaker_list[x].button.left
                    @speaker_list[x].realtime_check.left -= offset
                    @speaker_list[x].commit_check.left -= offset
                        ### FIX shift sorting buttons as well
                end
                
            end	
            Sketchup.active_model.active_view.invalidate
        end
        
            
        def draw
            @speaker_list.each do |speaker|		# FIX - wtf? this call doesn't make sense. lol...
                speaker.button.visible = true
            end		
            @window.show
        end
            
        def show(mod = true)
            @current_speaker.show(mod) if @current_speaker
            @speaker_list.each do |speaker|
                speaker.button.visible = mod
                speaker.realtime_check.visible = mod
                speaker.commit_check.visible = mod
                speaker.group_highlight.visible = mod	
            end
            @static_elements.each do |element|
                element.visible = mod
            end
            @please_add_label.visible = false if !@speaker_list.empty? # always hide the intro screen if there's a speaker...
        end
        
        def hide
            self.show(false)
        end
        
        
    end

end