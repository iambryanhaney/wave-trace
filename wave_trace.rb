require 'sketchup.rb'
require 'SKUI/core.rb'

#-----------------------------------------------------------------------------

# <SketchUp>/Plugins/my_extension/main.rb
#module Example
  #extension_path = File.dirname( __FILE__ )
  #skui_path = File.join( extension_path, 'SKUI' )
  #load File.join( skui_path, 'embed_skui.rb' )
  #::SKUI.embed_in( self )
  ## SKUI module is now available under Example::SKUI
#end

module Wave_Trace

	# Add toolbar and menu
	unless file_loaded?('wave_trace.rb')
			
		toolbar = UI::Toolbar.new("Wave Trace toolbar")
		cmd = UI::Command.new("Wave Trace command") { self.start_tool }
		cmd.small_icon = "img_toolbar_small.png"
		cmd.large_icon = "img_toolbar_large.png"
		cmd.tooltip = "Wave Trace tooltip"
		cmd.status_bar_text = "Advanced raycasting / raytracing tool for speaker sound wave reflection analysis in a studio environment."
		cmd.menu_text = "Wave Trace menu text"
		toolbar = toolbar.add_item(cmd)
	
		# Check if toolbar was visible and restore, or show if its the first time loaded
		case toolbar.get_last_state
		when 1
			toolbar.restore
			puts "Toolbar was visible last. Restoring."
		when -1
			toolbar.show
			puts "Toolbar never shown. Showing it."
		when 0
			puts "Toolbar was hidden and remains so."
		end
		
		plugins_menu = UI.menu('Plugins')
		plugins_menu.add_item(cmd)
	end
  
	# Constants for tool states
	unless file_loaded?('wave_trace.rb')
		STATE_IDLE = 0 # The main tool is running and will draw in realtime if the option is on
		STATE_LOCATE_DRIVER = 1 # User is placing driver points
		STATE_DEFINE_BARRIER = 2 # User is defining a barrier to stop rays
		STATE_MARK_IGNORE = 3 # User is toggling objects as ignorable
		
		RAY_PAGE_OFFSET = 0 # To manipulate the vertical layouts while under construction
		SPEAKER_PAGE_OFFSET = (RAY_PAGE_OFFSET + 40)
	end
		
	@main_window = nil
	@page = nil
	
	
	# Create the initial GUI window or load pre-existing
	def self.start_tool
		if @main_window		# There's already an existing window... lets just show it (the :ready trigger will select the tool)
			@main_window.show if @main_window.visible? == false
		else	# No window... first time through. Create window and main tool.
			@main_window = SKUI::Window.new({:title => 'Wave Trace window', :width => 800, :height => 800, :resizable => false,
											 :theme => SKUI::Window::THEME_GRAPHITE})
			@page = RayTracePage.new(@main_window)
			
			# Whenever the window is ready (HTML DOM is loaded) notify the page, select the tool and attempt to load any settings
			@main_window.on(:ready) { |control| @page.win_open = true ; Sketchup.active_model.select_tool(@page.tool) ; @page.try_load }
			
			# Clicking in the window loads the tool unless the window is "closing" (user clicked on the X while simultaneously bringing into focus)
			# Also check if the tool is already "active"... because even if we re-load the same tool, it will call its "deactivate" routine (bad!)
			@main_window.on(:focus) { |control|  Sketchup.active_model.select_tool(@page.tool) if @page.win_open && !@page.tool.active }
							
			# If the user CLOSES the window treat this as CANCELLING any operations... then notify the page the window isn't available
			@main_window.on(:close) { |control| Sketchup.active_model.select_tool(nil) ; @page.win_open = false }
					
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
		
		dict = Sketchup.active_model.attribute_dictionary('Wave_Trace')
		return "No dictionary. End of attributes." if !dict
		
		puts "draw_realtime: #{model.get_attribute(@dir, 'draw_realtime')}"
		puts "bounce_hidden: #{model.get_attribute(@dir, 'bounce_hidden')}"
		puts "max_length: #{model.get_attribute(@dir, 'max_length')}"
		puts "use_barrier: #{model.get_attribute(@dir, 'use_barrier')}"
		puts "max_bounces: #{model.get_attribute(@dir, 'max_bounces')}"
		puts "bounce_filter: #{model.get_attribute(@dir, 'bounce_filter')}"
		puts "draw_sweetspot: #{model.get_attribute(@dir, 'draw_sweetspot')}"
		
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
		ad = Sketchup.active_model.attribute_dictionaries
		ad.delete('Wave_Trace')
		puts "Deleted all Wave_Trace dictionary entries..."
		return self.Attr_Report # Report the dictionary entries... just to be sure its clear
	end		
		
	
#######################################################################################################################################
###### RAYTRACE #######################################################################################################################
#######################################################################################################################################
	
