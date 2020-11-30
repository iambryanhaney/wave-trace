module Wave_Trace

    class DriverPage
        attr_accessor :page
        attr_accessor :driver_list
        attr_accessor :origin
        attr_accessor :vector
        attr_accessor :ray_list
        attr_accessor :name_field
        attr_accessor :my_speaker
        attr_accessor :my_location
        attr_accessor :locate_button
        attr_accessor :x_angle_low_drop
        attr_accessor :x_angle_high_drop
        attr_accessor :y_angle_low_drop
        attr_accessor :y_angle_high_drop
        attr_accessor :x_angle_link_check
        attr_accessor :y_angle_link_check
        attr_accessor :density_drop
        attr_accessor :realtime_check
        attr_accessor :commit_check
        
        unless file_loaded?('wave_trace.rb')
            LESS = false
            MORE = true
            LINKED = true
            DRIVER_OFFSET = 110
        end

        @window = nil
        @my_speaker = nil
        @driver_list = nil
        @origin = nil # Point3d location on model, once selected by user
        @vector = nil # Vector3d direction on model, taken from the normal of the user selected face
        
        @ray_list = nil
        
        @elements = nil
        
        @name_field = nil
        @locate_button = nil 
        @delete_button = nil
        @realtime_label = nil
        @commit_label = nil
        @realtime_check = nil
        
        @x_angle_image = nil
        @x_angle_low_drop = nil
        @x_angle_high_drop = nil
        @x_angle_low_left_button = nil
        @x_angle_low_right_button = nil
        @x_angle_high_left_button = nil
        @x_angle_high_right_button = nil
        @x_angle_link_label = nil
        @x_angle_link_check = nil
        
        @y_angle_image = nil
        @y_angle_low_drop = nil
        @y_angle_high_drop = nil
        @y_angle_low_down_button = nil
        @y_angle_low_up_button = nil
        @y_angle_high_down_button = nil
        @y_angle_high_up_button = nil
        @y_angle_link_label = nil
        @y_angle_link_check = nil
        
        @density_image = nil
        @density_drop = nil
        @density_down_button = nil
        @density_up_button = nil
        @density_label = nil
        
        @highlight_x_angle = nil
        @highlight_y_angle = nil
        @highlight_check = nil # Checkbox
        @centerline_red = nil
        @centerline_check = nil # Checkbox
        @location = nil # Geom::Point3d
        
        
        def initialize(window, speaker, loading = false)
            @window = window
            @page = speaker.page
            @my_speaker = speaker
            @driver_list = @my_speaker.driver_list
            @ray_list = []
            
            offset = @driver_list.length * DRIVER_OFFSET
            name = "Driver " + (@driver_list.length + 1).to_s	
            
            @name_field = SKUI::Textbox.new(name)
            @name_field.on(:textchange) { |control| control.value = control.value } # Workaround... doesn't save name on window close unless referenced
            @name_field.position(10, (220 + offset + SPEAKER_PAGE_OFFSET ) )
            @name_field.width = 100		
            @window.add_control(@name_field)
                    
            @locate_button = SKUI::Button.new("Locate on Model") { |control| @page.tool.locate_driver(self) }
            @locate_button.width = 100
            @locate_button.position(8, (242 + offset + SPEAKER_PAGE_OFFSET ) )
            @locate_button.background_color = Sketchup::Color.new(128,0,0,192)
            @locate_button.font = SKUI::Font.new(nil, 12)
            @window.add_control(@locate_button)
            
            @delete_button = SKUI::Button.new("X") { |control| self.delete_button_action }
            @delete_button.width = 20
            @delete_button.height = 18
            @delete_button.position(113, (220 + offset + SPEAKER_PAGE_OFFSET ) )
            @delete_button.font = SKUI::Font.new(nil, 12)
            @window.add_control(@delete_button)
            
            @realtime_label = Wave_Trace::gui_create_label('R:', 144, (222 + offset + SPEAKER_PAGE_OFFSET), true)
            @window.add_control(@realtime_label)
            
            @commit_label = Wave_Trace::gui_create_label('C:', 144, (244 + offset + SPEAKER_PAGE_OFFSET), true)
            @window.add_control(@commit_label)
            
            @realtime_check = SKUI::Checkbox.new('', true)
            @realtime_check.position(158, (222 + offset + SPEAKER_PAGE_OFFSET))
            @realtime_check.on(:change) { |control| 
                control.checked?
                if @my_speaker.group_num # This speaker is in a group
                    this_driver_index = @driver_list.index(self)
                    # Find all other speakers in the same group and update similar drivers if they exist
                    @page.speaker_list.each do |speaker|
                        next if speaker == @my_speaker
                        next if speaker.group_num != @my_speaker.group_num
                        if (driver = speaker.driver_list[this_driver_index]) # There is a matching driver we can set the values of
                            driver.realtime_check.checked = control.checked?
                        end		
                    end
                end				
                Sketchup.active_model.active_view.invalidate
            }
            @window.add_control(@realtime_check)
            
            @commit_check = SKUI::Checkbox.new('', true)
            @commit_check.position(158, (244 + offset + SPEAKER_PAGE_OFFSET))
            @commit_check.on(:change) { |control|
                control.checked?
                if @my_speaker.group_num # This speaker is in a group
                    this_driver_index = @driver_list.index(self)
                    # Find all other speakers in the same group and update similar drivers if they exist
                    @page.speaker_list.each do |speaker|
                        next if speaker == @my_speaker
                        next if speaker.group_num != @my_speaker.group_num
                        if (driver = speaker.driver_list[this_driver_index]) # There is a matching driver we can set the values of
                            driver.commit_check.checked = control.checked?
                        end		
                    end
                end				
                Sketchup.active_model.active_view.invalidate
            }
            @window.add_control(@commit_check)
                    
            ###########################
            ########################### XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
            ###########################
            fresh_list = %w{0 15 30 45 60 75 90}
            
            path = File.dirname(__FILE__)
            file = File.join(path, 'images/img_x_angle.png')
            @x_angle_image = SKUI::Image.new( file )
            @x_angle_image.position( 190, (190 + offset + SPEAKER_PAGE_OFFSET))
            @window.add_control(@x_angle_image)		
                    
            @x_angle_low_drop = SKUI::Listbox.new(fresh_list)
            @x_angle_low_drop.value = 30.to_s
            @x_angle_low_drop.position( 190, (250 + offset + SPEAKER_PAGE_OFFSET) )
            @x_angle_low_drop.width = 47
            @x_angle_low_drop.height = 20
            @x_angle_low_drop.on( :change ) { |control, value, from_linked_control, from_linked_speaker| 
                control.value = value
                next if from_linked_control == true # This :change event is being called from its linked control. Just update the value and return.
                        
                if @x_angle_link_check.checked? == true # This control is linked to another. Update it...
                    @x_angle_high_drop.trigger_event(:change, value, true)
                end
                
                if from_linked_speaker == nil # This is an legitimate :change call from user input, not from a linked speaker
                    if @my_speaker.group_num # This speaker is in a group
                        this_driver_index = @driver_list.index(self)
                        # Find all other speakers in the same group and update similar drivers if they exist
                        @page.speaker_list.each do |speaker|
                            next if speaker == @my_speaker
                            next if speaker.group_num != @my_speaker.group_num
                            if (driver = speaker.driver_list[this_driver_index]) # There is a matching driver we can set the values of
                                driver.x_angle_low_drop.trigger_event(:change, control.value, nil, true)
                                @page.tool.update_driver(driver) # FIX - This only updates driver attributes that have origin / vector
                            end			
                        end
                    end
                    @page.tool.update_driver(self) # This should ultimately only be called once, after all linked speakers are updated
                end
            }
            @window.add_control(@x_angle_low_drop)		
            
            @x_angle_high_drop = SKUI::Listbox.new(fresh_list)
            @x_angle_high_drop.value = 30.to_s
            @x_angle_high_drop.position( 240, (250 + offset + SPEAKER_PAGE_OFFSET) )
            @x_angle_high_drop.width = 47
            @x_angle_high_drop.height = 20
            @x_angle_high_drop.on( :change ) { |control, value, from_linked_control, from_linked_speaker| 
                control.value = value
                next if from_linked_control == true # This :change event is being called from its linked control. Just update the value and return.
                        
                if @x_angle_link_check.checked? == true # This control is linked to another. Update it...
                    @x_angle_low_drop.trigger_event(:change, value, true)
                end
                
                if from_linked_speaker == nil # This is an legitimate :change call from user input, not from a linked speaker
                    if @my_speaker.group_num # This speaker is in a group
                        this_driver_index = @driver_list.index(self)
                        # Find all other speakers in the same group and update similar drivers if they exist
                        @page.speaker_list.each do |speaker|
                            next if speaker == @my_speaker
                            next if speaker.group_num != @my_speaker.group_num
                            if (driver = speaker.driver_list[this_driver_index]) # There is a matching driver we can set the values of
                                driver.x_angle_high_drop.trigger_event(:change, control.value, nil, true)
                                @page.tool.update_driver(driver) # FIX - This only updates driver attributes that have origin / vector
                            end		
                        end
                    end
                    @page.tool.update_driver(self) # This should ultimately only be called once, after all linked speakers are updated
                end
            }
            @window.add_control(@x_angle_high_drop)		
            
            @x_angle_low_left_button = SKUI::Button.new("<") { self.drop_list_navigate(@x_angle_low_drop, MORE) }
            @x_angle_low_left_button.width = 20
            @x_angle_low_left_button.height = 13
            @x_angle_low_left_button.position(189, (270 + offset + SPEAKER_PAGE_OFFSET) )
            @x_angle_low_left_button.font = SKUI::Font.new(nil, 9)
            @x_angle_low_left_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@x_angle_low_left_button)
            
            @x_angle_low_right_button = SKUI::Button.new(">") {	self.drop_list_navigate(@x_angle_low_drop, LESS) }
            @x_angle_low_right_button.width = 20
            @x_angle_low_right_button.height = 13
            @x_angle_low_right_button.position(209, (270 + offset + SPEAKER_PAGE_OFFSET) )
            @x_angle_low_right_button.font = SKUI::Font.new(nil, 9)
            @x_angle_low_right_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@x_angle_low_right_button)
            
            @x_angle_high_left_button = SKUI::Button.new("<") { self.drop_list_navigate(@x_angle_high_drop, LESS) }
            @x_angle_high_left_button.width = 20
            @x_angle_high_left_button.height = 13
            @x_angle_high_left_button.position(245, (270 + offset + SPEAKER_PAGE_OFFSET) )
            @x_angle_high_left_button.font = SKUI::Font.new(nil, 9)
            @x_angle_high_left_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@x_angle_high_left_button)
            
            @x_angle_high_right_button = SKUI::Button.new(">") { self.drop_list_navigate(@x_angle_high_drop, MORE) }
            @x_angle_high_right_button.width = 20
            @x_angle_high_right_button.height = 13
            @x_angle_high_right_button.position(265, (270 + offset + SPEAKER_PAGE_OFFSET) )
            @x_angle_high_right_button.font = SKUI::Font.new(nil, 9)
            @x_angle_high_right_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@x_angle_high_right_button)
            
            @x_angle_link_label = Wave_Trace::gui_create_label('Link', 194, (195 + offset + SPEAKER_PAGE_OFFSET), true)
            @window.add_control(@x_angle_link_label)
            
            @x_angle_link_check = SKUI::Checkbox.new('', true)
            @x_angle_link_check.on ( :change ) { |control, from_linked_control|
                control.checked?
                if @my_speaker.group_num # This speaker is in a group
                    this_driver_index = @driver_list.index(self)
                    # Find all other speakers in the same group and update similar drivers if they exist
                    @page.speaker_list.each do |speaker|
                        next if speaker == @my_speaker
                        next if speaker.group_num != @my_speaker.group_num
                        if (driver = speaker.driver_list[this_driver_index]) # There is a matching driver we can set the values of
                            driver.x_angle_link_check.checked = control.checked?
                        end		
                    end
                end
                    
                @x_angle_high_drop.trigger_event(:change, @x_angle_low_drop.value) if control.checked? == true 
            }
            @x_angle_link_check.position(198, (210 + offset + SPEAKER_PAGE_OFFSET))
            @window.add_control(@x_angle_link_check)
            
            ###########################
            ########################### YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
            ###########################

            file = File.join(path, 'images/img_y_angle.png')
            @y_angle_image = SKUI::Image.new( file )
            @y_angle_image.position( 300, (190 + offset + SPEAKER_PAGE_OFFSET))
            @window.add_control(@y_angle_image)		
            
            @y_angle_low_drop = SKUI::Listbox.new(fresh_list)
            @y_angle_low_drop.value = 30.to_s
            @y_angle_low_drop.position( 326, (247 + offset + SPEAKER_PAGE_OFFSET) )
            @y_angle_low_drop.width = 47
            @y_angle_low_drop.height = 20
            @y_angle_low_drop.on( :change ) { |control, value, from_linked_control, from_linked_speaker| 
                control.value = value
                next if from_linked_control == true # This :change event is being called from its linked control. Just update the value and return.
                        
                if @y_angle_link_check.checked? == true # This control is linked to another. Update it...
                    @y_angle_high_drop.trigger_event(:change, value, true)
                end
                
                if from_linked_speaker == nil # This is an legitimate :change call from user input, not from a linked speaker
                    if @my_speaker.group_num # This speaker is in a group
                        this_driver_index = @driver_list.index(self)
                        # Find all other speakers in the same group and update similar drivers if they exist
                        @page.speaker_list.each do |speaker|
                            next if speaker == @my_speaker
                            next if speaker.group_num != @my_speaker.group_num
                            if (driver = speaker.driver_list[this_driver_index]) # There is a matching driver we can set the values of
                                driver.y_angle_low_drop.trigger_event(:change, control.value, nil, true)
                                @page.tool.update_driver(driver) # FIX - This only updates driver attributes that have origin / vector
                            end
                        end
                    end
                    @page.tool.update_driver(self) # This should ultimately only be called once, after all linked speakers are updated
                end
            }
            @window.add_control(@y_angle_low_drop)		
            
            @y_angle_high_drop = SKUI::Listbox.new(fresh_list)
            @y_angle_high_drop.value = 30.to_s
            @y_angle_high_drop.position( 326, (210 + offset + SPEAKER_PAGE_OFFSET) )
            @y_angle_high_drop.width = 47
            @y_angle_high_drop.height = 20
            @y_angle_high_drop.on( :change ) { |control, value, from_linked_control, from_linked_speaker| 
                control.value = value
                next if from_linked_control == true # This :change event is being called from its linked control. Just update the value and return.
                        
                if @y_angle_link_check.checked? == true # This control is linked to another. Update it...
                    @y_angle_low_drop.trigger_event(:change, value, true)
                end
                
                if from_linked_speaker == nil # This is an legitimate :change call from user input, not from a linked speaker
                    if @my_speaker.group_num # This speaker is in a group
                        this_driver_index = @driver_list.index(self)
                        # Find all other speakers in the same group and update similar drivers if they exist
                        @page.speaker_list.each do |speaker|
                            next if speaker == @my_speaker
                            next if speaker.group_num != @my_speaker.group_num
                            if (driver = speaker.driver_list[this_driver_index]) # There is a matching driver we can set the values of
                                driver.y_angle_high_drop.trigger_event(:change, control.value, nil, true)
                                @page.tool.update_driver(driver) # FIX - This only updates driver attributes that have origin / vector
                            end		
                        end
                    end
                    @page.tool.update_driver(self) # This should ultimately only be called once, after all linked speakers are updated
                end
            }
            @window.add_control(@y_angle_high_drop)		
            
            @y_angle_low_down_button = SKUI::Button.new("v") {
                self.drop_list_navigate(@y_angle_low_drop, MORE)
                @y_angle_high_drop.value = @y_angle_low_drop.value if @y_angle_link_check.checked? == true }
            @y_angle_low_down_button.width = 20
            @y_angle_low_down_button.height = 13
            @y_angle_low_down_button.position(375, (257 + offset + SPEAKER_PAGE_OFFSET) )
            @y_angle_low_down_button.font = SKUI::Font.new(nil, 9)
            @y_angle_low_down_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@y_angle_low_down_button)
            
            @y_angle_low_up_button = SKUI::Button.new("^") { 
                self.drop_list_navigate(@y_angle_low_drop, LESS)
                @y_angle_high_drop.value = @y_angle_low_drop.value if @y_angle_link_check.checked? == true }
            @y_angle_low_up_button.width = 20
            @y_angle_low_up_button.height = 13
            @y_angle_low_up_button.position(375, (244 + offset + SPEAKER_PAGE_OFFSET) )
            @y_angle_low_up_button.font = SKUI::Font.new(nil, 9)
            @y_angle_low_up_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@y_angle_low_up_button)
            
            @y_angle_high_down_button = SKUI::Button.new("v") {
                self.drop_list_navigate(@y_angle_high_drop, LESS)
                @y_angle_low_drop.value = @y_angle_high_drop.value if @y_angle_link_check.checked? == true }
            @y_angle_high_down_button.width = 20
            @y_angle_high_down_button.height = 13
            @y_angle_high_down_button.position(375, (221 + offset + SPEAKER_PAGE_OFFSET) )
            @y_angle_high_down_button.font = SKUI::Font.new(nil, 9)
            @y_angle_high_down_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@y_angle_high_down_button)
            
            @y_angle_high_up_button = SKUI::Button.new("^") {
                self.drop_list_navigate(@y_angle_high_drop, MORE)
                @y_angle_low_drop.value = @y_angle_high_drop.value if @y_angle_link_check.checked? == true }
            @y_angle_high_up_button.width = 20
            @y_angle_high_up_button.height = 13
            @y_angle_high_up_button.position(375, (208 + offset + SPEAKER_PAGE_OFFSET) )
            @y_angle_high_up_button.font = SKUI::Font.new(nil, 9)
            @y_angle_high_up_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@y_angle_high_up_button)
            
            @y_angle_link_label = Wave_Trace::gui_create_label('Link', 304, (195 + offset + SPEAKER_PAGE_OFFSET), true)
            @window.add_control(@y_angle_link_label)
            
            @y_angle_link_check = SKUI::Checkbox.new('', true)
            @y_angle_link_check.on ( :change ) { |control, from_linked_control|
                control.checked?
                if @my_speaker.group_num # This speaker is in a group
                    this_driver_index = @driver_list.index(self)
                    # Find all other speakers in the same group and update similar drivers if they exist
                    @page.speaker_list.each do |speaker|
                        next if speaker == @my_speaker
                        next if speaker.group_num != @my_speaker.group_num
                        if (driver = speaker.driver_list[this_driver_index]) # There is a matching driver we can set the values of
                            driver.y_angle_link_check.checked = control.checked?
                        end		
                    end
                end
                    
                @y_angle_low_drop.trigger_event(:change, @y_angle_high_drop.value) if control.checked? == true 
            }
            
            @y_angle_link_check.position(308, (210 + offset + SPEAKER_PAGE_OFFSET))
            @window.add_control(@y_angle_link_check)
            
            ###########################
            ########################### DENSITY DENSITY DENSITY
            ###########################

            file = File.join(path, 'images/img_ray_density.png')
            @density_image = SKUI::Image.new( file )
            @density_image.position( 410, (190 + offset + SPEAKER_PAGE_OFFSET))
            @window.add_control(@density_image)		
            
            @density_drop = SKUI::Listbox.new(%w{ 0.1 0.3 0.5 0.75 1 3 5 7.5 10 12.5 15 30 })
            @density_drop.value = 15.to_s
            @density_drop.position( 434, (215 + offset + SPEAKER_PAGE_OFFSET) )
            @density_drop.width = 48
            @density_drop.height = 20
            @density_drop.on( :change ) { |control, value, from_linked_speaker| 
                control.value = value if value
                self.density_update(control.value)
                if @my_speaker.group_num && from_linked_speaker == nil # This speaker is in a group and the :change event is from user input
                    this_driver_index = @driver_list.index(self)
                    # Find all other speakers in the same group and update similar drivers if they exist
                    @page.speaker_list.each do |speaker|
                        next if speaker == @my_speaker
                        next if speaker.group_num != @my_speaker.group_num
                        if (driver = speaker.driver_list[this_driver_index]) # There is a matching driver we can set the values of
                            driver.density_drop.trigger_event(:change, control.value, true)
                            #@page.tool.update_driver(driver) #The bottom one should already be being called
                        end		
                    end
                end	
                @page.tool.update_driver(self)
            }
            @window.add_control(@density_drop)		
            
            @density_down_button = SKUI::Button.new("v") { self.drop_list_navigate(@density_drop, MORE) }
            @density_down_button.width = 20
            @density_down_button.height = 13
            @density_down_button.position(484, (224 + offset + SPEAKER_PAGE_OFFSET) )
            @density_down_button.font = SKUI::Font.new(nil, 9)
            @density_down_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@density_down_button)
            
            @density_up_button = SKUI::Button.new("^") { self.drop_list_navigate(@density_drop, LESS) }
            @density_up_button.width = 20
            @density_up_button.height = 13
            @density_up_button.position(484, (212 + offset + SPEAKER_PAGE_OFFSET) )
            @density_up_button.font = SKUI::Font.new(nil, 9)
            @density_up_button.background_color = Sketchup::Color.new(0,128,0, 255)
            @window.add_control(@density_up_button)
            
            @density_label = Wave_Trace::gui_create_label('Ray Density', 430, (195 + offset + SPEAKER_PAGE_OFFSET), true)
            @window.add_control(@density_label)
                    
            @elements = [ @name_field, @locate_button, @delete_button, @realtime_label, @commit_label, @realtime_check, @commit_check, @x_angle_image,
                        @x_angle_low_drop, @x_angle_high_drop, @x_angle_low_left_button, @x_angle_low_right_button, @x_angle_high_left_button,
                        @x_angle_high_right_button, @x_angle_link_label, @x_angle_link_check, @y_angle_image,
                        @y_angle_low_drop, @y_angle_high_drop, @y_angle_low_down_button, @y_angle_low_up_button, @y_angle_high_down_button,
                        @y_angle_high_up_button, @y_angle_link_label, @y_angle_link_check, @density_image, @density_drop, @density_label, @density_down_button, 
                        @density_up_button ]
            
            @driver_list.push(self)
            
            if @my_speaker.group_num &&	!loading # This driver was added to a speaker in a group. See if its linked speakers have a corresponding driver.
                @page.speaker_list.each do |s|
                    next if s == @my_speaker
                    next if s.group_num != @my_speaker.group_num
                    if (d_to_copy = s.driver_list[@driver_list.length-1])  # There is a corresponding driver in this speaker. Copy all settings.
                        @density_drop.trigger_event(:change, d_to_copy.density_drop.value, true)
                        @x_angle_low_drop.value = d_to_copy.x_angle_low_drop.value
                        @x_angle_high_drop.value = d_to_copy.x_angle_high_drop.value
                        @x_angle_link_check.checked = d_to_copy.x_angle_link_check.checked?
                        @y_angle_low_drop.value = d_to_copy.y_angle_low_drop.value
                        @y_angle_high_drop.value = d_to_copy.y_angle_high_drop.value
                        @y_angle_link_check.checked = d_to_copy.y_angle_link_check.checked?
                        break # We don't need to keep searching.
                    end
                end
            end
        end
            
        def create_new_list(d)
            new_list = []
            
            # These could be done elegantly by iterating the list and dropping non-integer values... but that's pretty inefficient 
            if d == 0.1 || d == 0.5
                for i in 0..90
                    new_list.push(i.to_s)	# List is 1-90 in increments of 1
                end
            elsif d == 0.3 || d == 0.75
                for i in 0..30
                    new_list.push((i*3).to_s) # List is 3-90 in increments of 3
                end
            else # d >= 1 ... populate list with all possibilities
                new_list.push(0.to_s) # Add zero as the first list choice
                for i in 1..((90/d).to_i)
                    new_val = i*d
                    new_val = new_val.to_i if new_val % 1 == 0	# Convert to integer if whole number (so we don't see " .0 " after the number.
                    new_list.push(new_val.to_s)
                end
            end
            
            return new_list
        end
            
        def density_update(density) # Update all of the angle list-boxes with divisible angles
            d = density.to_f
            new_list = []
                    
            # x low
            old_value = @x_angle_low_drop.value		
            @x_angle_low_drop.clear		
            @x_angle_low_drop.add_item(create_new_list(d))
            if list_pos = @x_angle_low_drop.items.index(old_value) # The currently selected angle still exists in the list of choices.
                @x_angle_low_drop.value = @x_angle_low_drop.items[list_pos]
            else # Currently selected angle does not exist. Round to the nearest neighbor
                @x_angle_low_drop.value = @x_angle_low_drop.items.min_by{ |item| (item.to_f - old_value.to_f).abs }
            end
                
            # x high
            new_list.clear
            old_value = @x_angle_high_drop.value		
            @x_angle_high_drop.clear
            @x_angle_high_drop.add_item(create_new_list(d))
            if list_pos = @x_angle_high_drop.items.index(old_value) # The currently selected angle still exists in the list of choices.
                @x_angle_high_drop.value = @x_angle_high_drop.items[list_pos]
            else # Currently selected angle does not exist. Round to the nearest neighbor...
                @x_angle_high_drop.value = @x_angle_high_drop.items.min_by{ |item| (item.to_f - old_value.to_f).abs }
            end
            
            # y low
            new_list.clear
            old_value = @y_angle_low_drop.value		
            @y_angle_low_drop.clear
            @y_angle_low_drop.add_item(create_new_list(d))
            if list_pos = @y_angle_low_drop.items.index(old_value) # The currently selected angle still exists in the list of choices.
                @y_angle_low_drop.value = @y_angle_low_drop.items[list_pos]
            else # Currently selected angle does not exist. Round to the nearest neighbor
                @y_angle_low_drop.value = @y_angle_low_drop.items.min_by{ |item| (item.to_f - old_value.to_f).abs }
            end
                    
            # y high
            new_list.clear
            old_value = @y_angle_high_drop.value		
            @y_angle_high_drop.clear
            @y_angle_high_drop.add_item(create_new_list(d))
            if list_pos = @y_angle_high_drop.items.index(old_value) # The currently selected angle still exists in the list of choices.
                @y_angle_high_drop.value = @y_angle_high_drop.items[list_pos]
            else # Currently selected angle does not exist. Round to the nearest neighbor...
                @y_angle_high_drop.value = @y_angle_high_drop.items.min_by{ |item| (item.to_f - old_value.to_f).abs }
            end
            
            # FIX - Update driver after all these changes happen...
            
        end
            
        def drop_list_navigate(list, direction)
            list_pos = list.items.index(list.value)
            if direction == LESS  # Moving down the array... just check if we're at the bottom
                if list_pos > 0
                    list.trigger_event(:change, list.items[list_pos-1] )
                end
            else	# Must be going up the array... just check if we're at the top
                if list_pos < (list.items.length-1)
                    list.trigger_event(:change, list.items[list_pos+1] )
                end
            end
        end
            
            
        def shift_up
            @elements.each do |element|
                element.top -= DRIVER_OFFSET
            end
        end
            
        
        ### DRIVER show
        def show(mod = true)
            @elements.each do |element|
                element.visible = mod
            end
        end
        
        ### DRIVER hide	
        def hide
            self.show(false)
        end
        
        def delete_button_action
                            
            if self == @driver_list.first
                if @driver_list.length > 1   # First driver, with others following. Delete and shift entire array down 1.
                    @driver_list.shift.delete  # Pop first driver and run its delete routine
                    @driver_list.compact!
                    
                    if @my_speaker.group_num	# This driver was added to a speaker in a group. See if its linked speakers have a corresponding driver.
                        @driver_list.each do |d|
                            next if d == self # Should never happen...
                            this_index = @driver_list.index(d)
                            @page.speaker_list.each do |s|
                                next if s == @my_speaker
                                next if s.group_num != @my_speaker.group_num
                                if (d_to_copy = s.driver_list[this_index])  # There is a corresponding driver in this speaker. Copy all settings.
                                    d.density_drop.trigger_event(:change, d_to_copy.density_drop.value, true)
                                    d.x_angle_low_drop.value = d_to_copy.x_angle_low_drop.value
                                    d.x_angle_high_drop.value = d_to_copy.x_angle_high_drop.value
                                    d.x_angle_link_check.checked = d_to_copy.x_angle_link_check.checked?
                                    d.y_angle_low_drop.value = d_to_copy.y_angle_low_drop.value
                                    d.y_angle_high_drop.value = d_to_copy.y_angle_high_drop.value
                                    d.y_angle_link_check.checked = d_to_copy.y_angle_link_check.checked?
                                    break # We don't need to keep searching for this driver.
                                end
                            end
                            d.shift_up # Shift the driver's visual elements upwards
                        end
                    else
                        @driver_list.each do |d|
                            d.shift_up 
                        end
                    end
            
                else	# First and only driver. Delete and hide static page elements
                    @driver_list.pop.delete
                    @driver_list.compact!
                end
            elsif self == @driver_list.last # Last driver (with others left). Delete
                @driver_list.pop.delete  # Pop last driver and run its delete routine
                @driver_list.compact!
            else
                ### This driver is somewhere in the middle... delete it and shift remaining array down
                this_index = @driver_list.index(self)
                @driver_list.delete(self) # Remove the current driver from the list
                @driver_list.compact!
                self.delete # Clear current driver
                
                if @my_speaker.group_num	# This driver was added to a speaker in a group. See if its linked speakers have a corresponding driver.
                    for i in this_index..(@driver_list.length - 1)
                        d = @driver_list[i]
                        next if d == self # Should never happen...
                        @page.speaker_list.each do |s|
                            next if s == @my_speaker
                            next if s.group_num != @my_speaker.group_num
                            if (d_to_copy = s.driver_list[i])  # There is a corresponding driver in this speaker. Copy all settings.
                                d.density_drop.trigger_event(:change, d_to_copy.density_drop.value, true)
                                d.x_angle_low_drop.value = d_to_copy.x_angle_low_drop.value
                                d.x_angle_high_drop.value = d_to_copy.x_angle_high_drop.value
                                d.x_angle_link_check.checked = d_to_copy.x_angle_link_check.checked?
                                d.y_angle_low_drop.value = d_to_copy.y_angle_low_drop.value
                                d.y_angle_high_drop.value = d_to_copy.y_angle_high_drop.value
                                d.y_angle_link_check.checked = d_to_copy.y_angle_link_check.checked?
                                break # We don't need to keep searching for this driver.
                            end
                        end
                        d.shift_up # Shift the driver's visual elements upwards
                    end
                else			
                    for i in this_index..(@driver_list.length - 1) # Shift remaining drivers up
                        @driver_list[i].shift_up
                    end
                end	
            end			
            @driver_list.compact! #FIX - remove...?
            Sketchup.active_model.active_view.invalidate
        end
        
        ### DRIVER delete
        def delete
            @elements.each do |element|
                @window.remove_control(element)
            end
        end
        
    end 

end