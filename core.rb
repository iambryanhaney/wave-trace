require 'sketchup.rb'
require 'SKUI/core.rb'

module Wave_Trace

    path = File.dirname(__FILE__)
    require File.join(path, 'ray_trace.rb')
    require File.join(path, 'speaker.rb')
    require File.join(path, 'driver.rb')
    require File.join(path, 'tool.rb')

    # Run once on initial file load
    unless file_loaded?('wave_trace.rb')
        # Show Ruby Console
        Sketchup.send_action "showRubyPanel:"
 
        # Add toolbar and menu
		toolbar = UI::Toolbar.new("Wave Trace")
		cmd = UI::Command.new("Wave Trace") { self.start_tool }
		cmd.small_icon = "images/img_toolbar_small.png"
		cmd.large_icon = "images/img_toolbar_large.png"
		cmd.tooltip = "Wave Trace"
		cmd.status_bar_text = "Advanced raycasting / raytracing tool for speaker sound wave reflection analysis in a studio environment."
		cmd.menu_text = "Wave Trace"
		toolbar = toolbar.add_item(cmd)
        plugins_menu = UI.menu('Plugins')
		plugins_menu.add_item(cmd)
        
        # Check if toolbar was visible and restore, or show if its the first time loaded
		case toolbar.get_last_state
		when 1
			# Toolbar was visible; restore it.
			toolbar.restore
		when -1
			# Toolbar was never shown; show it.
			toolbar.show
		when 0
			# Toolbar was hidden; keep it hidden.
		end
        
        # Tool state constants
        STATE_IDLE = 0              # 0 The main tool is running and will draw in realtime if the option is on
        STATE_LOCATE_DRIVER = 1     # 1 User is placing driver points
        STATE_DEFINE_BARRIER = 2    # 2 User is defining a barrier to stop rays
        STATE_MARK_IGNORE = 3       # 3 User is toggling objects as ignorable
        
        RAY_PAGE_OFFSET = 0 # To manipulate the vertical layouts while under construction
        SPEAKER_PAGE_OFFSET = (RAY_PAGE_OFFSET + 40)
        
	end
		
	@main_window = nil
	@page = nil
	
	# Create the initial GUI window or load pre-existing
	def self.start_tool
        if @main_window
            # Main window already exists; show it. The on(:ready) callback will select the tool.                
			@main_window.show if @main_window.visible? == false
        else
            # No window exists; create a window and main tool.
			@main_window = SKUI::Window.new({
                title: 'Wave Trace',
                width: 800,
                height: 800,
                resizable: false,
                theme: SKUI::Window::THEME_GRAPHITE
            })
			@page = Wave_Trace::RayTracePage.new(@main_window)
			
			# When the window is ready (HTML DOM is loaded) notify the page, select the tool and attempt to load any settings
            @main_window.on(:ready) { |control| 
                @page.win_open = true
                Sketchup.active_model.select_tool(@page.tool)
                @page.try_load 
            }
			
            # Load the tool on window focus, unless the window is closing or the tool is already active
            @main_window.on(:focus) { |control|  
                Sketchup.active_model.select_tool(@page.tool) if @page.win_open && !@page.tool.active
            }
							
			# If the user closes the window, cancel any operations and notify the page
            @main_window.on(:close) { |control| 
                Sketchup.active_model.select_tool(nil)
                @page.win_open = false 
            }
					
			@page.draw	# FIX - Redundant... just call a @main_window.show here
		end 
	end
	
	# Helper function for quicker SKUI::Label creation
	def self.gui_create_label(name, pos_x, pos_y, visible = true)
		label = SKUI::Label.new(name)
		label.position(pos_x, pos_y)
		label.visible = visible
		return label
	end
	
	# Helper functions for checking and clearing the 'Wave_Trace' attribute dictionary (for debugging purposes)
	@dir = "Wave_Trace"
		
	# Read out all of the pertinent Wave_Trace attributes
	def self.Attr_Report
		model = Sketchup.active_model
		
		dictionary = Sketchup.active_model.attribute_dictionary('Wave_Trace')
		return "No dictionary. End of attributes." if !dictionary
		
		puts "draw_realtime: #{model.get_attribute(@dir, 'draw_realtime')}"
		puts "bounce_hidden: #{model.get_attribute(@dir, 'bounce_hidden')}"
		puts "max_length: #{model.get_attribute(@dir, 'max_length')}"
		# puts "use_barrier: #{model.get_attribute(@dir, 'use_barrier')}"
		puts "max_bounces: #{model.get_attribute(@dir, 'max_bounces')}"
		puts "bounce_filter: #{model.get_attribute(@dir, 'bounce_filter')}"
		# puts "draw_sweetspot: #{model.get_attribute(@dir, 'draw_sweetspot')}"
		
		speaker_index = 0
		driver_index = 0
	
		begin
			speaker_name = "s_#{speaker_index.to_s}"
			speaker_object = Sketchup.active_model.get_attribute(@dir, speaker_name)
			puts "#{speaker_name} --- #{speaker_object}" if speaker_object
			begin
				driver_name = "#{speaker_name}_d_#{driver_index.to_s}"
				driver_object = Sketchup.active_model.get_attribute(@dir, driver_name)
				puts "#{driver_name} --- #{driver_object}" if driver_object
				driver_index += 1
			end while driver_object != nil
			driver_index = 0
			speaker_index += 1
		end while speaker_object != nil
		
		return "End of attributes."
	end
	
	# Delete all Wave_Trace attributes
	def self.Attr_Clear
		dictionaries = Sketchup.active_model.attribute_dictionaries
	    dictionaries.delete('Wave_Trace')
		puts "Deleted all Wave_Trace dictionary entries..."
		return self.Attr_Report # Report the dictionary entries... just to be sure its clear
	end		
		
end

file_loaded('wave_trace.rb')