class RayTracePage	
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
			speaker_hash_name = "s_#{speaker_list.index(speaker).to_s}" # Name it after its index location in speaker_list... "s_1" "s_2" etc
			speaker_hash_object = {:name => speaker.button.caption, :realtime_check => speaker.realtime_check.checked?,
									:commit_check => speaker.commit_check.checked?, :group_num => speaker.group_num}
			model.set_attribute(dir, speaker_hash_name, speaker_hash_object.inspect) # Store the speaker settings as a string
		
			speaker.driver_list.each do |driver|
				driver_hash_name = "#{speaker_hash_name}_d_#{speaker.driver_list.index(driver).to_s}" # Name driver index s_1_d_1, s_1_d_2 etc
				driver_hash_object = {:name => driver.name_field.value, :origin => driver.origin.to_a, :vector => driver.vector.to_a,
									  :x_angle_low => driver.x_angle_low_drop.value, :x_angle_high => driver.x_angle_high_drop.value,
									  :y_angle_low => driver.y_angle_low_drop.value, :y_angle_high => driver.y_angle_high_drop.value,
									  :x_angle_link => driver.x_angle_link_check.checked?, :y_angle_link => driver.y_angle_link_check.checked?,
									  :density => driver.density_drop.value, :ray_list => driver.ray_list,
									  :realtime_check => driver.realtime_check.checked?, :commit_check => driver.commit_check.checked?}
				model.set_attribute(dir, driver_hash_name, driver_hash_object.inspect) # Store the driver settings as a string
			end
		end
		
		# FIX - Save global options too
		
		model.commit_operation # End undo-able operation
		UI.messagebox("              Important!\n\nAll speakers, drivers and global settings have been *stored* in your model... but you must SAVE YOUR MODEL for these settings to keep!", MB_OK)
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
		
		@save_settings_button = SKUI::Button.new("Save All Settings") { |control| self.save_settings }
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
end

#######################################################################################################################################
##### SPEAKER #########################################################################################################################
#######################################################################################################################################
	
class SpeakerPage

	@window = nil
	@speaker_list = nil
	@dummy_button = nil
	@button = nil
	@realtime_check = nil
	@commit_check = nil
	@name_field = nil
	@add_driver_button = nil
	@link_to_group_label = nil
	@link_to_group_drop = nil
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
		
		@link_to_group_label = Wave_Trace::gui_create_label("Link speaker to group...", 120, (130 + SPEAKER_PAGE_OFFSET), true)
		@window.add_control(@link_to_group_label)
		
		@link_to_group_drop = SKUI::Listbox.new(["-----------", "Group 1 (red)", "Group 2 (green)", "Group 3 (yellow)", "Group 4 (white)"])
		@link_to_group_drop.position( 115, (148 + SPEAKER_PAGE_OFFSET) )
		@link_to_group_drop.width = 150
		@link_to_group_drop.height = 20
		@link_to_group_drop.on( :change ) { |control| self.link_speaker_to_group(control) }
		@window.add_control(@link_to_group_drop)
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
		@window.remove_control(@link_to_group_label)
		@window.remove_control(@link_to_group_drop)
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
		@link_to_group_label.visible = mod
		@link_to_group_drop.visible = mod
	end
	
	### SPEAKER hide
	def hide
		self.show(false)
	end
	
	attr_accessor :button
	attr_accessor :realtime_check
	attr_accessor :commit_check
	attr_accessor :name_field
	attr_accessor :speaker_list
	attr_accessor :driver_list
	attr_accessor :add_driver_button
	attr_accessor :link_to_group_label
	attr_accessor :link_to_group_drop
	attr_accessor :group_highlight
	attr_accessor :page
	attr_accessor :group_num
end

#######################################################################################################################################
##### DRIVER ##########################################################################################################################
#######################################################################################################################################

class DriverPage
	
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
		file = File.join(path, 'img_x_angle.png')
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

		file = File.join(path, 'img_y_angle.png')
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

		file = File.join(path, 'img_ray_density.png')
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
	
end 



