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
        #Sketchup.send_action "showRubyPanel:"
 
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
			@main_window = SKUI::Window.new(
                {title: 'Wave Trace',
                width: 800,
                height: 800,
                resizable: false,
                theme: SKUI::Window::THEME_GRAPHITE
            })
			@page = RayTracePage.new(@main_window)
			
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
		dictionaries = Sketchup.active_model.attribute_dictionaries
	    dictionaries.delete('Wave_Trace')
		puts "Deleted all Wave_Trace dictionary entries..."
		return self.Attr_Report # Report the dictionary entries... just to be sure its clear
	end		
		
	


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
	end
end

file_loaded('wave_trace.rb')
