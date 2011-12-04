class DSuitePlugin
  include Purugin::Plugin, Purugin::Colors
  description('dSuite', 0.3)
  
  def decode(value)
    value.to_s.to_i(36) - 32000
  end
  
  def convert_array_to_readable_string(array)
    result = ''
    array.each do |i|
      result << "#{i.to_s} "
    end
    return result
  end
  
  def neatify_home(home)
    x = home[:x].to_i
    y = home[:y].to_i + 1 # The +1 is to make the coordinates look like those when the user presses F3
    z = home[:z].to_i
    return "x#{x} y#{y} z#{z}".to_s
  end
  
  def load_locations()
    @location_hash = {}
    if File.exist?(locations_path) then
      File.open(locations_path, 'rb') do |io| 
        @location_hash = Marshal.load(io)
      end
    end
  end
  
  def locations_path()
    @path ||= File.join getDataFolder, 'locations.data'
  end
  
  def change_sign(sign_object, text_array)
    hex_pattern = /^[[:xdigit:]]+$/
    4.times do |i|
      line = text_array[i]
      if line[0] != nil and line[1] != nil and line[0].chr == '&' and hex_pattern === line[1].chr then # Red line
        sign_object.set_line(i, colorize_string(line))
      else
        sign_object.set_line(i, line)
      end
    end
    # Now perform a block update to change the sign
    sign_object.update
  end
  
  def parse_sign(sign_state)
    return [sign_state.get_line(0),sign_state.get_line(1),sign_state.get_line(2),sign_state.get_line(3)]
  end
  
  def check_direction_for_screen(direction, start_block)
    second_block = start_block.block_at(direction)
    if second_block.is? :iron_block
      # Iron blocks are there, now see if signs are
      sign1 = start_block.block_at(:up)
      sign2 = second_block.block_at(:up)
      screen_sign = sign2.block_at(direction,2)
      if sign1.is? :sign_post and sign2.is? :sign_post and screen_sign.is? :wall_sign then
        return [parse_sign(sign1.state),parse_sign(sign2.state),screen_sign.state]
      end
    end
  end
  
  def screen_setup(first_block)
    #North
    north = check_direction_for_screen(:north, first_block)
    return north if north != nil
    #South
    south = check_direction_for_screen(:south, first_block)
    return south if south != nil
    #East
    east = check_direction_for_screen(:east, first_block)
    return east if east != nil
    #West
    west = check_direction_for_screen(:west, first_block)
    return west if west != nil
    #---
    return nil
  end
  
  def check_for_blocks(original_block, direction, max_check)
    block_material = original_block.type
    result = []
    if direction == :up then
      max_check.times do |i|
        current_block = original_block.block_at(:up, i+1)
        return current_block if current_block.type == block_material
      end
    elsif direction == :down then
      max_check.times do |i|
        current_block = original_block.block_at(:down, i+1)
        return current_block if current_block.type == block_material
      end
    end
    return nil
  end
  
  def on_enable
    load_locations()
    players = {}
    
    public_command('dsethome', 'set_home', '/dsethome') do |me, *|
      # Get the player's current position
      location = me.location.to_a
      # ---
      # Now save that position into a file
      location_hash = {}
      location_hash[:x] = location[0].to_f
      location_hash[:y] = location[1].to_f
      location_hash[:z] = location[2].to_f
      @location_hash[me.display_name.split(']').last] = location_hash
      File.open(locations_path, 'wb') do |io| 
        Marshal.dump(@location_hash, io)
      end
      # ---
      # Finally, set the compass to the new home
      x = location_hash[:x].to_f
      y = location_hash[:y].to_f
      z = location_hash[:z].to_f
      destination = org.bukkit.Location.new(me.world, x, y, z)
      me.compass_target = destination
      # ---
      me.msg('Home set!')
    end
    
    public_command('dhome', 'check_home', '/dhome') do |me, *|
      home = @location_hash[me.display_name.split(']').last]
      if home == nil then
        me.msg('You are homeless!')
      else
        me.msg(neatify_home(home))
      end
    end
    
    public_command('dsuite', 'About the plugin', '/dsuite') do |me, *|
      me.msg('dSuite Plugins:')
      me.msg('---------------')
      me.msg('dHome:')
      me.msg('  /dhome - Tells you the coordinates of your home.')
      me.msg('  /dsethome - Sets your home to your current location.')
      me.msg('dLift')
    end
    
    event(:player_join) do |e|
      me = e.player
      home = @location_hash[me.display_name.split(']').last]
      if home != nil then
        x = home[:x].to_f
        y = home[:y].to_f
        z = home[:z].to_f
        destination = org.bukkit.Location.new(me.world, x, y, z)
        me.compass_target = destination
      end
    end
    
    event (:redstone_change) do |e|
      block = e.get_block
      if block.is? :sign_post and block.block_at(:down).is? :iron_block then
        signs = screen_setup(block.block_at(:down))
        if signs != nil then
          sign1_array = signs[0]
          sign2_array = signs[1]
          screen_sign = signs[2]
          if e.get_new_current == 0 then # Unpowered
            change_sign(screen_sign, sign1_array)
          else # Powered
            change_sign(screen_sign, sign2_array)
          end
        end
      end
    end
    
    event(:player_interact) do |e|
      player = e.player
      block = player.world.block_at(player.location).block_at(:down)
      clicked_block = e.clicked_block
      if block != nil and clicked_block != nil and block.is? :gold_block and clicked_block.is?(:stone_button) then
        # Standing on a gold block, clicking on a stone_button
        button_level = (clicked_block.location.to_a[1] - block.location.to_a[1]).to_i
        if button_level == 1 then
          next_block = check_for_blocks(block, :down, 10)
          if next_block != nil then
            player.msg('Going down')
            loc = player.eye_location
            next_block_loc = next_block.block_at(:up).location.to_a
            x = loc.to_a[0]
            y = next_block_loc[1]
            z = loc.to_a[2]
            destination = org.bukkit.Location.new(player.world, x, y, z, loc.yaw, loc.pitch)
            server.scheduler.schedule_sync_delayed_task(self) { player.teleport(destination) }
          end
        elsif button_level == 2 then
          next_block = check_for_blocks(block, :up, 10)
          if next_block != nil then
            player.msg('Going up')
            loc = player.eye_location
            next_block_loc = next_block.block_at(:up).location.to_a
            x = loc.to_a[0]
            y = next_block_loc[1]
            z = loc.to_a[2]
            destination = org.bukkit.Location.new(player.world, x, y, z, loc.yaw, loc.pitch)
            server.scheduler.schedule_sync_delayed_task(self) { player.teleport(destination) }
          end
        end
      end
    end
    
    event(:player_move) do |e|
      me = e.player
      block = me.world.block_at(e.to).block_at(:down)
      if block.is? :diamond_block # Teleport home
        home = @location_hash[me.display_name.split(']').last]
        if home != nil then
          x = home[:x].to_f
          y = home[:y].to_f
          z = home[:z].to_f
          loc = me.eye_location
          destination = org.bukkit.Location.new(me.world, x, y, z, loc.yaw, loc.pitch)
          server.scheduler.schedule_sync_delayed_task(self) { me.teleport(destination) }
        end
      end
    end
  end
end