################################################################################################
	
	# Place a driver point in the model
	class Wave_Trace_Raycast_Tool
	
		def initialize(page)
			@page = page
			@window = @page.window
			@driver = nil
			@state = STATE_IDLE
				
			@active = false
			@cursor = nil
			@cursor2 = nil
			@cursor3 = nil
			@cursor4 = nil
			@ph = nil
			@p_face = nil
			@p_best = nil
			
			@barrier_pt_1 = nil
			@barrier_pt_2 = nil
			@barrier_pt_3 = nil
			@sweet_pt_1 = nil
			@sweet_pt_2 = nil
			@sweet_pt_3 = nil
			@sweet_pt_4 = nil
			@tmp_pt_1 = nil
			@tmp_pt_2 = nil
			@tmp_pt_3 = nil
		end
		
		
		def locate_driver(driver)
			self.set_state(STATE_LOCATE_DRIVER)
			@driver = driver
			Sketchup.active_model.active_view.invalidate
		end
		
		
		def set_state(state_to_be)
			case state_to_be
			when STATE_IDLE # GOING TO BE
				case @state 
				when STATE_LOCATE_DRIVER # Coming From
					@page.show
					@window.set_size(800,800)
					@page.place_driver_label.visible = false
					@page.tool_button.visible = false
				when STATE_MARK_IGNORE # Coming From
					@page.show
					if @page.speaker_list.empty?
						@page.realtime_label.visible = false
						@page.commit_label.visible = false
						@page.delete_button.visible = false 
					end
					@window.set_size(800,800)
					@page.mark_ignore_label.visible = false
					@page.mark_ignore_label2.visible = false
					@page.mark_ignore_target_label.visible = false
					@page.mark_ignore_target_label.caption = ''
					@page.mark_ignore_target_highlight.visible = false
					@page.mark_ignore_target_highlight.background_color = Sketchup::Color.new(0,0,0,0)
					@page.mark_ignore_update_label.visible = false
					@page.mark_ignore_update_check.visible = false
					@page.tool_button.visible = false
					if @page.mark_ignore_update_check.checked? # Auto-update all rays
						self.update_all_drivers
					end
				when STATE_DEFINE_BARRIER # Coming From
					# Clear inference locking if we are locked...
					Sketchup.active_model.active_view.lock_inference if Sketchup.active_model.active_view.inference_locked?
					@tmp_pt_1 = nil
					@tmp_pt_2 = nil
					@tmp_pt_3 = nil
					@cursor2.clear
					@cursor3.clear
					@cursor4.clear
				end			
				@state = STATE_IDLE
			when STATE_LOCATE_DRIVER # GOING TO BE
				@page.hide
				@window.set_size(240,140)
				@page.place_driver_label.visible = true
				@page.tool_button.caption = "Cancel"
				@page.tool_button.position(78, 60)
				@page.tool_button.visible = true
				@state = STATE_LOCATE_DRIVER
			when STATE_MARK_IGNORE # GOING TO BE
				@page.hide
				@window.set_size(280, 200)
				@page.mark_ignore_label.visible = true
				@page.mark_ignore_label2.visible = true
				@page.mark_ignore_target_label.visible = true
				@page.mark_ignore_target_highlight.visible = true
				@page.mark_ignore_update_label.visible = true
				@page.mark_ignore_update_check.visible = true
				@page.tool_button.caption = "Done"
				@page.tool_button.position(100, 140)
				@page.tool_button.visible = true
				@state = STATE_MARK_IGNORE
			when STATE_DEFINE_BARRIER
				# FIX - Yeah yeah... make a little tool window, duh.
				@state = STATE_DEFINE_BARRIER
			end
		end
		
		
		def active?
			return @active
		end
		
		
		# We don't really need to do much here.
		def activate
			@active = true
			@cursor = Sketchup::InputPoint.new
			@cursor2 = Sketchup::InputPoint.new # cursor 2-4 for inferencing in STATE_DEFINE_BARRIER & STATE_DEFINE_SWEET
			@cursor3 = Sketchup::InputPoint.new
			@cursor4 = Sketchup::InputPoint.new
			Sketchup.active_model.active_view.invalidate # If we've re-opened the tool this will be sure to update the screen immediately
		end
		
		
		def deactivate(view)
			self.set_state(STATE_IDLE)
			@active = false
			Sketchup.active_model.selection.clear unless Sketchup.active_model.selection.empty?
			view.invalidate
		end
		
		
		def onCancel(reason, view)			
			self.set_state(STATE_IDLE) if reason == 0 # Pressed escape
			view.invalidate
		end

		
		def resume(view)
			view.invalidate
		end
	
				
		def onMouseMove(flags, x, y, view)
			case @state
			when STATE_LOCATE_DRIVER
				@ph = view.pick_helper
				@ph.do_pick(x, y)
				if @ph.picked_face != @p_face	# Found a face different than the currently picked
					@p_face = @ph.picked_face
				end
				@cursor.pick(view, x, y)
				view.invalidate
			when STATE_MARK_IGNORE
				@ph = view.pick_helper
				@ph.do_pick(x, y)
				if @ph.best_picked != @p_best
					@p_best = @ph.best_picked
					if @p_best == nil # Nothing under cursor
						Sketchup.active_model.selection.clear
						@page.mark_ignore_target_label.caption = ''
						@page.mark_ignore_target_highlight.background_color = Sketchup::Color.new(0,0,0,0)
					else 
						# Found something... check its ignore flag and update the gui accordingly						
						if (ignore_status = @p_best.get_attribute('Wave_Trace', 'ignore') )
							@page.mark_ignore_target_label.caption = 'IGNORE'
							@page.mark_ignore_target_highlight.background_color = Sketchup::Color.new(128,0,0,200)
						else
							@page.mark_ignore_target_label.caption = 'Normal'
							@page.mark_ignore_target_highlight.background_color = Sketchup::Color.new(0, 128, 0, 200)
						end
						
						# Highlight the object under cursor
						Sketchup.active_model.selection.clear
						if (@p_best.is_a? Sketchup::Face) || (@p_best.is_a? Sketchup::Edge) || (@p_best.is_a? Sketchup::ComponentInstance) ||
						(@p_best.is_a? Sketchup::Group)
							Sketchup.active_model.selection.add(@p_best)
						else
							# We found some misc stuff we don't care about (dimlinear, image, etc)
							@page.mark_ignore_target_label.caption = ''
							@page.mark_ignore_target_highlight.background_color = Sketchup::Color.new(0,0,0,0)
						end
					end
				end
				view.invalidate if @cursor.pick(view, x, y)
			when STATE_DEFINE_BARRIER
				if !@tmp_pt_1 # Picking first point...
					view.invalidate if @cursor.pick(view, x, y)		
				elsif !@tmp_pt_2 # Picking second point...
					view.invalidate if @cursor2.pick(view, x, y, @cursor) # cursor2 inferred from cursor
					view.lock_inference(@cursor) if !view.inference_locked? # FIX - Probably need this...
				else # Picking third and final point
					view.invalidate if @cursor3.pick(view, x, y, @cursor2) # cursor3 inferred from cursor2
				end
			end
		end

		
		def update_all_drivers
			@page.speaker_list.each do |speaker|
				speaker.driver_list.each do |driver|
					update_driver(driver, false) # Update driver, but don't refresh view
				end
			end
			Sketchup.active_model.active_view.invalidate
		end
		
		
		def update_driver(driver, refresh = true)
			return unless driver.origin && driver.vector
			
			driver.ray_list.clear # FIX - Remove?
			driver.ray_list = create_ray_list(driver.origin, driver.vector, driver.y_angle_low_drop.value.to_f.degrees, 
										  driver.y_angle_high_drop.value.to_f.degrees, driver.x_angle_high_drop.value.to_f.degrees,
										  driver.x_angle_low_drop.value.to_f.degrees, driver.density_drop.value.to_f.degrees,
										  15.degrees, (@page.max_length_drop.value.to_i*12), @page.max_bounces_drop.value.to_i, 1, 3, 
										  !@page.bounce_hidden_check.checked?, @page.bounce_filter_drop.value )
			Sketchup.active_model.active_view.invalidate if refresh
		end
		
		# FIX - only activate the inference if we are picking the first point...?
		# FIX - Add logic to lock the first cursor to objects too.
	#	def onKeyDown(key, repeat, flags, view)			
	#		if key == CONSTRAIN_MODIFIER_KEY
	#			if view.inference_locked?
	#				view.lock_inference # We WERE locked... clear it.
	#			else
	#				view.lock_inference(@cursor) if @cursor.valid?
	#			end
	#			view.invalidate
	#		end
	#	end
		
		
		def onLButtonUp(flags, x, y, view)
			case @state
			when STATE_LOCATE_DRIVER
				if !@p_face  # Clicked on blank space.
					return
				end
			
				normal = @p_face.normal
			
				## FIX - Probably have to move 
				@ph.count.times { |index| 
					if @p_face == @ph.leaf_at(index) # Found the face's pickhelper branch
						normal.transform!(@ph.transformation_at(index)) # Apply the branches complete transform
						break
					end
				}			
			
				# Make sure normal is facing camera, flip if not
				eye = Sketchup.active_model.active_view.camera.eye		
				test_point = @cursor.position.offset(normal, 1)
				
				if eye.distance(test_point) > eye.distance(@cursor.position)  
					# Test point is farther from camera... the normal isn't facing me.
					normal.reverse!
				end		

				# Set the driver object's origin, vector and ray_list... then store those as model attributes
				@driver.origin = @cursor.position
				@driver.vector = normal
				@driver.ray_list = create_ray_list(@cursor.position, normal, @driver.y_angle_low_drop.value.to_f.degrees, 
										  @driver.y_angle_high_drop.value.to_f.degrees, @driver.x_angle_high_drop.value.to_f.degrees,
										  @driver.x_angle_low_drop.value.to_f.degrees, @driver.density_drop.value.to_f.degrees,
										  15.degrees, (@page.max_length_drop.value.to_i*12), @page.max_bounces_drop.value.to_i, 1, 3,
										  !@page.bounce_hidden_check.checked?, @page.bounce_filter_drop.value )
			
				@driver.locate_button.background_color = Sketchup::Color.new(0, 0, 0, 128) # Un-highlight locate_button
				@driver.locate_button.caption = "Relocate"			
				@driver = nil
				self.set_state(STATE_IDLE)
				view.invalidate
			when STATE_MARK_IGNORE
				if @p_best && (@p_best.is_a? Sketchup::Face) || (@p_best.is_a? Sketchup::Edge) || (@p_best.is_a? Sketchup::ComponentInstance) ||
				(@p_best.is_a? Sketchup::Group)					
					# Flip the ignore status...
					Sketchup.active_model.start_operation("Wave_Trace: Mark Objects to Ignore", true, true)
					if (ignore_status = @p_best.get_attribute('Wave_Trace', 'ignore') )
						@p_best.delete_attribute('Wave_Trace', 'ignore')
						@page.mark_ignore_target_label.caption = 'Normal'
						@page.mark_ignore_target_highlight.background_color = Sketchup::Color.new(0, 128, 0, 200)
					else
						@p_best.set_attribute('Wave_Trace', 'ignore', true)
						@page.mark_ignore_target_label.caption = 'IGNORE'
						@page.mark_ignore_target_highlight.background_color = Sketchup::Color.new(128,0,0,200)
					end
					Sketchup.active_model.commit_operation
				end
			when STATE_DEFINE_BARRIER
				if !@tmp_pt_1 # First click / point selection
					if @cursor.valid?
						@tmp_pt_1 = @cursor.position
						@cursor.clear
						@cursor = Sketchup::InputPoint.new(@tmp_pt_1) # Move the cursor to the selected point
						@cursor.pick(view, x, y) # Make a pick at the selected point to get a valid inference
					end
				elsif !@tmp_pt_2 # Second click / point selection
					@tmp_pt_2 = @cursor2.position if @cursor2.valid?
					@cursor2 = Sketchup::InputPoint.new(@tmp_pt_2) # Move the cursor2 inference to the selected point
					#view.lock_inference(@cursor2) if !view.inference_locked? # FIX - Probably need this...
				else # Third and final click / point selection
					if @cursor3.valid?
						@barrier_pt_1 = @tmp_pt_1
						@barrier_pt_2 = @tmp_pt_2
						@barrier_pt_3 = @cursor3.position
						self.set_state(STATE_IDLE) # Clear all tmp points / cursors and reset window
						view.invalidate
					end
				end
			end
		end
				
				
		# More stringent test to make sure the cursor point is actually touching a face. For some reason it doesn't
		# report back as many valid points (@p_face.classify_point returns alot of '32' (point not on plane)... but why?)
		def point_on_face?(view)  
			
			return true if @cursor.face == @p_face
			
			point = @cursor.position
			@ph.count.times { |index| 
				if @p_face == @ph.leaf_at(index) # Its in a group... apply the transform in reverse to the point we are checking
					point.transform!(@ph.transformation_at(index).inverse)
					break
				end
			}			
				
			status = @p_face.classify_point(point)
			#puts "\nCursor returns....\nEdge: #{@cursor.edge}\nFace: #{@cursor.face}\nVertex: #{@cursor.vertex}\nClassify_point status: #{status}\n"
			#view.draw_points([point], 20, 4, 'orange')
			#@cursor.draw(view)
			if status == Sketchup::Face::PointUnknown || status == Sketchup::Face::PointOutside || status == Sketchup::Face::PointNotOnPlane
				return false
			else
				return true
			end
		end
	
	
		def draw(view)			
			case @state
			when STATE_IDLE
				if @page.ready? 
					if @page.draw_realtime_check.checked?
						@page.speaker_list.each do |speaker|
							next unless speaker.realtime_check.checked?
							speaker.driver_list.each do |driver|
								next unless driver.realtime_check.checked? && driver.origin 
								draw_ray_list(view, driver.origin, driver.ray_list)							
							end
						end
					end
				end
			when STATE_LOCATE_DRIVER
				# Draw the cursor and a simplified ray_cast icon
				if !@p_face.nil? && @p_face.valid? #&& point_on_face?(view)	<--- REMOVE comments for stricter point testing
					normal = @p_face.normal
				
					# Transform normal if in a group
					@ph.count.times { |index| 
						if @p_face == @ph.leaf_at(index)
							normal.transform!(@ph.transformation_at(index)) # if transform??
							break
						end
					}			
				
					# Make sure normal is facing camera, flip if not
					eye = Sketchup.active_model.active_view.camera.eye		
					test_point = @cursor.position.offset(normal, 1)
				
					if eye.distance(test_point) > eye.distance(@cursor.position)  
						# Test point is farther from camera... the normal isn't facing me.
						normal.reverse!
					end
						
					# This is the "driver placement" tool icon, for all intents...
					#FIX - create a list using offsets... extremely large rooms will take inordinate amounts of time to raycast... just for an icon
					rays = create_ray_list(@cursor.position, normal) # The defaults create a very small ray_list 
					draw_ray_list(view, @cursor.position, rays)
					view.draw_points(@cursor.position, 15, 5, 'red')
				end
			when STATE_MARK_IGNORE
				# Just draw a custom cursor
				view.draw_points(@cursor.position, 15, 3, 'red')
				view.draw_points(@cursor.position, 16, 6, 'blue')				
			when STATE_DEFINE_BARRIER
				if @tmp_pt_2 # Point 1 and 2 are defined, locating Point 3
					@cursor3.draw(view) # The current cursor
					view.draw_points(@cursor3.position, 16, 6, 'orange') # Triangle on 3rd cursor point
					
					@cursor2.draw(view) # The last chosen point (we could use draw_points with tmp_pt2 instead?)
					view.draw_points(@cursor2.position, 16, 6, 'blue') # Triangle on 2nd cursor point
					
					view.set_color_from_line(@cursor2.position, @cursor3.position)
					view.draw_line(@cursor2.position, @cursor3.position)
				elsif @tmp_pt_1 # Point 1 is defined, locating Point 2
					@cursor2.draw(view)
					view.draw_points(@cursor2.position, 16, 6, 'blue') # Triangle on 2nd cursor point
					
					view.set_color_from_line(@cursor.position, @cursor2.position)
					view.draw_line(@cursor.position, @cursor2.position)
					
					# FIX - Cache these as arrays of lines to draw in the mousemove callback
					if (vec_to = @cursor.position.vector_to(@cursor2.position)).valid? # Cursor positions are separate. Draw proposed barrier.
						view.drawing_color = Sketchup::Color.new("DarkSlateGray")
						offset_pt = @cursor2.position.offset(vec_to, 1200)
						view.draw_line(@cursor2.position, offset_pt)
						offset_pt = @cursor.position.offset(vec_to.reverse, 1200)
						view.draw_line(@cursor.position, offset_pt)
						
						#face = @cursor.face
						
						#offset_pt = @cursor.position.offset(vec_to, 1200)
						#view.draw_line(@cursor.position, offset_pt)
					end
				end
				@cursor.draw(view) # Always draw the first cursor
				view.draw_points(@cursor.position, 16, 6, 'red')
				view.draw_points(@tmp_pt_1, 16, 6, 'purple') if @tmp_pt_1	
			end
		end
				

		# Draw a raylist in realtime (no geometry creation)
		def draw_ray_list(view, origin, ray_list)
			return if !ray_list || ray_list.length < 1
			ray_list.each do |point_list|
				next if point_list.length < 6 # Malformed point_list. Must be at least: [0]R [1]G [2]B [3]A [4]Length [5]P1
				
				view.drawing_color = Sketchup::Color.new(point_list[0],point_list[1], point_list[2], point_list[3])
				view.line_width = point_list[4]
				
				start_point = origin
				# Start drawing point to point
				for index in 5..(point_list.length-1)
					end_point = point_list[index]
					view.draw_line(start_point, end_point)
					start_point = end_point
				end
				view.draw_points(end_point, 6, 5)
			end
		end			
		
		def create_ray(ray_origin, ray_vector, ray_color, max_length, max_bounce, line_width = 1, bounce_hidden = true, bounce_filter = nil)
			ray_length = 0
			bounce_count = 0
			ray_bounced_180 = false # To filter out parallel reflections
			
			# We will save all points in an array, with the first 4 values of the array being the ray's color, and the 5th being its line width.
			# (this format will make it quick and easy to store all ray info in an attribute_dictionary)
			point_list = ray_color.to_a
			point_list.push(line_width)
						
			begin
				ray = Sketchup.active_model.raytest([ray_origin, ray_vector], bounce_hidden)
				if ray
					ray_target_point = ray[0]
					ray_target_list = ray[1]
					ray_target_entity = ray_target_list.last
					ray_length += ray_origin.distance(ray_target_point)
						
					# If there is a positive bounce filter and our length exceeds it without having bounced then return nil
					if (bounce_filter && bounce_filter > 0 && bounce_count == 0 && ray_length > bounce_filter)
						return nil
					end
										
					if ray_length >= max_length # End the ray at max_length
						over_length = ray_length - max_length
						point_in_space = ray_origin.offset(ray_vector, (ray_origin.distance(ray_target_point) - over_length))
						point_list.push(point_in_space.to_a)
						return point_list
					end
					
					point_list.push(ray_target_point.to_a) # FIX - Possibly execute this per target type, to avoid excessive lines from ignored geom
					
					# Test for ignore flag and keep moving if found.
					if (ignore_status = ray_target_entity.get_attribute('Wave_Trace', 'ignore') )
						ray_origin = ray_target_point # Set origin to target_point and continue on with same vector.
						next
					end
																							
					if ray_target_entity.is_a? Sketchup::Face
						# Test face for group/component containers, test those for ignore flags and (if not ignored) apply all transformations
						target_normal = ray_target_entity.normal
						if ray_target_list.length > 1 
							## Face is inside group(s) / component(s). Iterate through and apply transformations.
							ray_target_list.reverse_each do |container| # Does it really need to be in reverse?
								if (container.is_a? Sketchup::ComponentInstance) || (container.is_a? Sketchup::Group)
									if ( ignore_status = container.get_attribute('Wave_Trace', 'ignore') )
										# Found ignore flag. Break out of this list traversal.
										ray_origin = ray_target_point # Vector stays the same
										break
									end
									target_normal.transform!(container.transformation)
								end
							end
						end
						
						next if ignore_status # We already set the origin to be the next point when we found ignore_status above
						
						# If there is a negative bounce filter and this is the first bounce, return nil if the ray has
						# has hit something before the filter length
						if (bounce_filter && bounce_filter < 0 && bounce_count == 0 && ray_length < bounce_filter.abs)
							return nil
						end
						
						return point_list if bounce_count == max_bounce # No more bounces allowed... end ray at this last target
					
						angleb = ray_vector.angle_between(target_normal)
						crossp = ray_vector.cross(target_normal) # Axis to rotate on
						
						if !crossp.valid? # Ray hit a perpendicular surface and is coming straight back
							return point_list if ray_bounced_180 == true # Second time it has happened... surfaces are parallel (abort / finished)
							ray_bounced_180 = true
							### Flip the ray vector and move origin for next ray cast
							ray_vector.reverse!
							ray_origin = ray_target_point 
							bounce_count += 1
							next
						end
						
						### Reflect the ray vector and move origin for next ray cast
						trans=Geom::Transformation.rotation(ray_target_point, crossp, angleb-180.degrees)
						ray_vector = target_normal.transform(trans)
						ray_origin = ray_target_point					
						bounce_count += 1
					elsif ray_target_entity.is_a? Sketchup::Edge # Hit an edge... 
						face_list = ray_target_entity.faces
						if face_list.empty? # There are no attached faces... just an errant line. Keep going without bouncing.
							ray_origin = ray_target_point
							# (Vector just stays the same)
							next
						end
																					
						closest_face = nil
						
						if face_list.length > 1 # Multiple faces... find closest
							last_test_point = nil
							face_list.each do |face|
								# Create a test point that is in the direction of the face's center.
								test_point = ray_target_point.offset(ray_target_point.vector_to(face.bounds.center), 1)
								if !last_test_point # First face. Set it as the bar to beat and keep searching.
									last_test_point = test_point
									closest_face = face
									next
								end
								
								# The meat and potatoes... find the closest:
								if test_point.distance(ray_origin) > last_test_point.distance(ray_origin)
									closest_face = face
								end
								last_test_point = test_point
							end
						else	# Only one face
							closest_face = face_list[0]
						end
						
						target_normal = closest_face.normal
						if ray_target_list.length > 1 
							## Face is inside group(s) / component(s). Iterate through and apply transformations.
							ray_target_list.reverse_each do |container| # Does it actually need to be in reverse?
								if (container.is_a? Sketchup::ComponentInstance) || (container.is_a? Sketchup::Group)
									if ( ignore_status = container.get_attribute('Wave_Trace', 'ignore') )
										# Found ignore flag. Break out of this list traversal.
										ray_origin = ray_target_point # Vector stays the same
										break
									end
									target_normal.transform!(container.transformation)
								end
							end
						end
						
						next if ignore_status # We already set the origin to be the next point when we found ignore_status above
						
						# If there is a negative bounce filter and this is the first bounce, return nil if the ray has
						# has hit something before the filter length
						if (bounce_filter && bounce_filter < 0 && bounce_count == 0 && ray_length < bounce_filter.abs)
							return nil
						end
						
						return point_list if bounce_count == max_bounce # No more bounces allowed... end ray at this last target
					
						angleb = ray_vector.angle_between(target_normal)
						crossp = ray_vector.cross(target_normal) # Axis to rotate on
						
						if !crossp.valid? # Ray hit a perpendicular surface and is coming straight back
							return point_list if ray_bounced_180 == true # Second time it has happened... surfaces are parallel (abort / finished)
							ray_bounced_180 = true
							### Flip the ray vector and move origin for next ray cast
							ray_vector.reverse!
							ray_origin = ray_target_point 
							bounce_count += 1
							next
						end
						
						### Reflect the ray vector and move origin for next ray cast
						trans=Geom::Transformation.rotation(ray_target_point, crossp, angleb-180.degrees)
						ray_vector = target_normal.transform(trans)
						ray_origin = ray_target_point					
						bounce_count += 1
					else
						puts "This should never happen... but apparently the ray hit something other than a face or edge?"
						return point_list
					end
				else
					# Ray hit nothing... your ceiling or walls are likely hidden. Finish the ray at its max length or return nil
					# if there is a positive bounce filter and we still have yet to bounce
					if (bounce_filter && bounce_filter > 0 && bounce_count == 0)
						return nil
					end
					point_in_space = ray_origin.offset(ray_vector, (max_length - ray_length))
					if !Sketchup.active_model.bounds.contains?(point_in_space)
						Sketchup.active_model.bounds.add(point_in_space)
					end
					point_list.push(point_in_space.to_a)
					return point_list
				end
			end while ray
			
			# We literally should NEVER wind up down here...
			puts "We shouldn't be here...(bottom of create_ray)"
			return point_list
		end					
		
		
		def create_ray_gradient(x_paths, x_count, y_paths, y_count)
			x_paths -= 1 if x_paths > 1 # Protect against zero-divide
			y_paths -= 1 if y_paths > 1
			gradient = Sketchup::Color.new()
			gradient.red = ((255 / x_paths) * (x_count-1))
			gradient.green = 25 + ((115 / x_paths) * (x_count-1)) + ((115 / y_paths) * (y_count-1))						
			gradient.blue = ((255 / y_paths) * (y_count-1))
			gradient.alpha = 255 # Always 100% visible
			return gradient
		end
		
		
		def create_ray_list(ray_origin, ray_vector, x_angle_low = 30.degrees, x_angle_high = 30.degrees, y_angle_low = 30.degrees,
							y_angle_high = 30.degrees, angle_between_rays = 15.degrees, highlight_angle = 15.degrees, max_length = 30,
							max_bounce = 0, base_line_width = 1, center_line_width = 2, bounce_hidden = true, bounce_filter = nil)			
			ray_list = []
			ray_color = Sketchup::Color.new(50,50,50)
			
			x_paths = ((x_angle_low.radians + x_angle_high.radians) / angle_between_rays.radians) + 1
			y_paths = ((y_angle_low.radians + y_angle_high.radians) / angle_between_rays.radians) + 1
			highlight_x = false			
			
			trans = Geom::Transformation.rotation(ray_origin, ray_vector.axes.x, x_angle_low) # Start at bottom of x angle
			x_vec = ray_vector.transform(trans)
			
			if bounce_filter && bounce_filter != "---"
				bounce_filter = bounce_filter.to_i * 12
			else
				bounce_filter = nil
			end
			
			for x_count in 1..x_paths
				# Start working our way back up the x angle (unless this is our first time though)
				x_vec.transform!(Geom::Transformation.rotation(ray_origin, ray_vector.axes.x, -angle_between_rays)) unless x_count == 1
				
				# Start at the bottom of the y angle
				trans = Geom::Transformation.rotation(ray_origin, ray_vector.axes.y, y_angle_low)
				y_vec = x_vec.transform(trans)
				current_angle_between_x = x_vec.angle_between(ray_vector)
				if current_angle_between_x.to_l == (highlight_angle.to_l) # tolerance for floating point inaccuracies
					highlight_x = true
				else
					highlight_x = false
				end
				for y_count in 1..y_paths
					# Start working our way back up the y angle (unless this is our first time through)
					y_vec.transform!(Geom::Transformation.rotation(ray_origin, ray_vector.axes.y, -angle_between_rays)) unless y_count == 1
					current_angle_between_y = y_vec.angle_between(x_vec)
					
					# Calculate color and width
