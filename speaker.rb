module Wave_Trace
	
    class SpeakerPage
        attr_accessor :button
        attr_accessor :realtime_check
        attr_accessor :commit_check
        attr_accessor :name_field
        attr_accessor :speaker_list
        attr_accessor :driver_list
        attr_accessor :add_driver_button
        # attr_accessor :link_to_group_label
        # attr_accessor :link_to_group_drop
        attr_accessor :group_highlight
        attr_accessor :page
        attr_accessor :group_num
        
        @window = nil
        @speaker_list = nil
        @dummy_button = nil
        @button = nil
        @realtime_check = nil
        @commit_check = nil
        @name_field = nil
        @add_driver_button = nil
        # @link_to_group_label = nil
        # @link_to_group_drop = nil
        @group_highlight = nil
        @group_num = nil
        
        @page = nil
            
        def initialize(page, window, speaker_list)
            @window = window
            @page = page
            @speaker_list = speaker_list
            @driver_list = []
            
            @group_highlight = SKUI::Container.new
            @group_highlight.visible = true
            @group_highlight.background_color = Sketchup::Color.new(0, 0, 0, 0)
            @group_highlight.width = 83
            @group_highlight.height = 11
            @window.add_control(@group_highlight)
            
            ### If loading from saved, search for drivers here and run some fancy routines to recover settings, else...
            
            @add_driver_button = SKUI::Button.new("Add Driver") { |control| self.add_driver }
            @add_driver_button.width = 100
            @add_driver_button.position(5, 148 + SPEAKER_PAGE_OFFSET)
            @add_driver_button.font = SKUI::Font.new(nil, 12)
            @window.add_control(add_driver_button)
            #self.add_driver # FIX - This is where it should be...
            
            # @link_to_group_label = Wave_Trace::gui_create_label("Link speaker to group...", 120, (130 + SPEAKER_PAGE_OFFSET), true)
            # @window.add_control(@link_to_group_label)
            
            # @link_to_group_drop = SKUI::Listbox.new(["-----------", "Group 1 (red)", "Group 2 (green)", "Group 3 (yellow)", "Group 4 (white)"])
            # @link_to_group_drop.position( 115, (148 + SPEAKER_PAGE_OFFSET) )
            # @link_to_group_drop.width = 150
            # @link_to_group_drop.height = 20
            # @link_to_group_drop.on( :change ) { |control| self.link_speaker_to_group(control) }
            # @window.add_control(@link_to_group_drop)
        end
        
        def link_speaker_to_group(control)
            if control.value == control.items[0] ### Selected the first option (no group link). 
                @group_num = nil
                @group_highlight.background_color = Sketchup::Color.new(0, 0, 0, 0)
            else # Chose a group to link to
                @group_num = control.items.index(control.value)
                case @group_num
                when 1
                    @group_highlight.background_color = Sketchup::Color.new(128,0,0,255) # Red
                when 2
                    @group_highlight.background_color = Sketchup::Color.new(0,128,0,255) # Green
                when 3
                    @group_highlight.background_color = Sketchup::Color.new(128,128,0,255) # Yellow
                when 4
                    @group_highlight.background_color = Sketchup::Color.new(200,200,200,255) # White
                else
                    puts "Error: Shouldn't be here (case @group_num failed in link_speaker_to_group)"
                end
                # Find the speaker in this group with the most drivers and copy its settings
                speaker_with_most_drivers = nil
                most_drivers = 0
                @speaker_list.each do |s|
                    next if s == self
                    if s.group_num == @group_num
                        if s.driver_list.length > most_drivers
                            speaker_with_most_drivers = s
                            most_drivers = s.driver_list.length
                        end
                    end
                end
                if speaker_with_most_drivers # At least one other speaker in the group has drivers defined.
                    for driver_index in 0..(speaker_with_most_drivers.driver_list.length - 1)
                        if (d = @driver_list[driver_index]) # There is a corresponding driver in this speaker. Copy all settings.
                            d_to_copy = speaker_with_most_drivers.driver_list[driver_index]
                            d.density_drop.trigger_event(:change, d_to_copy.density_drop.value)
                            d.x_angle_low_drop.value = d_to_copy.x_angle_low_drop.value
                            d.x_angle_high_drop.value = d_to_copy.x_angle_high_drop.value
                            d.x_angle_link_check.checked = d_to_copy.x_angle_link_check.checked?
                            d.y_angle_low_drop.value = d_to_copy.y_angle_low_drop.value
                            d.y_angle_high_drop.value = d_to_copy.y_angle_high_drop.value
                            d.y_angle_link_check.checked = d_to_copy.y_angle_link_check.checked?
                            d.realtime_check.checked = d_to_copy.realtime_check.checked?
                            #d.commit_check = d_to_copy.commit_check
                            # FIX - !!! This might be causing multiple ray_list rewrites?
                        end
                    end
                end
            end			
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
            
        def add_driver(loading = false)
            driver = DriverPage.new(@window, self, loading)	
            self.highlight_mute
            return driver
        end	
            
        ### SPEAKER delete
        def delete
            @window.remove_control(@button)
            @window.remove_control(@realtime_check)
            @window.remove_control(@commit_check)
            @window.remove_control(@name_field)
            @window.remove_control(@add_driver_button)
            # @window.remove_control(@link_to_group_label)
            # @window.remove_control(@link_to_group_drop)
            @window.remove_control(@group_highlight)
            @driver_list.each do |driver|
                driver.delete
            end
        end
        
        ### SPEAKER show
        def show(mod = true)
            @driver_list.each do |driver|
                driver.show(mod)
            end
            @add_driver_button.visible = mod
            @name_field.visible = mod
            # @link_to_group_label.visible = mod
            # @link_to_group_drop.visible = mod
        end
        
        ### SPEAKER hide
        def hide
            self.show(false)
        end

    end

end