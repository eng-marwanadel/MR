# encoding: UTF-8
require 'sketchup.rb'
require 'tmpdir'
require 'base64'

module MR
  module ClassicToSolidPresetSwap

    DICT = "dynamic_attributes"
    IDENTITY = Geom::Transformation.new

    THICKNESS_DEFAULT_CM = 2.0
    THICKNESS_MAX_CM     = 5.0

    # ===================== Minimal Cursor (Door -> Arrow) =====================
    # 32x32 transparent PNG
    CURSOR_PNG_B64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAf0lEQVR4nO2VwQ7AIAhDddn//7K7LVtEwqQ4cW4F0V7rjGQqj4s0tqk0s5pTQ2QmKJ0xQqWQJ0bqg1c2x2b7x3wqvVJwQkY0G2yQj2A6mQ0o0cYcQGdE0a0y7wC0w2J6yqf8h2oAAAAASUVORK5CYII="

    def self.ensure_cursor_file!
      @cursor_file ||= begin
        path = File.join(Dir.tmpdir, "MR_classic_to_solid_cursor.png")
        unless File.exist?(path) && File.size(path) > 0
          File.binwrite(path, Base64.decode64(CURSOR_PNG_B64))
        end
        path
      rescue
        nil
      end
    end

    def self.cursor_id
      return @cursor_id if @cursor_id
      path = ensure_cursor_file!
      return nil unless path && File.exist?(path)
      # hotspot Ù‚Ø±ÙŠØ¨ Ù…Ù† Ø§Ù„Ø¨Ø§Ø¨
      @cursor_id = UI.create_cursor(path, 7, 7) rescue nil
    end

    # ===================== DC Engine =====================
    def self.dc_engine
      $dc_observers.get_latest_class rescue nil
    end

    def self.redraw(inst)
      dc = dc_engine
      return false unless dc
      if dc.respond_to?(:redraw_with_undo)
        dc.redraw_with_undo(inst)
      elsif dc.respond_to?(:redraw)
        dc.redraw(inst)
      else
        return false
      end
      true
    end

    # âœ… Ù…Ø¶Ù…ÙˆÙ†: Redraw Ù…Ø±ØªÙŠÙ† + invalidate view
    def self.force_refresh!(inst, view=nil)
      return false unless inst
      ok1 = redraw(inst)
      ok2 = redraw(inst)
      begin
        view.invalidate if view
        Sketchup.active_model.active_view.invalidate
        Sketchup.active_model.active_view.refresh rescue nil
      rescue
      end
      ok1 || ok2
    end

    # ===================== Picking (UNDER MOUSE ONLY) =====================
    def self.pick_under_mouse_path(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.path_at(0) rescue nil
    end

    def self.instances_in_path(path)
      return [] unless path && !path.empty?
      path.select { |e| e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group) }
    end

    # âœ… Template (classic): Ø®Ø¯ Ø§Ù„Ø±ÙˆØª Ù…Ù† Ø§Ù„Ù…Ø³Ø§Ø± ØªØ­Øª Ø§Ù„Ù…Ø§ÙˆØ³
    def self.pick_classic_root(path)
      insts = instances_in_path(path)
      insts.first
    end

    # âœ… Solid: Ù„Ø§Ø²Ù… ÙŠØ·Ù„Ø¹ instance Ø¹Ù†Ø¯Ù‡ LenX/LenY/LenZ ÙÙŠ Ù†ÙØ³ Ø§Ù„Ù…Ø³Ø§Ø± ØªØ­Øª Ø§Ù„Ù…Ø§ÙˆØ³
    # Ø¨Ø¯ÙˆÙ† fallback ØºÙ„Ø·.
    def self.pick_solid_lenxyz(path)
      insts = instances_in_path(path)
      return nil if insts.empty?

      keys_any = ["lenx","leny","lenz","lx","ly","lz","rotx","rotz"]

      insts.reverse.each do |inst|
        dict = inst.attribute_dictionary(DICT, false)
        next unless dict
        keys = dict.keys.map { |k| k.to_s.downcase }
        return inst if (keys & keys_any).any?
      end

      nil
    end

    def self.force_refresh_parent_from_path!(path, view=nil)
      insts = instances_in_path(path)
      return false if insts.empty?
      parent = insts.first
      return false unless parent
      force_refresh!(parent, view)
    end

    # ===================== Parse final value =====================
    def self.parse_length_to_inches(v)
      return nil if v.nil?
      return v.to_f if v.is_a?(Numeric)

      s = v.to_s.strip
      return nil if s.empty?
      return nil if s.start_with?("=")

      begin
        parsed = Sketchup.parse_length(s)
        return parsed.to_f if parsed
      rescue
      end

      return s.to_f if s =~ /-?\d+(\.\d+)?/
      nil
    end

    def self.get_final_len_inch(inst, key)
      dc = dc_engine
      if dc && dc.respond_to?(:get_attribute_value)
        begin
          v = dc.get_attribute_value(inst, key.to_s)
          got = parse_length_to_inches(v)
          return got unless got.nil?
        rescue
        end
      end
      v = inst.get_attribute(DICT, key.to_s, nil)
      parse_length_to_inches(v)
    end

    # ===================== Bounds / Anchor =====================
    def self.entities_bounds(ents)
      bb = Geom::BoundingBox.new
      ents.to_a.each do |e|
        next unless e.respond_to?(:bounds)
        b = e.bounds rescue nil
        next unless b
        bb.add(b.min)
        bb.add(b.max)
      end
      bb
    end

    def self.bb_valid?(bb)
      bb && bb.valid? && bb.diagonal > 0.0
    end

    def self.bb_anchor_corner(bb)
      return ORIGIN unless bb_valid?(bb)
      min = bb.min
      max = bb.max
      corners = []
      xs = [min.x, max.x]
      ys = [min.y, max.y]
      zs = [min.z, max.z]
      xs.each { |xx| ys.each { |yy| zs.each { |zz| corners << Geom::Point3d.new(xx,yy,zz) } } }
      corners.min_by { |p| p.distance(ORIGIN) } || ORIGIN
    end

    # ===================== Auto kind (NO POPUP) =====================
    def self.detect_kind_from_name(solid_inst)
      name = solid_inst.name.to_s.strip
      name = solid_inst.definition.name.to_s.strip if name.empty?
      n = name.downcase

      return :door_left  if n.include?("Ø´Ù…Ø§Ù„")
      return :door_right if n.include?("ÙŠÙ…ÙŠÙ†")
      return :flap       if n.include?("Ù‚Ù„Ø§Ø¨") || n.include?("Ù‚Ù„Ø¨")
      return :drawer     if n.include?("Ø¯Ø±Ø¬") || n.include?("Ø¯Ø±ÙˆØ¬")

      return :door_left  if n.include?("left")
      return :door_right if n.include?("right")
      return :flap       if n.include?("flap") || n.include?("lift") || n.include?("up")
      return :drawer     if n.include?("drawer")

      nil
    end

    def self.detect_solid_kind_by_keys(solid_inst)
      dict = solid_inst.attribute_dictionary(DICT, false)
      return nil unless dict
      keys = dict.keys.map { |k| k.to_s.downcase }
      return :door_left if keys.include?("rotz")
      return :flap      if keys.include?("rotx")
      return :drawer    if (keys.include?("lenx") || keys.include?("leny") || keys.include?("lenz") || keys.include?("lx") || keys.include?("ly") || keys.include?("lz"))
      nil
    end

    # âœ… Ø¨Ø¯ÙˆÙ† popup: Ù„Ùˆ Ù…Ø´ Ù…Ø¹Ø±ÙˆÙ = Drawer Ø§ÙØªØ±Ø§Ø¶ÙŠ
    def self.auto_kind(solid_inst)
      detect_kind_from_name(solid_inst) || detect_solid_kind_by_keys(solid_inst) || :drawer
    end

    def self.kind_to_label(kind)
      case kind
      when :door_left  then "Ø¯Ù„ÙØ© Ø´Ù…Ø§Ù„"
      when :door_right then "Ø¯Ù„ÙØ© ÙŠÙ…ÙŠÙ†"
      when :drawer     then "ÙˆØ´ Ø¯Ø±Ø¬"
      when :flap       then "Ù‚Ù„Ø§Ø¨"
      else "ÙˆØ´ Ø¯Ø±Ø¬"
      end
    end

    # ===================== Compute classic dims (X=width, Y=thickness, Z=height) =====================
    def self.compute_classic_dims_from_solid!(solid_inst, kind)
      sx = get_final_len_inch(solid_inst, "LenX") || get_final_len_inch(solid_inst, "lenx")
      sy = get_final_len_inch(solid_inst, "LenY") || get_final_len_inch(solid_inst, "leny")
      sz = get_final_len_inch(solid_inst, "LenZ") || get_final_len_inch(solid_inst, "lenz")
      raise "Ù…Ø´ Ù‚Ø§Ø¯Ø± Ø£Ù‚Ø±Ø£ LenX/LenY/LenZ (Ù‚ÙŠÙ… Ù†Ù‡Ø§Ø¦ÙŠØ©) Ù…Ù† Ø§Ù„Ø³ÙˆÙ„ÙŠØ¯." if sx.nil? || sy.nil? || sz.nil?

      vals = [sx.to_f, sy.to_f, sz.to_f]
      thr_in = THICKNESS_MAX_CM / 2.54
      default_thick_in = THICKNESS_DEFAULT_CM / 2.54

      smallest = vals.min
      thickness = (smallest <= thr_in) ? smallest : default_thick_in

      bigs = vals.sort.reverse
      bigA = bigs[0]
      bigB = bigs[1]

      if kind == :door_left || kind == :door_right
        height = bigA
        width  = bigB
      else
        width  = bigA
        height = bigB
      end

      [width, thickness, height]
    end

    # ===================== Orient (for drawers/flaps) =====================
    def self.axis_index_for_thickness(x_in, y_in, z_in)
      vals = [x_in, y_in, z_in].map(&:to_f)
      thr_in = THICKNESS_MAX_CM / 2.54
      idx = vals.index { |v| v <= thr_in }
      return idx unless idx.nil?
      vals.each_with_index.min[1]
    end

    def self.build_orient_tr_from_solid_axes(solid_inst)
      x = get_final_len_inch(solid_inst, "LenX") || get_final_len_inch(solid_inst, "lenx")
      y = get_final_len_inch(solid_inst, "LenY") || get_final_len_inch(solid_inst, "leny")
      z = get_final_len_inch(solid_inst, "LenZ") || get_final_len_inch(solid_inst, "lenz")
      raise "Ù…Ø´ Ù‚Ø§Ø¯Ø± Ø£Ù‚Ø±Ø£ LenX/LenY/LenZ Ù„ØªÙˆØ¬ÙŠÙ‡ Ø§Ù„Ù…Ø­Ø§ÙˆØ±." if x.nil? || y.nil? || z.nil?

      vals = [x.to_f, y.to_f, z.to_f]
      t_idx = axis_index_for_thickness(vals[0], vals[1], vals[2])

      idxs = [0,1,2] - [t_idx]
      big_sorted = idxs.sort_by { |i| -vals[i] }

      x_idx = big_sorted[0]
      z_idx = big_sorted[1]
      y_idx = t_idx

      axes = [
        Geom::Vector3d.new(1,0,0),
        Geom::Vector3d.new(0,1,0),
        Geom::Vector3d.new(0,0,1)
      ]
      tx = axes[x_idx]
      ty = axes[y_idx]
      tz = axes[z_idx]
      tz = tz.reverse if tx.cross(ty).dot(tz) < 0

      Geom::Transformation.axes(ORIGIN, tx, ty, tz)
    end

    def self.deep_explode_entities!(ents)
      loop do
        nested = ents.grep(Sketchup::Group) + ents.grep(Sketchup::ComponentInstance)
        break if nested.empty?
        nested.each { |i| i.explode rescue nil }
      end
    end

    # ===================== Core swap (ONE CLICK per solid) =====================
    def self.swap_once!(classic_template, solid_inst, solid_path, view)
      raise "Ù„Ø§ ÙŠÙˆØ¬Ø¯ Classic Template Ù…Ø­ÙÙˆØ¸." unless classic_template
      raise "Ù…Ø´ Ù‚Ø§Ø¯Ø± ÙŠØ­Ø¯Ø¯ Ø¶Ù„ÙØ© Ø³ÙˆÙ„ÙŠØ¯ (Ø¯ÙˆØ³ Ø¹Ù„Ù‰ Ø§Ù„Ø¶Ù„ÙØ© Ù†ÙØ³Ù‡Ø§)." unless solid_inst

      kind = auto_kind(solid_inst)
      label = kind_to_label(kind)

      model = Sketchup.active_model
      model.start_operation("MR: Swap Classic -> Solid (#{label})", true)

      # ---- 1) Apply sizes to classic template ----
      w, t, h = compute_classic_dims_from_solid!(solid_inst, kind)

      [["LenX", w], ["lenx", w], ["lx", w]].each { |k,v| classic_template.set_attribute(DICT, k, v) rescue nil }
      [["LenY", t], ["leny", t], ["ly", t]].each { |k,v| classic_template.set_attribute(DICT, k, v) rescue nil }
      [["LenZ", h], ["lenz", h], ["lz", h]].each { |k,v| classic_template.set_attribute(DICT, k, v) rescue nil }

      classic_template.set_attribute(DICT, "_dc_dirty", Time.now.to_i) rescue nil

      ok = redraw(classic_template)
      raise "Dynamic Components Ù…Ø´ Ù…ØªØ§Ø­ Ø£Ùˆ Redraw ÙØ´Ù„." unless ok

      # ---- 2) Replace geometry inside solid definition ----
      solid_def = solid_inst.definition
      raise "Ù…Ø´ Ù‚Ø§Ø¯Ø± Ø£ÙˆØµÙ„ Ù„ØªØ¹Ø±ÙŠÙ Ø¶Ù„ÙØ© Ø§Ù„Ø³ÙˆÙ„ÙŠØ¯." unless solid_def

      old_bb = entities_bounds(solid_def.entities)
      old_anchor = bb_anchor_corner(old_bb)

      solid_def.entities.to_a.each { |e| e.erase! rescue nil }

      base_tr =
        if kind == :drawer || kind == :flap
          build_orient_tr_from_solid_axes(solid_inst)
        else
          IDENTITY
        end

      mirror_tr =
        if kind == :door_right
          Geom::Transformation.scaling(ORIGIN, -1, 1, 1)
        else
          IDENTITY
        end

      tr = mirror_tr * base_tr

      # Flap: FlipX 180 + MirrorY (Ø§Ù„Ø­Ù„ÙŠØ§Øª Ù„Ø¨Ø±Ø§)
      if kind == :flap
        flip_x   = Geom::Transformation.rotation(ORIGIN, X_AXIS, 180.degrees)
        mirror_y = Geom::Transformation.scaling(ORIGIN, 1, -1, 1)
        tr = mirror_y * flip_x * tr
      end

      tmp = solid_def.entities.add_instance(classic_template.definition, tr)

      begin
        cdict = classic_template.attribute_dictionary(DICT, false)
        cdict&.each_pair { |k, v| tmp.set_attribute(DICT, k, v) }
      rescue
      end

      redraw(tmp)

      tmp.explode
      deep_explode_entities!(solid_def.entities)

      # anchor align
      new_bb = entities_bounds(solid_def.entities)
      new_anchor = bb_anchor_corner(new_bb)
      delta = old_anchor - new_anchor
      move_tr = Geom::Transformation.translation(delta)
      solid_def.entities.transform_entities(move_tr, solid_def.entities.to_a) rescue nil

      model.commit_operation

      # ---- 3) Guaranteed Refresh ----
      force_refresh!(solid_inst, view)
      force_refresh_parent_from_path!(solid_path, view) if solid_path
      force_refresh!(solid_inst, view)

      label
    rescue => e
      model.abort_operation rescue nil
      UI.messagebox("Ø­ØµÙ„ Ø®Ø·Ø£:\n#{e.class}\n#{e.message}")
      nil
    end

    # ===================== Tool (Template saved + ONE CLICK per solid) =====================
    def self.activate_tool
      Sketchup.active_model.select_tool(Tool.new)
    end

    class Tool
      def initialize
        @classic_template = nil
        @state = :pick_classic_once
        @last_esc_t = nil
        Sketchup.status_text = "â‘  Ù…Ø±Ø© ÙˆØ§Ø­Ø¯Ø©: Ø§Ø®ØªØ§Ø± Ø§Ù„Ø¶Ù„ÙØ© Ø§Ù„ÙƒÙ„Ø§Ø³ÙŠÙƒ (Template) â€” Ø¨Ø¹Ø¯Ù‡Ø§: ÙƒÙ„ÙŠÙƒ ÙˆØ§Ø­Ø¯ Ø¹Ù„Ù‰ Ø£ÙŠ Ø¶Ù„ÙØ© Ø³ÙˆÙ„ÙŠØ¯ ÙŠÙ†ÙØ° ÙƒÙ„Ù‡"
      end

      # âœ… Cursor Ø·ÙˆÙ„ Ù…Ø§ Ø§Ù„Ø£Ø¯Ø§Ø© Ø´ØºÙ‘Ø§Ù„Ø©
      def onSetCursor
        cid = ClassicToSolidPresetSwap.cursor_id
        return false unless cid
        UI.set_cursor(cid)
        true
      end

      # âœ… ESC Ù…Ø±Ø©: reset template | âœ… ESC Ù…Ø±ØªÙŠÙ† Ø³Ø±ÙŠØ¹: Ø®Ø±ÙˆØ¬ Ù…Ù† Ø§Ù„Ø£Ø¯Ø§Ø©
      def onKeyDown(key, repeat, flags, view)
        return unless key == 27
        now = Time.now.to_f
        if @last_esc_t && (now - @last_esc_t) <= 0.7
          Sketchup.active_model.select_tool(nil)
          Sketchup.status_text = "ØªÙ… Ø§Ù„Ø®Ø±ÙˆØ¬ Ù…Ù† Ø§Ù„Ø£Ø¯Ø§Ø©."
          return
        end
        @last_esc_t = now
        @classic_template = nil
        @state = :pick_classic_once
        Sketchup.status_text = "â‘  Ø§Ø®ØªØ§Ø± Ø§Ù„Ø¶Ù„ÙØ© Ø§Ù„ÙƒÙ„Ø§Ø³ÙŠÙƒ (Template) Ù…Ù† Ø¬Ø¯ÙŠØ¯ â€” (ESC Ù…Ø±ØªÙŠÙ† Ù„Ù„Ø®Ø±ÙˆØ¬)"
      end

      def onLButtonDown(flags, x, y, view)
        path = ClassicToSolidPresetSwap.pick_under_mouse_path(view, x, y)

        case @state
        when :pick_classic_once
          inst = ClassicToSolidPresetSwap.pick_classic_root(path)
          unless inst
            UI.beep
            Sketchup.status_text = "Ø¯ÙˆØ³ Ø¹Ù„Ù‰ Ø§Ù„Ø¶Ù„ÙØ© Ø§Ù„ÙƒÙ„Ø§Ø³ÙŠÙƒ Ù†ÙØ³Ù‡Ø§."
            return
          end
          @classic_template = inst
          @state = :click_solid_one
          Sketchup.status_text = "âœ… ØªÙ… Ø­ÙØ¸ Ø§Ù„Ù€ Template â€” Ø¯Ù„ÙˆÙ‚ØªÙŠ: ÙƒÙ„ÙŠÙƒ ÙˆØ§Ø­Ø¯ Ø¹Ù„Ù‰ Ø£ÙŠ Ø¶Ù„ÙØ© Ø³ÙˆÙ„ÙŠØ¯ ÙŠÙ†ÙØ° ÙƒÙ„Ù‡ | (ESC Ù„Ø¥Ø¹Ø§Ø¯Ø© Template / ESC Ù…Ø±ØªÙŠÙ† Ø®Ø±ÙˆØ¬)"

        when :click_solid_one
          solid = ClassicToSolidPresetSwap.pick_solid_lenxyz(path)
          unless solid
            UI.beep
            Sketchup.status_text = "Ø¯ÙˆØ³ Ø¹Ù„Ù‰ Ø§Ù„Ø¶Ù„ÙØ© Ø§Ù„Ø³ÙˆÙ„ÙŠØ¯ Ù†ÙØ³Ù‡Ø§ (Ø§Ù„Ù„ÙŠ ÙÙŠÙ‡Ø§ LenX/LenY/LenZ) ØªØ­Øª Ø§Ù„Ù…Ø§ÙˆØ³."
            return
          end

          label = ClassicToSolidPresetSwap.swap_once!(@classic_template, solid, path, view)
          if label
            Sketchup.status_text = "âœ… ØªÙ…: #{label} â€” Ø§Ø®ØªØ§Ø± Ø¶Ù„ÙØ© Ø³ÙˆÙ„ÙŠØ¯ ØªØ§Ù†ÙŠØ© (ÙƒÙ„ÙŠÙƒ ÙˆØ§Ø­Ø¯) | (ESC Ù„Ø¥Ø¹Ø§Ø¯Ø© Template / ESC Ù…Ø±ØªÙŠÙ† Ø®Ø±ÙˆØ¬)"
          else
            Sketchup.status_text = "âŒ Ø­ØµÙ„ Ø®Ø·Ø£ â€” Ø¬Ø±Ù‘Ø¨ ØªØ§Ù†ÙŠ."
          end
        end
      end
    end

  end
end

# ØªØ´ØºÙŠÙ„ Ø§Ù„Ø£Ø¯Ø§Ø©:
# MR::ClassicToSolidPresetSwap.activate_tool