=begin					if  current_angle_between_y.to_l <= (highlight_angle.to_l) && highlight_x == true 
						
						else   # ray is in the "highlight" zone. create purple gradient (sloppy, quick version)\
							line_width = base_line_width
						    if highlight_angle > 0
								ray_color.red = 100 + 50*(current_angle_between_y / highlight_angle)
								ray_color.blue = 100 + 72 * (current_angle_between_x / highlight_angle )
							else
								ray_color.red = 128
								ray_color.blue = 128
							end
							ray_color.green = 0
						end
=end
					if y_vec.parallel?(ray_vector) # ray is in absolute center, highlight red
							ray_color.red = 255 
							ray_color.green = 0
							ray_color.blue = 0
							line_width = center_line_width
					else
						line_width = base_line_width
						ray_color = create_ray_gradient(x_paths, x_count, y_paths, y_count) # ray is not in a special zone. standard gradient
					end
										
					### Check for 90 degree rays and offset them a hair to reduce hitting speaker edges
					final_vector = y_vec.clone	
					if y_vec.angle_between(ray_vector).to_l == 90.degrees.to_l
						crossp = final_vector.cross(ray_vector)
						trans = Geom::Transformation.rotation(ray_origin, crossp, 0.25.degrees) # Offset the vector by .25 degrees back to center
						final_vector.transform!(trans)
					end
					
					ray = create_ray(ray_origin.clone, final_vector, ray_color, max_length, max_bounce, line_width, bounce_hidden, bounce_filter) # Create a point_list
					ray_list.push(ray) if ray # Add it to the ray_list unless nil
				end				
			end
			
			return ray_list
		end			
		attr_accessor :active
	end	 # class
end
#-----------------------------------------------------------------------------
file_loaded('wave_trace.rb')
#-----------------------------------------------------------------------------